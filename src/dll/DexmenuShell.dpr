library DexmenuShell;

// DexmenuShell.dll: Dexmenu's shell extension (docs/plans/01-PLAN-dexmenu.md, executed/02-PLAN-own-menu.md). 64-bit, built by
// build.cmd with Delphi's dcc64; the hook is DDetours (src/vendor/DDetours, MPL 2.0, unchanged).

uses
  System.Win.ComServ,
  Dexmenu.Log in 'Dexmenu.Log.pas',
  Dexmenu.Menus in 'Dexmenu.Menus.pas',
  Dexmenu.Json in 'Dexmenu.Json.pas',
  Dexmenu.Rules in 'Dexmenu.Rules.pas',
  Dexmenu.Layout in 'Dexmenu.Layout.pas',
  Dexmenu.Tree in 'Dexmenu.Tree.pas',
  Dexmenu.Place in 'Dexmenu.Place.pas',
  Dexmenu.Icons in 'Dexmenu.Icons.pas',
  Dexmenu.Theme in 'Dexmenu.Theme.pas',
  Dexmenu.Draw in 'Dexmenu.Draw.pas',
  Dexmenu.Seen in 'Dexmenu.Seen.pas',
  Dexmenu.Usage in 'Dexmenu.Usage.pas',
  Dexmenu.Timings in 'Dexmenu.Timings.pas',
  Dexmenu.Tip in 'Dexmenu.Tip.pas',
  Dexmenu.Menu in 'Dexmenu.Menu.pas',
  Dexmenu.Preview in 'Dexmenu.Preview.pas',
  Dexmenu.Hook in 'Dexmenu.Hook.pas',
  Dexmenu.Handler in 'Dexmenu.Handler.pas';

exports
  DllGetClassObject,
  DllCanUnloadNow,
  DllRegisterServer,
  DllUnregisterServer,
  DexmenuPreviewCreate,
  DexmenuPreviewSet,
  DexmenuBaseLayout,
  DexmenuPreviewSetCallback,
  DexmenuPreviewMark,
  DexmenuPreviewCounts,
  DexmenuSeenOfMenu,
  DexmenuSetTheme,
  DexmenuThemePalette,
  DexmenuThemePaletteOf;

begin
end.
