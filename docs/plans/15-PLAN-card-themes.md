# Plan 15: A theme per card

Status: partly executed; see Status.

- 2026-11-24: draft.
- 2026-11-27: partly executed: everything but the check by hand.

Builds on plan 03 (`03-PLAN-menu-look.md` 3.2, 3.3: themes, the light and dark pair) and the card panel of the
layout editor (`executed/13-PLAN-card-panel-tabs.md`).

## 1. What this is about

The theme is a setting in General of the main window: one theme when Windows is light, one when it is dark, for
every layout and every card. A layout cannot bring its own theme, and one part of a menu (a submenu, a row of
cards) cannot look different from the rest other than by giving each card its own colours.

## 2. The solution, in brief

A card carries the theme pair (when Windows is light, when dark), starting at the main card. A card that sets a
theme, or one half of the pair, draws itself and all its inner cards in it; a card that sets none takes its
parent's, and a main card without one the built-in light and dark. A submenu opened from a themed card is drawn
wholly in that theme, its window included. Templates carry no theme: they follow the card they sit on. The two
fields leave General; a choice made there is copied once onto the main card of the user's layouts.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Layout | `themeLight`, `themeDark` on a card; read, kept, the inherited pair resolved per card | 3.1; 6 |
| Themes loaded | any number of themes in memory, by name, each read again when its files change | 3.2; 6 |
| Drawing | every card, holder, note and divider drawn in its own card's theme; a level in its opener's | 3.3; 6 |
| Editor | a Theme field (light, dark) on the card panel; the colour pickers with the focused card's palette | 3.4; 6 |
| General | the two theme fields gone; the old choice copied onto the main cards once | 3.5; 6 |
| Tests | 3.6 | 3.6; 6 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| By hand | the user's layouts after the move from General, a card in a theme of its own at a right-click | the user | 3.6 |

## 3. Details

### 3.1 The layout

- A card (not a template, not a note, not a divider) may have `"themeLight"` and `"themeDark"`, each a theme's
  name. Either may be left out: that half comes from the parent card.
- The resolved pair per card: its own value, else its parent's resolved one; for the main card its own, else
  `light` and `dark`. Windows' mode then picks one half.
- A note or a divider has no theme of its own; it is drawn in the theme of the card it sits in.
- Found items: the cards made from a card's templates are inner cards of that card, so they take its theme; the
  template itself sets none.
- A theme name that cannot be read (a file gone, a bad file) falls back to the built-in light or dark for that card,
  logged once, as a bad General theme does now.

### 3.2 Themes loaded

`CurrentTheme(Dark)` holds one theme per mode, named by the global settings. It becomes a lookup by name: themes
kept in memory by name, each with its files' stamp, read again when a file changes, the same way as today. The
built-in ones stay in the DLL. A menu with a few themes reads each once.

### 3.3 Drawing

- Placing (Dexmenu.Place) gives every view card the theme it draws in, resolved by 3.1. A level (the main menu, or a
  submenu) gets the theme of the card it shows: its background, border, radius, shadow window and see-through test
  come from that theme.
- Render takes its card colours, numbers, borders, shadows and image fills from the card's theme instead of the one
  theme it uses now. The brushes it makes once per render from the theme (text, dim, extra, hover, divider line,
  focus, unavailable stripes) are made per theme in use, not per card, so a level with a single theme costs what it
  costs now.
- The gaps between cards and lines (`card.gap`, `line.gap`) come from the level's theme.
- The preview's outline colour (`card.marked.border`) comes from the marked card's theme.
- The preview's light/dark switch (DexmenuSetTheme) keeps picking the half of each pair.

### 3.4 The editor

- The card panel gets a Theme field with two dropdowns, "when Windows is light" and "when dark", listing the theme
  names (as General does now) plus "(the parent's)"; on the main card "(built-in)" instead. Shown as a tree under
  Theme, as the other sub-options are.
- A template, a note and a divider have no Theme field.
- The colour pickers' palette (DexmenuThemePalette) is that of the focused card's resolved theme, for the mode the
  preview shows; it changes when the focus moves to a card in another theme, or the card's theme changes.
