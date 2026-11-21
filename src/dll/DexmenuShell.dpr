library DexmenuShell;

// DexmenuShell.dll: Dexmenu's shell extension (docs/plans/01-PLAN-dexmenu.md, 02-PLAN-own-menu.md). 64-bit, built by
// build.cmd with Delphi's dcc64; the hook is DDetours (src/vendor/DDetours, MPL 2.0, unchanged).

uses
  System.Win.ComServ,
  Dexmenu.Log in 'Dexmenu.Log.pas',
  Dexmenu.Menus in 'Dexmenu.Menus.pas',
  Dexmenu.Json in 'Dexmenu.Json.pas',
  Dexmenu.Layout in 'Dexmenu.Layout.pas',
  Dexmenu.Tree in 'Dexmenu.Tree.pas',
  Dexmenu.Place in 'Dexmenu.Place.pas',
  Dexmenu.Draw in 'Dexmenu.Draw.pas',
  Dexmenu.Menu in 'Dexmenu.Menu.pas',
  Dexmenu.Hook in 'Dexmenu.Hook.pas',
  Dexmenu.Handler in 'Dexmenu.Handler.pas';

exports
  DllGetClassObject,
  DllCanUnloadNow,
  DllRegisterServer,
  DllUnregisterServer;

begin
end.
