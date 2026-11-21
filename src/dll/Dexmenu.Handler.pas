unit Dexmenu.Handler;

// The context menu handler (docs/plans/01-PLAN-dexmenu.md 3.1): loaded with every shell right-click menu for the
// kinds register.ps1 registers it for. It adds nothing; its QueryContextMenu notes the menu being built (Dexmenu.Hook).

interface

uses
  Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj, System.Win.ComObj;

const
  CLSID_Dexmenu: TGUID = '{CD4EEF01-47D9-4172-A48A-F6E61850D170}';

type
  TDexmenuHandler = class(TComObject, IShellExtInit, IContextMenu)
  private
    FKind: string;   // the kind of right-click (KindOf)
  protected
    function IShellExtInit.Initialize = ShellInit;
    function ShellInit(pidlFolder: PItemIDList; lpdobj: IDataObject; hKeyProgID: HKEY): HResult; stdcall;
    function QueryContextMenu(Menu: HMENU; indexMenu, idCmdFirst, idCmdLast, uFlags: UINT): HResult; stdcall;
    function InvokeCommand(var lpici: TCMInvokeCommandInfo): HResult; stdcall;
    function GetCommandString(idCmd: UINT_PTR; uFlags: UINT; pwReserved: PUINT; pszName: LPSTR;
      cchMax: UINT): HResult; stdcall;
  end;

implementation

uses
  System.Win.ComServ, Dexmenu.Hook;

// The kind of right-click (docs/plans/02-PLAN-own-menu.md 3.5): a folder's empty part (no items), several items, a
// drive, a folder or a file; 'default' when it cannot be told.
function KindOf(DataObject: IDataObject): string;
var
  Items: IShellItemArray;
  Item: IShellItem;
  Count: DWORD;
  Attributes: DWORD;
  Raw: Pointer;
  Path: PWideChar;
begin
  if DataObject = nil then
    Exit('background');
  Raw := nil;
  if Failed(SHCreateShellItemArrayFromDataObject(DataObject, IShellItemArray, Raw)) then
    Exit('default');
  Items := IShellItemArray(Raw);
  IUnknown(Raw)._Release;   // the cast above took its own reference
  if Failed(Items.GetCount(Count)) or (Count = 0) then
    Exit('default');
  if Count > 1 then
    Exit('several');
  if Failed(Items.GetItemAt(0, Item)) or Failed(Item.GetAttributes(SFGAO_FOLDER, Attributes)) then
    Exit('default');
  if Attributes and SFGAO_FOLDER = 0 then
    Exit('file');
  Result := 'folder';
  if Succeeded(Item.GetDisplayName(SIGDN_FILESYSPATH, Path)) then
  begin
    if (Length(string(Path)) = 3) and (Path[1] = ':') then
      Result := 'drive';
    CoTaskMemFree(Path);
  end;
end;

function TDexmenuHandler.ShellInit(pidlFolder: PItemIDList; lpdobj: IDataObject; hKeyProgID: HKEY): HResult;
begin
  try
    FKind := KindOf(lpdobj);
  except
    FKind := 'default';
  end;
  Result := S_OK;
end;

function TDexmenuHandler.QueryContextMenu(Menu: HMENU; indexMenu, idCmdFirst, idCmdLast, uFlags: UINT): HResult;
begin
  try
    if FKind = '' then
      FKind := 'default';
    NoteMenu(Menu, uFlags, FKind);
  except
    // never let an error reach the program building the menu
  end;
  Result := MakeResult(SEVERITY_SUCCESS, 0, 0);   // no items of its own
end;

function TDexmenuHandler.InvokeCommand(var lpici: TCMInvokeCommandInfo): HResult;
begin
  Result := E_FAIL;
end;

function TDexmenuHandler.GetCommandString(idCmd: UINT_PTR; uFlags: UINT; pwReserved: PUINT; pszName: LPSTR;
  cchMax: UINT): HResult;
begin
  Result := E_INVALIDARG;
end;

initialization
  TComObjectFactory.Create(ComServer, TDexmenuHandler, CLSID_Dexmenu, 'Dexmenu', 'Dexmenu context menu handler',
    ciMultiInstance, tmApartment);

end.