- Copy style and paste style include the theme pair: it is part of a card's look.

### 3.5 General

- The fields "Theme when Windows is light" and "when dark" go from the main window.
- Once, when the app starts and settings.json still has `themeLight` or `themeDark` with a value other than the
  built-in `light` / `dark`: that value is written onto the main card of every layout in the user's layouts folder
  whose main card sets no theme of its own, and the keys are removed from settings.json. The menu looks as before.
- The DLL no longer reads `themeLight` / `themeDark` from settings.json.

### 3.6 Tests

- Unit (DLL): the pair resolved through parents, one half inherited, the main card's default, a template's found
  cards in their card's theme, an unknown name to the built-in one.
- Unit (DLL), pixels: a dark-themed card in a light menu drawn with the dark theme's card background; its submenu
  level drawn with the dark theme's menu background.
- Unit (DLL): two themes loaded at once, one changed on disk and read again, the other kept.
- Self-test (editor): the Theme field writes and removes `themeLight` / `themeDark`; "(the parent's)" leaves the key
  out; copy and paste style carry the pair.
- Settings app: the migration on a data folder with a non-default General theme and layouts with and without a
  main-card theme; run once, settings.json without the keys after it.

## 4. Open questions

None.

## 6. As built

- Dexmenu.Layout: `TCard.ThemeLight`, `ThemeDark` on every card (and the main card); `MenuSettings` no longer reads
  the theme from settings.json (its fields keep the built-in names).
- Dexmenu.Theme: themes kept by name and mode (`ThemeByName`), each read again when its file's time changes; the
  built-in one for a name that cannot be read, logged. `SetLayoutThemes` holds the main card's pair (set by the menu
  and the preview from their layout); `CurrentTheme` is the main card's theme, `CardTheme` walks a card's parents to
  the top (a top card's parent being the main card). `ThemePaletteOf` and the export `DexmenuThemePaletteOf` give a
  pair's palette for the mode the preview draws in.
- Dexmenu.Place and Dexmenu.Draw: `TViewLevel.ThemeCard` (a card's submenu: that card; a Windows submenu: its
  opener's card, else the level it opens from, set by Dexmenu.Menu and Dexmenu.Preview); the level's theme draws its
  window, background, border, radius, see-through test and shadow, and gives the gaps (Measure holds it for Gaps).
  Each box is drawn in its layout card's theme, a box without one (a divider, Windows' items) in that of the card
  holding cards around it, else the level's; the brushes are made again only when the theme changes from one box to
  the next. The preview's outline is in the marked card's theme.
- Editor: a Theme field (when Windows is light, when dark; "(the parent's)", on the main card "(built-in)") in a card's
  Style and the menu's; the page works out the edited card's pair (its own, its parents', the main card's) and asks
  the app for that palette ("paletteFor") whenever the pair changes, also after a reload and a light/dark switch; the
  pair is part of a card's style (copy and paste style).
- A card's Menustyle (its submenu's style) has a theme pair of its own: the submenu, its window and what is in it
  (the cards it holds, the items found into it) are drawn in it; the card opening it keeps its own. A card in a
  submenu takes the Menustyle's theme before its card's; a Menustyle setting none is its card's. Editor: a Theme
  field in the Menustyle's panel; the palette lookup follows the same order. Tested: unit test (the card in its own
  theme, the submenu and a card in it in the Menustyle's).
- General: the two fields gone from the main window and the app; `DataFolder.MoveThemesToLayouts` runs at the app's
  start: a non-built-in General theme written onto each layout's main card that sets none (the rest of the file as it
  was, its text kept unescaped), the keys removed from settings.json.
- Tested: unit tests (TestCardThemes: the pair through the parents, one half inherited, the main card's, the built-in
  one for a half set nowhere and for a name that cannot be read, a template's found cards in their card's theme; two
  themes kept, one changed on disk read again, the other kept; drawn: a card in its own theme in a menu of another,
  the menu in the main card's, a themed card's submenu window in its theme), the theme tests now naming the theme on
  the main card; the files self-test (the move from General, a main card's own theme kept, settings.json without the
  keys, a second start changing nothing); the editor's self-test (copy and paste style carry the pair).
