# Plan 11: Cards hold content: one item, a submenu, or cards arranged inside them; lines and groups become cards

Status: not started; see Status.

- 2026-11-23: draft.

Builds on plan 02 (`executed/02-PLAN-own-menu.md`): lines of cards, a card with a menu, a card placing what it
found (3.3), items as buttons in a card (3.3, 6.1), the editor's cards view (3.5); plan 03 (`03-PLAN-menu-look.md`):
a card's size on its line (3.5), its own look (3.6); plan 09 (`executed/09-PLAN-used-rules.md`): used rules, which
often find several items; plan 13 (`executed/13-PLAN-card-panel-tabs.md`): the card panel's panels. Takes in what was
plan 07 (groups: cards that belong together, shown or left out together).

## 1. What this is about

A layout is lines of cards, and a card is one of a few fixed kinds: one that finds items (several found each take a
line of their own), one with a menu (its cards in a submenu), one showing its items as buttons. So a user cannot:

- put found items side by side (the three most used next to each other), with a maximum per row and of rows;
- give the cards made for found items a look of their own (square, coloured);
- put cards inside a card without making it a menu;
- keep cards that belong together together: when none of them shows, the divider above them stays (what plan 07 was
  about);
- arrange cards in aligned columns: a line shares its width among its own cards only, so lines make a mosaic.

## 2. The solution, in brief

Every card holds content and says how it shows it. Its content is what its rules find, or the cards placed in it
(cards with rules, notes, dividers, cards holding cards): found items show at the place of the card that found them,
in the order its rules found them. It shows its content as its own item (one found), in a submenu, or arranged
inside it: side by side (a set number per row,
rows up to a maximum, the rest in a "More" submenu or left out), or under each other (a set number per column, then
the next column, the columns sharing the width). A card that only arranges others and has no style of its own draws
nothing itself: that is what a line was, and what a group was, also in being left out when nothing in it shows. The
menu is then one tree of cards, so rows of cards (a mosaic) and aligned columns are both a matter of what holds what.
A card holding cards can have every style a card has (background, border, a title, which may look like a divider),
and its hover style lights it up while the mouse is over anything inside it. The cards made for found items take a
style the holder gives them. It is built in two steps: the DLL and the layout
format first, then the editor. The user's layouts (their "First" among them) are converted once to the new form; the
shipped layouts are written in it.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Format | format 2: the menu a card; a card's rules or its `content` (cards, dividers, notes, the search box), and `show` (`item`, `submenu`, `row`, `column`) with `perRow`, `rows`, `perColumn`, `columns`, `rest`, `shownWhen`, `titleAs`, `items` | -- | 3.1 |
| Placement | the tree placed: found items and placed cards in a card's content, shown as it says; a holder left out by `shownWhen` | Format | 3.2; 3.3 |
| Measure and draw | a card's content measured and drawn inside it as its `show` says, recursively; a holder's style, title (or title as a divider) and hover while the mouse is inside it; found items in the `items` style; square cards | Placement | 3.4 |
| Keys and hit tests | the arrows, a click and the hover through the tree of cards | Measure and draw | 3.4 |
| Shipped layouts | Default A - D in format 2 | Format | 3.6 |
| Conversion once | the user's layouts converted once to format 2 (a backup kept); nothing reads format 1 afterwards | Format | 3.7 |
| Editor: tree | the cards view shows the tree: a card's content inside it; dragging into a card, beside a card, above or below it | Format | 3.5 |
| Editor: panel | the card panel's Inside: Shows, per row, rows, per column, columns, the rest, shown when; Names: Title shown as; the found items' style | Editor: tree | 3.5 |
| Tests | 3.8 | -- | 3.8 |

Moved in: all of plan 07 (groups), as holders without a style and their `shownWhen`.

## 3. Details

### 3.1 The format

