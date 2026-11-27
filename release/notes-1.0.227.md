First public release of **Dexmenu**: your own right-click menu for Windows 10/11 (x64). Instead of Windows' long list, Explorer shows a menu you build yourself from layouts: cards, submenus, notes and your own themes, with the items of Windows and other programs placed where you want them.

For the full feature overview, see the [README](https://github.com/ArcoW2/dexmenu#readme).

## Highlights

- **Your own layouts**: cards and submenus you arrange by dragging, rules that collect Windows' and other programs' items into them, notes, dividers, icons and images; a layout per kind of right-click (a file, a folder, a folder's empty part, a drive, ...).
- **Your own look**: a theme for when Windows is light and one for when it is dark; text size (also Ctrl+scroll in the open menu), menu widths, marks on submenus and items.
- **Submenus your way**: next to their card, under it, or in place of the menu (<< back); on hover or only on a click.
- **Windows' menu still there**: hold Shift while right-clicking for Windows' own menu (in Explorer its extended menu).
- **Diagnostics**: which programs make your right-click slow, measured per program, each with a switch to turn its menu extension off.

## Install

1. Download `Dexmenu-1.0.227-win-x64.zip` and extract it to a folder that stays (for example `C:\Apps\Dexmenu`): Explorer loads `DexmenuShell.dll` from there.
2. Run `DexmenuSettings.exe`, click **Register** (General), then **Restart Explorer**.

Registration is for your user only; no administrator rights needed. Settings and layouts are kept in `%APPDATA%\Dexmenu`, not next to the exe.

To remove: **Unregister**, **Restart Explorer**, then delete the folder.

Needs the [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0) (x64) and the Microsoft Edge WebView2 Runtime (included with Windows 11) for the settings window; the menu in Explorer needs neither. No installer.

**Unsigned:** Windows SmartScreen may show "Windows protected your PC" on first start. Click *More info* > *Run anyway*, or tick *Unblock* in the zip's Properties before extracting.

## Verify the download

SHA-256 of `Dexmenu-1.0.227-win-x64.zip`:

```
08F52CCE4DD371003EA63D4141A29A793852071A1AA3FC311802238B1B1A7CA5
```

PowerShell: `Get-FileHash .\Dexmenu-1.0.227-win-x64.zip -Algorithm SHA256`

---

Includes [DDetours](https://github.com/MahdiSafsafi/DDetours) by Mahdi Safsafi (MPL 2.0, unchanged).

Copyright (c) 2026 Arco Witter. Released under the [MIT License](https://github.com/ArcoW2/dexmenu/blob/main/LICENSE).

Like Dexmenu? [Buy me a coffee or a chocolate](https://ko-fi.com/arcowitter).
