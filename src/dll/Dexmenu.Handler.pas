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

function TDexmenuHandler.ShellInit(pidlFolder: PItemIDList; lpdobj: IDataObject; hKeyProgID: HKEY): HResult;
begin
  Result := S_OK;
end;

function TDexmenuHandler.QueryContextMenu(Menu: HMENU; indexMenu, idCmdFirst, idCmdLast, uFlags: UINT): HResult;
begin
  try
    NoteMenu(Menu, uFlags);
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
