unit Dexmenu.Hook;

// The hook (docs/plans/01-PLAN-dexmenu.md 3.1, 3.2; plan 02 3.1; plan 00 step 3): the menus the handler noted, the
// show call caught (TrackPopupMenu, TrackPopupMenuEx) and a noted menu shown as Dexmenu's own menu (Dexmenu.Menu)
// laid out by the layout. Windows' own menu when Dexmenu is off, the layout cannot be used, or anything fails before
// Dexmenu's menu shows. Changes a program makes on its menu while Dexmenu's menu is shown (Explorer sets Explorer
// commands' states then) are made on Windows' menu as always, and make Dexmenu's menu read it again. Hooks set with
// DDetours the first time a menu is noted; the DLL is then pinned, so the hooks never point into an unloaded DLL.

interface

uses
  Winapi.Windows;

// A shell right-click menu being built (the handler's QueryContextMenu). Sets the hooks the first time. Where: the
// right-click as the preview can repeat it (Dexmenu.Seen.RightClickJson), '' when it cannot; written to the last
// right-click after Dexmenu's menu for it was shown.
procedure NoteMenu(Menu: HMENU; Flags: UINT; const Kind, Where: string);

implementation

uses
  System.SysUtils, System.StrUtils, System.SyncObjs, System.Generics.Collections, DDetours, Dexmenu.Log,
  Dexmenu.Layout, Dexmenu.Menu, Dexmenu.Seen;

const
  GET_MODULE_HANDLE_EX_FLAG_PIN = $00000001;
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS = $00000004;

function GetModuleHandleEx(Flags: DWORD; Name: Pointer; out Module: HMODULE): BOOL; stdcall;
  external kernel32 name 'GetModuleHandleExW';

