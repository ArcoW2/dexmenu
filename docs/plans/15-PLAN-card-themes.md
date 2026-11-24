# Plan 15: A theme per card

Status: not started; see Status.

- 2026-11-24: draft.

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

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Layout | `themeLight`, `themeDark` on a card; read, kept, the inherited pair resolved per card | -- | 3.1 |
| Themes loaded | any number of themes in memory, by name, each read again when its files change | -- | 3.2 |
| Drawing | every card, holder, note and divider drawn in its own card's theme; a level in its opener's | Layout; Themes loaded | 3.3 |
| Editor | a Theme field (light, dark) on the card panel; the colour pickers with the focused card's palette | Layout | 3.4 |
| General | the two theme fields gone; the old choice copied onto the main cards once | Layout | 3.5 |
| Tests | 3.6 | -- | 3.6 |

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
