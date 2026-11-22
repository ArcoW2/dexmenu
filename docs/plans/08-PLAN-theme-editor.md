# Plan 08: A theme editor, for whole themes and for card styles

Status: not started; see Status.

- 2026-11-22: draft.

Builds on plan 03 (`03-PLAN-menu-look.md`: themes, the palette, elements and states) and the layout editor (plan 02
3.5; `executed/05-PLAN-settings-windows.md` 3.6). The details are to be worked out; this draft holds the idea and
the questions.

## 1. What this is about

A theme (plan 03) is a JSON file with a palette and, per element and state, its properties. Writing one by hand is
slow and gives no picture of the result. A user also often wants one card to look different from the theme's other
cards (a red Delete, a highlighted favourite) without making a whole theme.

## 2. The solution, in brief

A theme editor in the settings app that makes a whole theme (the palette, every element and state, with a preview
of the menu), or only card styles: named looks for a card, kept inside a theme. In the layout editor a card can take
such a card style, which overrules the theme's look for cards on that card only. A right-click on a card in the
layout editor opens the card style editor for it.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Theme editor | a window for a whole theme: palette, elements, states, with the menu's preview | plan 03 Theme files; Open questions 1, 2 | 3.1 |
| Card styles | named card looks inside a theme, in its file | plan 03 Theme files; Open question 3 | 3.2 |
| Card style editor | the theme editor for one card style | Theme editor; Card styles | 3.2 |
| In the layout editor | a card takes a card style; a right-click on a card opens the card style editor | Card styles | 3.3 |
| Tests | 3.4 | -- | 3.4 |

## 3. Details

### 3.1 The theme editor

- A window of the settings app, as the layout editor is: the theme's palette (its base colour and named colours),
  then per element and state its properties (plan 03 3.2), each colour as a palette colour with its intensity and
  opacity; a preview of the menu drawn by the DLL with the theme as it is being edited.
- A theme is made from another (its `base`), and keeps only what differs, as plan 03 says.

### 3.2 Card styles

- A card style: a name and the card's properties per state (plan 03 3.6, 3.7), kept in the theme, so it follows the
  theme's palette.
- The card style editor: the theme editor narrowed to one card style.

### 3.3 In the layout editor

- A card's panel: which card style it takes (none: the theme's own look for cards).
- A right-click on a card in the cards view: a menu with "Edit card style..." that opens the card style editor on
  that card's style (or a new one for it).

### 3.4 Tests

- To be set with the details.

## 4. Open questions

1. The theme editor: a window of its own, or a tab in the main window?
2. Its preview: the layout in use, a sample layout showing every element and state, or the user's choice?
3. A card style in a theme the user is not using: does a card taking it fall back to the theme's own look, or is a
   card style kept outside the themes, so every theme has it?
4. Light and dark: does a card style have a light and a dark side, as the themes come in pairs (plan 03 3.3)?