type
  TTrackPopupMenuEx = function(Menu: HMENU; Flags: UINT; X, Y: Integer; Wnd: HWND; Params: PTPMParams): BOOL; stdcall;
  TTrackPopupMenu = function(Menu: HMENU; Flags: UINT; X, Y, Reserved: Integer; Wnd: HWND; Rect: PRect): BOOL; stdcall;
  TEnableMenuItem = function(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
  TMenuItemInfoCall = function(Menu: HMENU; Item: UINT; ByPosition: BOOL; Info: PMenuItemInfoW): BOOL; stdcall;
  TDeleteMenu = function(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
  TModifyMenuW = function(Menu: HMENU; Item, Flags: UINT; NewId: UINT_PTR; NewText: PWideChar): BOOL; stdcall;
  TCheckMenuItem = function(Menu: HMENU; Item, Flags: UINT): DWORD; stdcall;

var
  RealTrackPopupMenuEx: TTrackPopupMenuEx;
  RealTrackPopupMenu: TTrackPopupMenu;
  RealEnableMenuItem: TEnableMenuItem;
  RealSetMenuItemInfoW: TMenuItemInfoCall;
  RealInsertMenuItemW: TMenuItemInfoCall;
  RealDeleteMenu: TDeleteMenu;
  RealRemoveMenu: TDeleteMenu;
  RealModifyMenuW: TModifyMenuW;
  RealCheckMenuItem: TCheckMenuItem;

  NotedLock: TCriticalSection;
  Noted: TList<HMENU>;
  NotedKinds: TList<string>;   // the kind of right-click of each noted menu
  NotedWhere: TList<string>;   // and where it was (NoteMenu)
  HooksLock: TCriticalSection;
  HooksTried, HooksSet: Boolean;

function TakeNoted(Menu: HMENU; out Kind, Where: string): Boolean;
var
  I: Integer;
begin
  NotedLock.Enter;
  try
    I := Noted.IndexOf(Menu);
    Result := I >= 0;
    if Result then
    begin
      Kind := NotedKinds[I];
      Where := NotedWhere[I];
      Noted.Delete(I);
      NotedKinds.Delete(I);
      NotedWhere.Delete(I);
    end;
  finally
    NotedLock.Leave;
  end;
end;

// ---- changes made while Dexmenu's menu is shown --------------------------------------------------------------------

procedure Changed(const Call: string; Menu: HMENU; Item: UINT; ByPosition: Boolean; Result: Integer);
var
  S: TMenuSession;
begin
  S := ActiveSession;   // only on the thread showing the menu
  if S = nil then
    Exit;
  if Tracing then
    Log(Format('  call %s menu=%s%s %s=%u -> %d', [Call, Hex(Menu), IfThen(Menu = S.Original, ' (ORIGINAL)', ''),
      IfThen(ByPosition, 'pos', 'id'), Item, Result]));
  S.Changed(Menu);
end;

function HookEnableMenuItem(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
begin
  Result := RealEnableMenuItem(Menu, Item, Flags);
  Changed('EnableMenuItem', Menu, Item, Flags and MF_BYPOSITION <> 0, Integer(Result));
end;

function HookSetMenuItemInfoW(Menu: HMENU; Item: UINT; ByPosition: BOOL; Info: PMenuItemInfoW): BOOL; stdcall;
begin
  Result := RealSetMenuItemInfoW(Menu, Item, ByPosition, Info);
  Changed('SetMenuItemInfoW', Menu, Item, ByPosition, Ord(Result));
end;

function HookInsertMenuItemW(Menu: HMENU; Item: UINT; ByPosition: BOOL; Info: PMenuItemInfoW): BOOL; stdcall;
begin
  Result := RealInsertMenuItemW(Menu, Item, ByPosition, Info);
  Changed('InsertMenuItemW', Menu, Item, ByPosition, Ord(Result));
end;

function HookDeleteMenu(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
begin
  Result := RealDeleteMenu(Menu, Item, Flags);
  Changed('DeleteMenu', Menu, Item, Flags and MF_BYPOSITION <> 0, Ord(Result));
end;

function HookRemoveMenu(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
begin
  Result := RealRemoveMenu(Menu, Item, Flags);
  Changed('RemoveMenu', Menu, Item, Flags and MF_BYPOSITION <> 0, Ord(Result));
end;

function HookModifyMenuW(Menu: HMENU; Item, Flags: UINT; NewId: UINT_PTR; NewText: PWideChar): BOOL; stdcall;
begin
  Result := RealModifyMenuW(Menu, Item, Flags, NewId, NewText);
  Changed('ModifyMenuW', Menu, Item, Flags and MF_BYPOSITION <> 0, Ord(Result));
end;

function HookCheckMenuItem(Menu: HMENU; Item, Flags: UINT): DWORD; stdcall;
begin
  Result := RealCheckMenuItem(Menu, Item, Flags);
  Changed('CheckMenuItem', Menu, Item, Flags and MF_BYPOSITION <> 0, Integer(Result));
end;

// ---- the show call ---------------------------------------------------------------------------------------------

// Dexmenu's menu for a noted menu; Shown False when Windows' menu has to be shown instead.
function ShowOwn(Menu: HMENU; Flags: UINT; X, Y: Integer; Owner: HWND; Params: PTPMParams; out Shown: Boolean): BOOL;
var
  Layout: ILayout;
  Error: string;
  Session: TMenuSession;
  Kind, Where: string;
begin
  Result := False;
  Shown := False;
  if not TakeNoted(Menu, Kind, Where) or not Enabled or (ActiveSession <> nil) then
  begin
    if Tracing then
      Log(Format('show %s (%d items): not noted, passed through', [Hex(Menu), GetMenuItemCount(Menu)]));
    Exit;
  end;
  Layout := CurrentLayout(Error);
  if Layout = nil then
  begin
    Log('Windows'' menu shown: ' + Error);
    Exit;
  end;
  if Tracing then
    Log(Format('show %s (%d items): Dexmenu''s menu, kind %s, layout %s', [Hex(Menu), GetMenuItemCount(Menu), Kind,
      Layout.Source]));
  Session := TMenuSession.Create(Menu, Owner, Flags, Layout, Kind);
  try
    Shown := True;
    Result := Session.Run(X, Y, Params);
  finally
    Session.Free;
  end;
  if Where <> '' then
    WriteLastRightClick(Where);   // the settings app's preview starts on it
  if Tracing then
    Log(Format('show %s closed, returned %d', [Hex(Menu), Integer(Result)]));
end;

function HookTrackPopupMenuEx(Menu: HMENU; Flags: UINT; X, Y: Integer; Wnd: HWND; Params: PTPMParams): BOOL; stdcall;
var
  Shown: Boolean;
begin
  try
    Result := ShowOwn(Menu, Flags, X, Y, Wnd, Params, Shown);
  except
    on E: Exception do
    begin
      Log('Dexmenu''s menu failed: ' + E.Message);
      Shown := False;
      Result := False;
    end;
  end;
  if not Shown then
    Result := RealTrackPopupMenuEx(Menu, Flags, X, Y, Wnd, Params);
end;

function HookTrackPopupMenu(Menu: HMENU; Flags: UINT; X, Y, Reserved: Integer; Wnd: HWND; Rect: PRect): BOOL; stdcall;
var
  Shown: Boolean;
begin
  try
    Result := ShowOwn(Menu, Flags, X, Y, Wnd, nil, Shown);
  except
    on E: Exception do
    begin
      Log('Dexmenu''s menu failed: ' + E.Message);
      Shown := False;
      Result := False;
    end;
  end;
  if not Shown then
    Result := RealTrackPopupMenu(Menu, Flags, X, Y, Reserved, Wnd, Rect);
end;

// ---- setting the hooks -------------------------------------------------------------------------------------------

function SetHooks: Boolean;
var
  Module: HMODULE;
begin
  HooksLock.Enter;
  try
    if not HooksTried then
    begin
      HooksTried := True;
      // Kept loaded from now on: the hooks point into this DLL.
      GetModuleHandleEx(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS or GET_MODULE_HANDLE_EX_FLAG_PIN, @SetHooks, Module);
      @RealTrackPopupMenuEx := InterceptCreate(user32, 'TrackPopupMenuEx', @HookTrackPopupMenuEx);
      @RealTrackPopupMenu := InterceptCreate(user32, 'TrackPopupMenu', @HookTrackPopupMenu);
      @RealEnableMenuItem := InterceptCreate(user32, 'EnableMenuItem', @HookEnableMenuItem);
      @RealSetMenuItemInfoW := InterceptCreate(user32, 'SetMenuItemInfoW', @HookSetMenuItemInfoW);
      @RealInsertMenuItemW := InterceptCreate(user32, 'InsertMenuItemW', @HookInsertMenuItemW);
      @RealDeleteMenu := InterceptCreate(user32, 'DeleteMenu', @HookDeleteMenu);
      @RealRemoveMenu := InterceptCreate(user32, 'RemoveMenu', @HookRemoveMenu);
      @RealModifyMenuW := InterceptCreate(user32, 'ModifyMenuW', @HookModifyMenuW);
      @RealCheckMenuItem := InterceptCreate(user32, 'CheckMenuItem', @HookCheckMenuItem);
      HooksSet := Assigned(RealTrackPopupMenuEx) and Assigned(RealTrackPopupMenu) and Assigned(RealEnableMenuItem)
        and Assigned(RealSetMenuItemInfoW) and Assigned(RealInsertMenuItemW) and Assigned(RealDeleteMenu)
        and Assigned(RealRemoveMenu) and Assigned(RealModifyMenuW) and Assigned(RealCheckMenuItem);
      if not HooksSet then
        Log('hooks not set');
    end;
    Result := HooksSet;
  finally
    HooksLock.Leave;
  end;
end;

// The settings app builds Windows' real menu for its preview, so Dexmenu's handler runs in it too, maybe from another
// copy of this DLL (the registered one) than the one the app loads itself: the app says it is the editor in its
// environment (DEXMENU_EDITOR=1), which every copy reads. There the handler notes nothing and sets no hook.
function InEditor: Boolean;
var
  Env: array[0..7] of Char;
begin
  Result := (GetEnvironmentVariable('DEXMENU_EDITOR', Env, Length(Env)) > 0) and (Env[0] = '1');
end;

procedure NoteMenu(Menu: HMENU; Flags: UINT; const Kind, Where: string);
var
  I: Integer;
begin
  if InEditor or (Flags and $00000001 <> 0) or not Enabled or not SetHooks then   // CMF_DEFAULTONLY: a double-click, no menu
    Exit;
  NotedLock.Enter;
  try
    for I := Noted.Count - 1 downto 0 do
      if not IsMenu(Noted[I]) then
      begin
        Noted.Delete(I);
        NotedKinds.Delete(I);
        NotedWhere.Delete(I);
      end;
    I := Noted.IndexOf(Menu);
    if I < 0 then
    begin
      Noted.Add(Menu);
      NotedKinds.Add(Kind);
      NotedWhere.Add(Where);
    end
    else
    begin
      NotedKinds[I] := Kind;
      NotedWhere[I] := Where;
    end;
  finally
    NotedLock.Leave;
  end;
  if Tracing then
    Log(Format('noted %s (%d items so far, flags %u, kind %s)', [Hex(Menu), GetMenuItemCount(Menu), Flags, Kind]));
end;

initialization
  NotedLock := TCriticalSection.Create;
  Noted := TList<HMENU>.Create;
  NotedKinds := TList<string>.Create;
  NotedWhere := TList<string>.Create;
  HooksLock := TCriticalSection.Create;

end.
