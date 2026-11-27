# Dexmenu

Your own right-click menu for Windows. Instead of Windows' long list, Explorer shows a menu you build yourself from
layouts: cards, submenus, notes and themes, with the items of Windows and other programs placed where you want them.
A Delphi shell extension (the menu) and a WinForms host with a WebView2 page (the settings), as Foldex and LexPen.

## Features

- **Your own layouts**: cards and submenus you arrange by dragging, rules that collect Windows' and other programs'
  items into them, notes, dividers, icons and images; a layout per kind of right-click (a file, a folder, a folder's
  empty part, a drive, ...).
- **Your own look**: a theme for when Windows is light and one for when it is dark; text size (also Ctrl+scroll in the
  open menu), menu widths, marks on submenus and items.
- **Submenus your way**: next to their card, under it, or in place of the menu (<< back); on hover or only on a click.
- **Windows' menu still there**: hold Shift while right-clicking for Windows' own menu (in Explorer its extended
  menu).
- **Diagnostics**: which programs make your right-click slow, measured per program, each with a switch to turn its
  menu extension off.

## Install

Download `Dexmenu-<version>-win-x64.zip` from [Releases](https://github.com/ArcoW2/dexmenu/releases) and extract it to
a folder that stays (for example `C:\Apps\Dexmenu`): Explorer loads `DexmenuShell.dll` from there. Run
`DexmenuSettings.exe`, click **Register** (General), then **Restart Explorer**. Registration is for your user only;
no administrator rights needed. No installer.

To remove: **Unregister**, **Restart Explorer**, then delete the folder.

## Requirements

- Windows 10 or 11 (x64)
- .NET 10 Desktop Runtime and the Microsoft Edge WebView2 Runtime (included with Windows 11), for the settings window;
  the menu in Explorer needs neither

To build: Delphi (its 64-bit compiler, `dcc64`), Visual Studio's C++ tools (Desktop development with C++, for the
test host) and the .NET 10 SDK.

## Build and run

From the top folder:

```powershell
cmd /c .\build.cmd              # the DLL, the unit tests, the test host and the settings app, into bin
bin\DexmenuUnitTests.exe        # unit tests of the DLL
bin\DexmenuSettings.exe         # the settings app
dotnet publish src\settings\Dexmenu.Settings.csproj -c Release -o release\bin   # a release build (after build.cmd)
```

`build.cmd` finds Delphi through the registry, or `DELPHI_ROOT`. Explorer keeps a DLL it loaded open; the build then
renames the old one and puts the new one next to it.

`register.ps1` registers `bin\DexmenuShell.dll` for the current user (`-Remove` takes it away, `-Enable` switches it
on).

The version is `1.0.<commits>` (`git rev-list --count HEAD`, the `GitVersion` target in
`src\settings\Dexmenu.Settings.csproj`).

## Data folder

`%APPDATA%\Dexmenu`: the settings and the layouts. `%LOCALAPPDATA%\Dexmenu`: what Dexmenu keeps by itself (the
settings window's browser data, the right-clicks' timings for Diagnostics). `DEXMENU_DATA` points a test copy
elsewhere.

## Releasing

`release\notes-template.md` describes a release; `release\notes-<version>.md` are the notes of each one (tracked). The
zip and its SHA-256 go in `release\` too, but only to GitHub Releases, not into git.

## License and support

Copyright (c) 2026 Arco Witter. Released under the [MIT License](LICENSE).
Includes [DDetours](https://github.com/MahdiSafsafi/DDetours) by Mahdi Safsafi (MPL 2.0, unchanged, in
`src\vendor\DDetours` with its licence).
Like Dexmenu? [Support me on Ko-fi](https://ko-fi.com/arcowitter).
