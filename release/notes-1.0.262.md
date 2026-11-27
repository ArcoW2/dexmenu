Themes per card, rules that order and exclude, dividers that stand upright, and three new medium themes: a feature update to 1.0.227.

For the full feature overview, see the [README](https://github.com/ArcoW2/dexmenu#readme).

## Changes

### Themes

- **A theme per card**: every card can set its own theme for when Windows is light and when it is dark; a card that sets none takes its parent's, up to the menu's own. A card's submenu is drawn in its theme, its window included.
- **The menu chooses its theme**: the menu card (the top of the cards view) has the theme fields that were in General.
- **Menustyle**: a card that opens a submenu shows a small dashed *Menustyle* item; its style (background, border, radius, shadow, see-through) and its own theme are those of the submenu it opens.
- **Three medium themes**: medium-sage, medium-sandstone and medium-lagoon, between the light and dark pairs, with text at 7:1 contrast. The theme lists are sorted by name.
- The colour pickers show the palette of the theme of the card being edited.

### Rules

- **Order**: per rule (as found, most recent, most used, name; descending) and per card over all its rules.
- **Exclude**: a rule that takes nothing itself; the card's rules after it do not take what it matches. Shown in red.
- **Latest**: of the items a rule finds, only the ones seen most recently (for items whose name changes each time, as "Compare to <file>").
- **any** as a name match (every name); the list match is now called *one of*.
- Rules that look inside a submenu now find the items of submenus filled only when opened (Open with); an item whose submenu ends up empty is not shown.
- Rename: `^` alone puts text before the item's name, `$` alone after it; cards shown inside a card use the card's rename when their template has none.

### Dividers and groups

- **Upright dividers** between cards side by side, with a min and max width and a thickness; a divider in a grid is drawn between its columns or rows. Drop a divider on a card's left or right edge in a row and it stands upright.
- **A group bordered by dividers**: a divider on top (with the group's title) and optionally at the bottom, no frame; doubled lines are left out.
- **A divider as a spacer**: room without a line.

### Editor and menu

- New cards, notes, groups and dividers are added after the selected card (inside its group), and the Group button can be dragged.
- A card's hover buttons act on a click held a moment or on a double-click.
- Copy and paste style works on the menu card.
- Selecting a group highlights the rules of every card inside it.
- Wrapped titles break long words instead of cutting them; cards without a mark no longer reserve room for one, so their text is not cut early.
- A click on a submenu card that hover just opened keeps it open.
- Fixed: a card showing items taken from a Windows submenu could show the wrong items after that submenu was opened.

**Themes move to your layouts:** the first start of the new `DexmenuSettings.exe` writes the theme chosen in General onto the menu card of each of your layouts that has none, and removes it from General. Your menus look as before. Replace `DexmenuShell.dll` together with the exe, as below: the old DLL no longer finds the theme in General.

## Install / update

Download `Dexmenu-1.0.262-win-x64.zip`. Explorer keeps the DLL it loaded open, so: in `DexmenuSettings.exe` click **Unregister**, then **Restart Explorer**, close it, delete the old files in its folder (not `%APPDATA%\Dexmenu`: your settings and layouts stay there), and extract the zip into it. Run `DexmenuSettings.exe` again, click **Register**, then **Restart Explorer**.

Needs the [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0) (x64) and the Microsoft Edge WebView2 Runtime (included with Windows 11) for the settings window.

**Unsigned:** Windows SmartScreen may show "Windows protected your PC" on first start. Click *More info* > *Run anyway*, or tick *Unblock* in the zip's Properties before extracting.

## Verify the download

SHA-256 of `Dexmenu-1.0.262-win-x64.zip`:

```
C183113911B4EEA17C18C015DBB0A579D989F17E3CB58AD33A2B59B5C32ABCD0
```

PowerShell: `Get-FileHash .\Dexmenu-1.0.262-win-x64.zip -Algorithm SHA256`

---

Includes [DDetours](https://github.com/MahdiSafsafi/DDetours) by Mahdi Safsafi (MPL 2.0, unchanged).

Copyright (c) 2026 Arco Witter. Released under the [MIT License](https://github.com/ArcoW2/dexmenu/blob/main/LICENSE).

Like Dexmenu? [Buy me a coffee or a chocolate](https://ko-fi.com/arcowitter).
