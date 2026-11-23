# Plan 10: Explorer's icons, found by probing Windows, and an icon picker for cards

Status: not started; see Status.

- 2026-11-23: draft.

Builds on plan 02 (`executed/02-PLAN-own-menu.md`): icons in the slot left of the text (3.8), the icons kept as PNG files in
the seen folder's `icons` by the item's key (3.8, 3.9), and the card's own `icon` (a glyph or `path,index`).

## 1. What this is about

In Explorer the menu shows almost no icons. Explorer draws every item of its full menu itself (plan 01 6.2), so there
is no bitmap to read. Asking Explorer to draw the items into Dexmenu's memory (plan 02's icon probe) does not work:
run in Explorer, its window measured nothing for nearly every item, and the few it drew (TortoiseGit, TortoiseSVN)
came out blank. Outside Explorer (Foldex, an Open dialog) and in the settings app's real menu of a folder, the same
items do carry their bitmaps.

Windows' own items (Cut, Copy, Delete, Properties) are no problem: a card gives them a glyph of its own, as Default
A does. What is missing are the extensions' icons (Edit in LexPen, Open with Code, 7-Zip, TortoiseGit), and a way for
a user to give a card an icon without knowing glyph code points.

## 2. The solution, in brief

The icons are found by probing Windows from the settings app, not by asking Explorer at a right-click: the settings
app asks Windows for the real menus of a set of right-clicks, as its preview already does, and keeps every item's
bitmap; items that still have none get the icon their registration names (a verb's `Icon` value, a packaged
extension's own icon). The DLL at a right-click uses an item's kept icon when the item has no bitmap of its own. The
editor gets an icon picker for a card: the icon themes' icons, the glyphs, the kept icons and an icon from a file.
Dexmenu ships a set of icons for Windows' own items and common tasks in several icon themes; a card names an icon,
and the icon theme in use draws it. The owner-draw probe in the DLL is removed.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Kept icons in the menu | at a right-click, an item without a bitmap drawn with the icon kept for its key | -- | 3.1 |
| Probing menus | the settings app asks Windows for the real menus of a set of right-clicks and keeps every bitmap | -- | 3.2 |
| Probing registrations | items still without an icon: the `Icon` of their verb's registration, a packaged extension's icon | Probing menus | 3.3 |
| Icon themes | shipped icons for Windows' own items and common tasks, by name, in several icon themes; the icon theme chosen per light and dark | -- | 3.6 |
| Icon from a file | in the card panel: "..." beside Icon, a file chosen (exe, dll, ico), its icons shown, one picked as `path,index` | -- | 3.4 |
| Icon picker | the picker's other tabs: an icon theme's icon, a glyph, a kept icon | Icon themes | 3.4 |
| Owner-draw probe removed | the DLL's opt-in probe (ProbeIcons) and its code taken out | -- | 3.5 |
| Tests | 3.7 | -- | 3.7 |

## 3. Details

### 3.1 Kept icons in the menu

- The order of plan 02 3.8 gets one step: the card's own icon; the item's own bitmap; the icon kept for the item's key;
  none.
- Read once per process and then from memory, as the preview's are (`KeptIconPixels`), so a right-click stays fast.
- An item whose text differs per right-click ("Compare to <file>") has a key that differs too; it gets an icon only
  through its card or a registration (3.3).

### 3.2 Probing menus

- The settings app builds the real menu for a set of right-clicks, as the preview does for a chosen folder (plan 02
  3.8): a file of each extension the seen items have right-clicked, a folder, a folder's empty part, a drive. Every
  submenu opened once; every bitmap kept by the item's key, as now.
- When: from a button in the main window ("Find icons"), and after the seen items show a new item without an icon.
- Where the files come from: a folder of the user's that has them, or empty files made in a temporary folder with
  the extensions (an extension's handler looks at the extension, rarely at the content): [not yet checked] which
  handlers need a real file.

### 3.3 Probing registrations

- For an item still without an icon: its verb's registration (`HKCR\<type>\shell\<verb>`, `*`, `Directory`,
  `Directory\Background`, `Drive`, `AllFilesystemObjects`) matched by its text (`MUIVerb` or the default value), and
  its `Icon` value read.
- A packaged extension (an `IExplorerCommand`: PowerRename, File Locksmith, Terminal): its `GetIcon`, or the package's
  logo.
- Matching by text is needed because Explorer's menu gives no verb per item: [not yet checked] how many items it
  leaves without a match.

### 3.4 Icon picker

- In the editor's card panel, beside the Icon field: "Select an icon...", and where a card shows no icon in the
  preview the same choice on the card. A dialog with four tabs: the icon themes' icons by name (3.6), the glyphs of Segoe Fluent Icons (searchable by
  name), the kept icons (by the items' names), and an icon in a file (`path,index`, the file's icons shown).
- The icon in a file comes first, on its own: "..." beside the Icon field opens Windows' file dialog (programs,
  libraries, icon files); the settings app reads the file's icons and shows them in a grid; the one clicked is
  written as `path,index`. The other tabs join it once the icon themes are there.
- A kept icon chosen is written as the card's `icon` by its file, so it stays when the item's own icon changes (where
  that file lives: Open question 2).

### 3.5 Owner-draw probe removed

- The DLL's probe (`ProbeOwnerDrawn`, `ProbingIcons`, HKCU Software Dexmenu ProbeIcons) gave nothing in Explorer; it is
  taken out with its log lines and the `probe` folder's use.

### 3.6 Icon themes

- A set of icons by name for Windows' own items and common tasks (`cut`, `copy`, `paste`, `rename`, `delete`,
  `properties`, `open`, `openWith`, `share`, `archive`, `versionControl`, `terminal`, `edit`, `search`, Dexmenu's own
  `editMenu` and `windowsMenu`, ...), shipped in several icon themes, each drawn in one style (for example outlined
  glyphs, filled glyphs, coloured): [not yet checked] which styles and how many icons each.
- An icon theme is a folder of its own: one image per name (SVG or PNG at a few sizes) and a small JSON with its name;
  shipped in the DLL's `icons` folder, the user's own in `%APPDATA%\Dexmenu\icons`, as the colour themes are (plan 03).
- A card names an icon (`"icon": "cut"`); the icon theme in use draws it. A name the theme lacks falls back to the
  default icon theme. Glyph code points and `path,index` keep working.
- Chosen in the main window beside the colour themes, per light and dark; a colour theme may name an icon theme to
  go with it.
- The shipped layouts use the names, so they follow the icon theme; plan 03's own cards' icons (Edit menu...,
  Windows' menu) become names in this set.

### 3.7 Tests

- Kept icons in the menu: an item without a bitmap and with a kept icon drawn with it; one with a bitmap keeps its
  own; a card's icon wins over both.
- Probing menus: the set of right-clicks built, icons kept, a second run writes nothing new.
- Probing registrations: a verb registered with an `Icon` found by its text.
- The icon picker in the editor's self-test: an icon theme's icon, a glyph, a kept icon and a file icon chosen and
  written.
- Icon themes: a card's named icon drawn from the theme in use, a name the theme lacks from the default, a user's
  icon theme read, the theme switched per light and dark.
- By hand in Explorer: a right-click after "Find icons" shows the extensions' icons.

## 4. Open questions

1. Should probing menus also run by itself when the settings app starts, or only on the button and on new items?
2. A kept icon chosen in the picker: copied into the layouts folder (a layout that travels with its icons), or
   referred to in the seen folder's `icons`?