- `"format": 2`. The layout is one card, the menu: `{ "format": 2, "menu": { "show": "column", "content": [ ... ] } }`.
- A card: its name, title, texts, icon, hint and style as now, and either its rules (it finds items) or its
  `content` (it holds cards), not both:
  - `content`: what is placed in it, in order: cards (with rules, with content), dividers (`{ "divider": ... }`),
    notes, the search box (`{ "search": true }`). A card with rules among them shows what it found at its own place,
    in the order its rules found it.
  - `show`: how it shows its found items or its content:
    - `item` (the default for a card with rules): the card multiplied: one found item is the card itself; several
      found, the card once for each, under each other at the card's place, each in the card's own layout and style
      (as now);
    - `submenu`: the card is one item with its title; its found items or its content are its submenu (a card with a
      menu as now);
    - `row`: side by side inside it; `perRow` the most per row (not set: as many as fit; too many for the width wrap,
      as a line's cards do now); `rows` the most rows;
    - `column`: under each other inside it; `perColumn` the most per column, then the next column, the columns sharing
      the width; `columns` the most columns.
  - `rest`, with `rows` or `columns` set: what does not fit, `"menu"` (the default: a last card "More" with them as
    its submenu) or `"none"` (left out; still taken, so shown nowhere else).
  - `shownWhen` (from plan 07): `"always"`, `"anyItem"` (anything in it shows: an item, a card that shows, a note) or
    `"actionItem"` (something in it does something when chosen: an item, a card with a submenu holding one; not a
    note). Dividers never count. Not shown, the card and all it holds are left out. A card with rules that finds
    nothing and holds nothing is not shown, as now, whatever this says.
  - A card holding cards (`row`, `column`) has every style a card has: background (a colour, a gradient), text
    colour, border, radius, and its `hover` and `pressed` looks; its `hover` look shows while the mouse is over
    anything inside it. Its title, when it has one (`title`), stands above its content: as a card's title, or with
    `"titleAs": "divider"` drawn as a divider with that text (its line and text in the dividers' look). With no style
    and no title it draws nothing itself (what a line or a group was).
  - `items`: the layout and style of the inner cards made for its found items when it shows them in a `row` or
    `column`, their own and apart from the card's (the card's own layout and style are its box around them): the
    layout fields (`height`, `square`, `minWidth`, `wrap`, `cardFit`, `extraAt`) and the style fields (`background`,
    `foreground`, `border`, `borderWidth`, `radius`, `hover`, `pressed`). Not set: the theme's card look, each as high
    as its content (as buttons are now).
  - `square`: a card as high as it is wide.
  - `cardFit` (on a holder: how its cards fit a taller row, as a line's now) and `weight`, `minWidth`, `height`,
    `wrap`, `cardFit` on a card as now, within its holder.
- Gone: `lines`, `line`, the line's `cardFit` (now the holder's), `menu` (now `content` with `show: "submenu"`),
  `buttons` (now a card with rules and `show: "row"`, its found items inside it, with the theme's card border).
- A card alone in a `column` holder is drawn as the theme's `item` (as a card alone on its line now); in a `row`, as
  its `card`.

### 3.2 Where found items go

- At the place of the card that found them, in the order its rules found them; inside the card when it shows them
  in a `row` or `column`. They are taken by the rules as now (the priority list, `also`, `consume`, ...): how they
  show is the only change.
- Used rules (plan 09) and own rules (plan 12) find items as any rule; ranks are as before.
- The remaining card: its items in its own way as now (`item`: each a card of its own under each other).
- An item found with a submenu of its own keeps it, in any `show`.

### 3.3 Holders and being shown

- A card holding cards (its `content`) with no style and no title is what a line was (`row`) or a group was
  (`column` with `shownWhen`). Its `shownWhen` decides first for nested holders; the holder around it counts
  what it shows.
- Dividers inside a holder go with it; the divider rules of plan 02 3.5 apply to what remains, in each holder.

### 3.4 Measure and draw

- Measured from the inside out: a card's content measured at the width its holder gives it; a `row` shares its
  width by `weight` and `minWidth` as a line does now, `perRow` cards to a row; a `column` stacks, `perColumn` per
  column, the columns sharing the width equally.
- A holder with a style or a title: its box (background, border, radius), its title on top (as a title, or as a
  divider), its content inside with a padding (as a card with buttons now). The mouse anywhere inside it: its `hover`
  look on its box, besides the hover of the card under the mouse.
- Keys: the arrows move by position through what shows, at any depth (left and right within a row, up and down
  between rows and columns); a holder is no stop of its own. The hover and a click hit the innermost
  card.
- The preview draws the same; a holder left out by `shownWhen` shows striped there (as plan 02 3.8 does for cards
  that show nothing at a right-click).

### 3.5 The editor

- The cards view shows the tree: a card's content inside it, drawn as now for a card with a menu; a holder without a
  style or title as a light outline (as a line now). Its `show` named on it ("row", "column 3 per column", "submenu").
- Dragging: onto a card's top or bottom edge, a card above or below it in the same holder; onto its left or right
  edge, beside it (into a row holder made there when the holder is a column); onto its middle, into it (its content
  at the end). The gutter's line selection becomes a holder's selection: a click beside a holder selects it.
- "+ Card" in a card's actions adds one to its content; "+ Group" adds a holder without a style.
- The card panel's Inside panel: Shows (item, submenu, row, column), Per row and Rows (row), Per column and Columns
  (column), The rest (in a More submenu, left out), Shown when; the Names panel: Title shown as (a title, a divider).
- Two more panels for a card with rules shown in a `row` or `column`: Item layout and Item style, the layout and
  style fields of `items` (the inner cards'), beside the card's own Layout and Style; arranged as any panel (plan 13).
- No conversion in the editor: it reads and writes format 2 only.

### 3.6 Shipped layouts

- Default A - D in format 2: their lines as holders (`row` without a style, a line of one card the card itself),
  Default B's cards with buttons as cards with rules showing them in a `row`, Default D's three used cards as a `row`.

### 3.7 The conversion, once

- A script run once (not part of the settings app or the DLL) converts every layout in the user's layouts folder to
  format 2 and keeps the old files in a backup folder beside it. How: the lines as the menu's `column`; a line of one
  card: that card; of more: a `row` holder without a style holding them, the line's `cardFit` on it; a card with a
  menu: `show: "submenu"` with its menu as `content`; a card with buttons: `show: "row"` with the theme's card
  border; everything else as it is.
- Run when step 1 (the DLL and the format) is published, so the menu reads the converted layouts at once; the user's
  "First" checked by hand after it. The settings' `shipped` list is left as it is (the shipped layouts already
  written are converted with the others).

### 3.8 Tests

- Unit tests: the format read (every `show`, the limits, `rest`, `shownWhen`, `titleAs`, `items`, rules and
  content together refused); placement: found
  items and placed cards in each `show`, `perRow` and `rows` with the rest in "More" and left out, `perColumn` and
  `columns`; `shownWhen` for each value with nested holders and dividers; measure: rows sharing the width, columns
  sharing it, a holder's padding and title (as a title and as a divider), its hover while the mouse is inside it,
  square; keys and hit tests through nested holders.
- The conversion: a format 1 layout with every kind of card and line converted and its menu compared, item for item,
  with what format 1 gave.
- The editor's self-test: the tree dragged (above, below, beside, into), a holder added, the Inside fields written.
- By hand: the user's "First" after the conversion, at a right-click and in the editor.

## 4. Open questions

None.
