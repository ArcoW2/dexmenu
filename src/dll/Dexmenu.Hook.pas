unit Dexmenu.Hook;

// The hook (docs/plans/01-PLAN-dexmenu.md 3.1, 3.2, 3.4): the menus the handler noted, the show call caught
// (TrackPopupMenu, TrackPopupMenuEx) and a noted menu shown arranged; calls a program makes on its menu while it is
// shown arranged followed onto the arranged menu. Hooks set with DDetours the first time a menu is noted; the DLL is
// then pinned, so the hooks never point into an unloaded DLL.

interface

uses
  Winapi.Windows;

// A shell right-click menu being built (the handler's QueryContextMenu). Sets the hooks the first time.
procedure NoteMenu(Menu: HMENU; Flags: UINT);

implementation

uses
  System.SysUtils, System.StrUtils, System.SyncObjs, System.Generics.Collections, DDetours, Dexmenu.Log, Dexmenu.Menus,
  Dexmenu.Arrange;

const
  GET_MODULE_HANDLE_EX_FLAG_PIN = $00000001;
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS = $00000004;

function GetModuleHandleEx(Flags: DWORD; Name: Pointer; out Module: HMODULE): BOOL; stdcall;
  external kernel32 name 'GetModuleHandleExW';

type
  TTrackPopupMenuEx =function(Menu: HMENU; Flags: UINT; X, Y: Integer; Wnd: HWND; Params: PTPMParams): BOOL; stdcall;
  TTrackPopupMenu = function(Menu: HMENU; Flags: UINT; X, Y, Reserved: Integer; Wnd: HWND; Rect: PRect): BOOL; stdcall;
  TEnableMenuItem = function(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
  TMenuItemInfoCall = function(Menu: HMENU; Item: UINT; ByPosition: BOOL; Info: PMenuItemInfoW): BOOL; stdcall;
  TDeleteMenu = function(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
  TModifyMenuW = function(Menu: HMENU; Item, Flags: UINT; NewId: UINT_PTR; NewText: PWideChar): BOOL; stdcall;
  TCheckMenuItem = function(Menu: HMENU; Item, Flags: UINT): DWORD; stdcall;
  TShow = reference to function(Menu: HMENU): BOOL;

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
  HooksLock: TCriticalSection;
  HooksTried, HooksSet: Boolean;

  // The arranged menu being shown, if any, and the thread showing it; only that thread redirects.
  ActiveLock: TCriticalSection;
  Active: TArranged;
  ActiveThread: DWORD;
  ActiveTrace: Boolean;

threadvar
  Own: Boolean;   // Dexmenu's own menu calls (arranging, putting back): not traced or redirected

function TakeNoted(Menu: HMENU): Boolean;
begin
  NotedLock.Enter;
  try
    Result := Noted.Remove(Menu) >= 0;
  finally
    NotedLock.Leave;
  end;
end;

// ---- changes made while an arranged menu is shown (plan 01 3.4) ----------------------------------------------------
// A call by id on Windows' menu, from the thread showing it, is made on the arranged menu instead (a search by id
// covers the user's submenus), and the saved item follows it, so Windows' menu is put back with the change. A group
// left empty goes. Calls by position cannot be mapped and are left as they are. With Trace on, every call is logged.

function Target(Menu: HMENU; ByPosition: Boolean): HMENU;
begin
  Result := Menu;
  if Own or ByPosition or (GetCurrentThreadId <> ActiveThread) then
    Exit;
  ActiveLock.Enter;
  try
    if (Active <> nil) and (Menu = Active.Original) then
      Result := Active.Shown;
  finally
    ActiveLock.Leave;
  end;
end;

procedure Follow(Id: UINT; Gone: Boolean);
var
  A: TArranged;
  I, G, P: Integer;
  Now: TItem;
  Group: HMENU;
begin
  A := Active;   // only the showing thread redirects, and only while it shows
  if A = nil then
    Exit;
  Own := True;
  try
    for I := 0 to A.Items.Count - 1 do
    begin
      if IsSeparator(A.Items[I]) or (A.Items[I].Info.wID <> Id) then
        Continue;
      if Gone then
        A.Items.Delete(I)
      else if ReadItem(A.Shown, Id, False, Now) then
        A.Items[I] := Now;
      Break;
    end;
    if Gone then
      for G := A.Made.Count - 1 downto 1 do
      begin
        Group := A.Made[G];
        if GetMenuItemCount(Group) <> 0 then
          Continue;
        for P := GetMenuItemCount(A.Shown) - 1 downto 0 do
          if GetSubMenu(A.Shown, P) = Group then
            RemoveMenu(A.Shown, P, MF_BYPOSITION);
        DestroyMenu(Group);
        A.Made.Delete(G);
      end;
  finally
    Own := False;
  end;
end;

function RoleOf(Menu: HMENU): string;
var
  M: HMENU;
  Item: TItem;
begin
  if Active = nil then
    Exit('?');
  if Menu = Active.Original then
    Exit('ORIGINAL');
  if Menu = Active.Shown then
    Exit('arranged');
  for M in Active.Made do
    if M = Menu then
      Exit('group');
  for Item in Active.Items do
    if Item.Info.hSubMenu = Menu then
      Exit('windows-submenu');
  Result := 'other';
end;

procedure TraceCall(const Call: string; Menu: HMENU; Item: UINT; ByPosition: Boolean; const What: string;
  Result: Integer);
var
  Role: string;
  On: Boolean;
begin
  if Own then
    Exit;
  ActiveLock.Enter;
  try
    On := (Active <> nil) and ActiveTrace;
    if On then
      Role := RoleOf(Menu);
  finally
    ActiveLock.Leave;
  end;
  if not On then
    Exit;
  Own := True;
  try
    Log(Format('  call %s thread=%u menu=%s (%s) %s=%u %s -> %d', [Call, GetCurrentThreadId, Hex(Menu), Role,
      IfThen(ByPosition, 'pos', 'id'), Item, What, Result]));
  finally
    Own := False;
  end;
end;

function InfoText(Info: PMenuItemInfoW): string;
begin
  if Info = nil then
    Exit('null');
  Result := Format('mask=0x%x type=0x%x state=0x%x id=%u', [Info.fMask, Info.fType, Info.fState, Info.wID]);
end;

function Redirected(T, Menu: HMENU): string;
begin
  if T <> Menu then
    Result := ' redirected'
  else
    Result := '';
end;

// Each call: made on its target (Target), traced, and for a redirected one the saved item follows (Follow).
function HookEnableMenuItem(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
var
  T: HMENU;
begin
  T := Target(Menu, Flags and MF_BYPOSITION <> 0);
  Result := RealEnableMenuItem(T, Item, Flags);
  TraceCall('EnableMenuItem', Menu, Item, Flags and MF_BYPOSITION <> 0, Format('flags=0x%x', [Flags]) +
    Redirected(T, Menu), Integer(Result));
  if (T <> Menu) and (Integer(Result) <> -1) then
    Follow(Item, False);
end;

function HookSetMenuItemInfoW(Menu: HMENU; Item: UINT; ByPosition: BOOL; Info: PMenuItemInfoW): BOOL; stdcall;
var
  T: HMENU;
  Id: UINT;
begin
  T := Target(Menu, ByPosition);
  Result := RealSetMenuItemInfoW(T, Item, ByPosition, Info);
  TraceCall('SetMenuItemInfoW', Menu, Item, ByPosition, InfoText(Info) + Redirected(T, Menu), Ord(Result));
  if (T <> Menu) and Result then
  begin
    Id := Item;
    if (Info <> nil) and (Info.fMask and MIIM_ID <> 0) then
      Id := Info.wID;
    Follow(Id, False);
  end;
end;

function HookInsertMenuItemW(Menu: HMENU; Item: UINT; ByPosition: BOOL; Info: PMenuItemInfoW): BOOL; stdcall;
begin
  Result := RealInsertMenuItemW(Menu, Item, ByPosition, Info);
  TraceCall('InsertMenuItemW', Menu, Item, ByPosition, InfoText(Info), Ord(Result));
end;

function HookDeleteMenu(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
var
  T: HMENU;
begin
  T := Target(Menu, Flags and MF_BYPOSITION <> 0);
  Result := RealDeleteMenu(T, Item, Flags);
  TraceCall('DeleteMenu', Menu, Item, Flags and MF_BYPOSITION <> 0, Redirected(T, Menu), Ord(Result));
  if (T <> Menu) and Result then
    Follow(Item, True);
end;

function HookRemoveMenu(Menu: HMENU; Item, Flags: UINT): BOOL; stdcall;
var
  T: HMENU;
begin
  T := Target(Menu, Flags and MF_BYPOSITION <> 0);
  Result := RealRemoveMenu(T, Item, Flags);
  TraceCall('RemoveMenu', Menu, Item, Flags and MF_BYPOSITION <> 0, Redirected(T, Menu), Ord(Result));
  if (T <> Menu) and Result then
    Follow(Item, True);
end;

function HookModifyMenuW(Menu: HMENU; Item, Flags: UINT; NewId: UINT_PTR; NewText: PWideChar): BOOL; stdcall;
var
  T: HMENU;
begin
  T := Target(Menu, Flags and MF_BYPOSITION <> 0);
  Result := RealModifyMenuW(T, Item, Flags, NewId, NewText);
  TraceCall('ModifyMenuW', Menu, Item, Flags and MF_BYPOSITION <> 0, Format('flags=0x%x newid=%u', [Flags, NewId]) +
    Redirected(T, Menu), Ord(Result));
  if (T <> Menu) and Result then
    if Flags and MF_POPUP <> 0 then
      Follow(Item, False)
    else
      Follow(UINT(NewId), False);
end;

function HookCheckMenuItem(Menu: HMENU; Item, Flags: UINT): DWORD; stdcall;
var
  T: HMENU;
begin
  T := Target(Menu, Flags and MF_BYPOSITION <> 0);
  Result := RealCheckMenuItem(T, Item, Flags);
  TraceCall('CheckMenuItem', Menu, Item, Flags and MF_BYPOSITION <> 0, Format('flags=0x%x', [Flags]) +
    Redirected(T, Menu), Integer(Result));
  if (T <> Menu) and (Result <> DWORD(-1)) then
    Follow(Item, False);
end;

// ---- the show call ---------------------------------------------------------------------------------------------

function ShowArranged(Menu: HMENU; const Show: TShow): BOOL;
var
  Trace, Done: Boolean;
  A: TArranged;
begin
  Trace := Tracing;
  if not TakeNoted(Menu) or not Enabled then
  begin
    if Trace then
      Log(Format('show %s (%d items): not noted, passed through', [Hex(Menu), GetMenuItemCount(Menu)]));
    Exit(Show(Menu));
  end;
  A := TArranged.Create(Menu);
  try
    Own := True;
    try
      try
        Done := Arrange(A);
      except
        Done := False;
      end;
    finally
      Own := False;
    end;
    if Trace then
      if Done then
        Log(Format('show %s (%d items): noted, arranged into %d items', [Hex(Menu), A.Items.Count,
          GetMenuItemCount(A.Shown)]))
      else
        Log(Format('show %s (%d items): noted, nothing to arrange', [Hex(Menu), A.Items.Count]));
    if not Done then
    begin
      if A.Made.Count > 0 then
        Log('arranging failed; Windows'' menu shown');
      Own := True;
      try
        Restore(A);
      finally
        Own := False;
      end;
      Exit(Show(Menu));
    end;
    ActiveLock.Enter;
    Active := A;
    ActiveThread := GetCurrentThreadId;
    ActiveTrace := Trace;
    ActiveLock.Leave;
    try
      Result := Show(A.Shown);
    finally
      ActiveLock.Enter;
      Active := nil;
      ActiveThread := 0;
      ActiveLock.Leave;
    end;
    if Trace then
      Log(Format('show %s closed, returned %d', [Hex(Menu), Ord(Result)]));
    Own := True;
    try
      Restore(A);
    finally
      Own := False;
    end;
  finally
    A.Free;
  end;
end;

function HookTrackPopupMenuEx(Menu: HMENU; Flags: UINT; X, Y: Integer; Wnd: HWND; Params: PTPMParams): BOOL; stdcall;
begin
  Result := ShowArranged(Menu,
    function(M: HMENU): BOOL
    begin
      Result := RealTrackPopupMenuEx(M, Flags, X, Y, Wnd, Params);
    end);
end;

function HookTrackPopupMenu(Menu: HMENU; Flags: UINT; X, Y, Reserved: Integer; Wnd: HWND; Rect: PRect): BOOL; stdcall;
begin
  Result := ShowArranged(Menu,
    function(M: HMENU): BOOL
    begin
      Result := RealTrackPopupMenu(M, Flags, X, Y, Reserved, Wnd, Rect);
    end);
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

procedure NoteMenu(Menu: HMENU; Flags: UINT);
var
  I: Integer;
begin
  if (Flags and $00000001 <> 0) or not Enabled or not SetHooks then   // CMF_DEFAULTONLY: a double-click, no menu
    Exit;
  NotedLock.Enter;
  try
    for I := Noted.Count - 1 downto 0 do
      if not IsMenu(Noted[I]) then
        Noted.Delete(I);
    if Noted.IndexOf(Menu) < 0 then
      Noted.Add(Menu);
  finally
    NotedLock.Leave;
  end;
  if Tracing then
    Log(Format('noted %s (%d items so far, flags %u)', [Hex(Menu), GetMenuItemCount(Menu), Flags]));
end;

initialization
  NotedLock := TCriticalSection.Create;
  Noted := TList<HMENU>.Create;
  HooksLock := TCriticalSection.Create;
  ActiveLock := TCriticalSection.Create;

end.
