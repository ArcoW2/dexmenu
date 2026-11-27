# Plan 08: A theme editor, for whole themes and for card styles

Status: not started; see Status.

- 2026-11-22: draft.

Builds on plan 03 (`03-PLAN-menu-look.md`: themes, the palette, elements and states), plan 15
(`executed/15-PLAN-card-themes.md` once closed; `15-PLAN-card-themes.md` until then: a theme per card) and the layout
editor (plan 02 3.5; `executed/05-PLAN-settings-windows.md` 3.6).

## 1. What this is about

A theme (plan 03) is a JSON file with a palette and, per element and state, its properties. Writing one by hand is
slow and gives no picture of the result. A user also often wants one card to look different from the theme's other
cards (a red Delete, a highlighted favourite) without making a whole theme.

## 2. The solution, in brief

A Themes tab in the main window: a theme is selected and changed there (its palette, every element and state, and
its card styles), with a preview of a sample layout holding every kind of card. Card styles are named looks for a
card, kept inside a theme; one can be copied from another theme. In the layout editor a card takes a card style by
copying it into its own style: the styles of every theme are shown, each drawn in its own theme, and the user chooses
whether the style's theme is copied onto the card too (not when the card's parent is already in that theme).

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Themes tab | a tab in the main window: a theme selected and changed (palette, elements, states), with the sample layout's preview | plan 03 Theme files | 3.1 |
| Sample layout | a layout holding every kind of card, for the preview | -- | 3.2 |
| Card styles | named card looks inside a theme, in its file; edited in the Themes tab; copied from another theme | Themes tab | 3.3 |
| In the layout editor | a card takes a card style: the styles of every theme shown in their themes, copied into the card, its theme too when chosen | Card styles; plan 15 | 3.4 |
| Tests | 3.5 | -- | 3.5 |

## 3. Details

### 3.1 The Themes tab

- A tab of the main window, beside the layouts: the themes there are (the built-in ones, the user's and the shipped
  ones), one selected and changed in the tab: its palette (its base colour and named colours), then per element and
  state its properties (plan 03 3.2), each colour as a palette colour with its intensity and opacity.
- A theme is made from another (its `base`) and keeps only what differs, as plan 03 says. A built-in or shipped theme
  is not changed in place: changing it makes the user's own copy under a new name.
- A preview drawn by the DLL with the theme as it is being edited (3.2).

### 3.2 The sample layout

- A layout made for the preview, holding every kind of card: an item, a card with a submenu, a card holding cards (a
  group, a row, a framed one, one with dividers as its border), found items inside a card, a note, a divider with and
  without a title, an upright divider, a disabled item, a card with an extra text; with fixed made-up items, so it
  looks the same on every machine.
- Its cards show the theme's states where a state can be shown still (disabled, the selected card's hover).

### 3.3 Card styles

- A card style: a name and a card's properties per state (plan 03 3.6, 3.7), kept in the theme, so it uses that
  theme's palette. There are no card styles outside a theme.
- Edited in the Themes tab with the theme: listed, each shown as a card in the theme, opened into the same fields as
  a card's style in the layout editor.
- A card style is copied from another theme into the selected one; its colours that name the other theme's palette
  keep their names where the selected theme has them, else take the colour they had there.

### 3.4 In the layout editor

- A card's right-click menu gets "Card style...": a view of the card styles of every theme, each drawn as a card in
  its own theme (as a template card is), the user sees the style exactly as it was made.
- Choosing one copies it into the card's own style (as Paste style does: what the style does not set, the theme's
  again). The card keeps no link to the card style: changing the style later does not change the card.
- With it a checkbox "also its theme": the style's theme is then set on the card (its `themeLight` or `themeDark`,
  whichever half the style's theme is for, plan 15), so it looks as shown. Not offered, and not set, when the card's
  parent already draws in that theme.

### 3.5 Tests

- To be set with the details: the Themes tab's changes written to the theme's file (a copy for a built-in or shipped
  one); the sample layout drawn in each shipped theme without problems; a card style copied between themes; a card
  style taken into a card, with and without its theme, and the theme left out when the parent has it.

## 4. Open questions

1. Which half a theme is for: a theme does not say whether it is a light or a dark one. Should a theme file say so
   (`"mode": "light"` or `"dark"`), or does the user pick the half when copying a style's theme onto a card?
