<!--
Release notes template (as Foldex's). Copy to notes-<version>.md, fill in, paste into GitHub's
"Describe this release". Replace every {PLACEHOLDER}; drop sections that do not apply.
- {VERSION}  new version, for example 1.0.250 (1.0.<git commit count>, see GitVersion in src\settings\Dexmenu.Settings.csproj)
- {PREVIOUS} previous published version
- {SHA256}   from Dexmenu-{VERSION}-win-x64.zip.sha256
Build: build.cmd, then dotnet publish src\settings\Dexmenu.Settings.csproj -c Release -o release\bin; zip release\bin's
files into Dexmenu-{VERSION}-win-x64.zip.
Describe only what changed since {PREVIOUS}; the full overview stays in the first release.
Keep the fixed parts (install, unsigned note, verify, footer).
This comment is not shown by GitHub, but delete it anyway.
-->
{One-line summary, for example: Small update to {PREVIOUS}.}

For the full feature overview, see the [README](https://github.com/ArcoW2/dexmenu#readme).

## Changes

- {Change, user's point of view: what is new or fixed, where to find it.}

{Compatibility line, for example: No changes to settings; your layouts from {PREVIOUS} work as-is.}

## Install / update

Download `Dexmenu-{VERSION}-win-x64.zip`. Explorer keeps the DLL it loaded open, so: in `DexmenuSettings.exe` click **Unregister**, then **Restart Explorer**, close it, delete the old files in its folder (not `%APPDATA%\Dexmenu`: your settings and layouts stay there), and extract the zip into it. Run `DexmenuSettings.exe` again, click **Register**, then **Restart Explorer**.

Needs the [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0) (x64) and the Microsoft Edge WebView2 Runtime (included with Windows 11) for the settings window.

**Unsigned:** Windows SmartScreen may show "Windows protected your PC" on first start. Click *More info* > *Run anyway*, or tick *Unblock* in the zip's Properties before extracting.

## Verify the download

SHA-256 of `Dexmenu-{VERSION}-win-x64.zip`:

```
{SHA256}
```

PowerShell: `Get-FileHash .\Dexmenu-{VERSION}-win-x64.zip -Algorithm SHA256`

---

Includes [DDetours](https://github.com/MahdiSafsafi/DDetours) by Mahdi Safsafi (MPL 2.0, unchanged).

Copyright (c) 2026 Arco Witter. Released under the [MIT License](https://github.com/ArcoW2/dexmenu/blob/main/LICENSE).
Like Dexmenu? [Support me on Ko-fi](https://ko-fi.com/arcowitter).
