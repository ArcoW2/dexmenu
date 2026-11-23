# Plan 11: Cards hold content: one item, a submenu, or cards arranged inside them; lines and groups become cards

Status: partly executed; see Status.

- 2026-11-23: draft.
- 2026-11-23: partly executed: step 1, the DLL and format 2; the conversion script.
- 2026-11-23: partly executed: step 2, the editor; the shipped layouts; the user's layouts converted.

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
The menu itself is the base card of that tree, fixed: every layout has it, and it holds how the menu's cards show
(under each other, side by side, in columns), the layout's submenus default and the menu's own style.
A card holding cards can have every style a card has (background, border, a title, which may look like a divider),
and its hover style lights it up while the mouse is over anything inside it. The cards made for found items follow templates the
card holds: cards of their own, edited as any card, each with its states' looks; with several, the card says how
its inner cards pick one, by their place (cycling) or by the rule that found them; how they are aligned stays the
holding card's. It is built in two steps: the DLL and the layout
format first, then the editor. The user's layouts (their "First" among them) are converted once to the new form; the
shipped layouts are written in it.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Format | format 2 read by the DLL (format 1 too, onto the same cards) | 3.1; 6.1 |
| Placement | holders, found items inside a card or in a submenu, limits, "More", rest, shownWhen, templates by place or rule | 3.2; 3.3; 6.1 |
| Measure and draw | measuring recursive through holders; holders' frames, titles (also as a divider), hover inside; square | 3.4; 6.1 |
| Keys and hit tests | through the boxes in their order at any depth; a holder no stop | 3.4; 6.1 |
| Conversion | written, checked and run on the user's layouts (a backup kept; the same menus, box for box) | 3.7; 6.1; 6.2 |
| Shipped layouts | Default A - D and the base layout in format 2 | 3.6; 6.2 |
| Editor: tree | format 2 only; the cards view draws holders and rows; drops above, below, beside (a plain row made) and into a card; a click in the gutter selects a row; "+ Group" | 3.5; 6.2 |
| Editor: panel | Shows, per row, rows, per column, columns, the rest, shown when, templates picked, title shown as, square; templates as dashed cards edited as cards; a rule's template | 3.5; 6.2 |
| Tests | unit tests, the editor's self-test, the compare on the user's layouts | 3.8; 6.1; 6.2 |
| The menu card | the menu the base card of every layout (id `menu`): its Shows, columns, submenus default and style read by the DLL and set in the editor; drawn as the fixed outer card; every layout given it (the user's, the shipped, the base layout, the conversion) | 3.9; 6.4 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| By hand | the user's "First" at a right-click and in the editor; dragging holders and rows; templates edited | -- | 3.8 |

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
  - A card showing its found items or the cards it holds inside it (`row`, `column`) has a title above them only
    when it has one (`title`); its name is never shown in its place. In the editor the title starts as its name when
    the card is set to show them inside it, and follows the name while the two are the same; an empty title shows
    none.
  - A card holding cards (`row`, `column`) has every style a card has: background (a colour, a gradient), text
    colour, border, radius, and its `hover` and `pressed` looks; its `hover` look shows while the mouse is over
    anything inside it. Its title, when it has one (`title`), stands above its content: as a card's title, or with
    `"titleAs": "divider"` drawn as a divider with that text (its line and text in the dividers' look). With no style
    and no title it draws nothing itself (what a line or a group was).
  - `templates`: the cards the inner cards made for its found items follow when it shows them in a `row`, a `column`
    or a `submenu`: their own and apart from the card's (the card's own layout and style are its box around them). A
    template is a card without rules or content: its texts that apply to every item (`rename`, `extra`, `extraAt`,
    `icon`, `hint`), its layout (`height`, `square`, `minWidth`, `wrap`, `cardFit`) and its style (`background`,
    `foreground`, `border`, `borderWidth`, `radius`, and its states' looks `hover`, `pressed`, `disabled`). Each inner
    card's title is its item's text (with its template's rename). How the inner cards are aligned (`perRow`, `rows`,
    `perColumn`, `columns`, the holder's `cardFit`) stays the holding card's. No template: the theme's card look,
    each as high as its content (as buttons are now).
  - `templatesBy`, with more than one template: `"position"` (the default: the inner cards take them in turn, the
    first card the first template, the second the second, and round again: two templates, every other card) or
    `"rule"` (each inner card the template its rule names, `"template": 2` on the rule; a rule naming none the
    first).
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
- An item found with a submenu of its own keeps it as its submenu, except inside a card showing it in a `row` or
  `column`: there it is unfolded, its submenu's items the inner cards (as buttons did, so a program's card shows that
  program's items).

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
- Keys: up and down move through the cards in their order, at any depth, as through the cards of lines now; a holder
  is no stop of its own. The hover and a click hit the innermost card.
- A row of held cards shares its width as a line's cards do (wrapping where their minimum widths do not fit); a row
  of found items without `perRow` flows, each as wide as its content, wrapping where they do not fit (as buttons).
- A holder with nothing in it but dividers (its cards found nothing) is left out, also in the preview.
- The preview draws the same; a holder left out by `shownWhen` shows striped there (as plan 02 3.8 does for cards
  that show nothing at a right-click).

### 3.5 The editor

- The cards view shows the tree: a card's content inside it, drawn as now for a card with a menu; a holder without a
  style or title as a light outline (as a line now). Its `show` named on it ("row", "column 3 per column", "submenu").
- With more than one template: "Templates picked by" (place, rule) in the card's Inside panel, disabled with one or
  none; by rule, each rule's panel names its template.
- Dragging: onto a card's top or bottom edge, a card above or below it in the same holder; onto its left or right
  edge, beside it (into a row holder made there when the holder is a column); onto its middle, into it (its content
  at the end). The gutter's line selection becomes a holder's selection: a click beside a holder selects it.
- "+ Card" in a card's actions adds one to its content; "+ Group" adds a holder without a style.
- The card panel's Inside panel: Shows (item, submenu, row, column), Per row and Rows (row), Per column and Columns
  (column), The rest (in a More submenu, left out), Shown when; the Names panel: Title shown as (a title, a divider).
- A card with rules shown in a `row`, a `column` or a `submenu` shows its template in the cards view as a card of its
  own inside it, marked as the template (dashed, "Template"), first in it; "+ Template" adds one, "x" removes it.
  Selected, it is edited in the card panel as any card: its Names (rename, extra text, icon, hint), Layout and Style
  panels; no Rules or Inside. Its style is copied and pasted as any card's.
- No conversion in the editor: it reads and writes format 2 only. (The DLL still reads format 1 as well: its unit
  tests are written in it, and it is read onto the same cards.)

### 3.6 Shipped layouts

- Default A - D in format 2: their lines as holders (`row` without a style, a line of one card the card itself),
  Default B's cards with buttons as cards with rules showing them in a `row`, Default D's three used cards as a `row`.

### 3.7 The conversion, once

- A script run once (not part of the settings app or the DLL) converts every layout in the user's layouts folder to
  format 2 and keeps the old files in a backup folder beside it. How: the lines as the menu's `column`; a line of one
  card: that card; of more: a `row` holder without a style holding them, shown whenever anything in it shows
  (`"shownWhen": "always"`, as a line), the line's `cardFit` on it; a card with a menu: `show: "submenu"` with its
  menu as `content`; a card with buttons: `show: "row"`; Dexmenu's own card a card with an own rule; everything else
  as it is. `tools/convert-layouts-to-format-2.py`; `--to <folder>` writes the converted files elsewhere to look first.
- Checked before it runs: `DexmenuUnitTests --compare <old> <new> <kinds>` places each kind's seen menu with the old
  and the converted layout, in the preview and at a right-click, and compares every box (kind, title, place, size).
- Run when both steps are published (the editor reads format 2 only, so not before), so the menu and the editor read
  the converted layouts at once; the user's "First" checked by hand after it. The settings' `shipped` list is left as it is (the shipped layouts already
  written are converted with the others).

### 3.9 The menu card

- The menu is the base card holding every other: `"menu": { "id": "menu", "card": "Menu", "show": "column", ... }`.
  Every layout has it: new ones start with it (the base layout), the user's and the shipped ones were given it.
- Its own fields: `show` (`column`, its cards under each other, with `perColumn` and `columns` in columns; or `row`),
  the limits and `rest`, `submenus` (how submenus open in this layout unless a card says otherwise, over General's),
  and its style (background, border, radius over the theme's menu look).
- Fixed: not moved, copied or deleted; no rules, no title, its name the layout's.
- In the editor the outer card of the cards view, selected by its heading; its panel: Inside (Shows, the limits,
  Submenus open) and Style.

### 3.8 Tests

- Unit tests: the format read (every `show`, the limits, `rest`, `shownWhen`, `titleAs`, `template`, rules and
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

## 6. As built

### 6.1 Step 1: the DLL and format 2

- Read onto the cards the DLL had: a format 2 card's `content` is its lines, one card (or divider, or search box) to
  a line; `show` and the rest on the card (`TCard.Shows`, `PerRow`, ..., `Templates`, `TemplatesBy`); a rule's
  `template`. Format 1 is read as before onto the same cards (`menu`: show submenu; `buttons`: show row).
- Placed (`Dexmenu.Place`): a card holding cards, or a card showing its found items in a row or column, becomes a
  holder view (`vkGroup`) with its inner lines (`Inner`), arranged by `Arrange` (a row `perRow` to a line, a column
  filled column by column, beyond the capacity "More" or nothing); "More" and a card's found items in a submenu open
  with `TPlacement.LevelOf`. Each inner card has its template (`Template`), picked by its place or its rule.
- Measured (`Dexmenu.Draw`): `LayLines` lays out lines at a width and recurses into holders; a level is its lines at
  the level's width. Drawn: a holder without a frame draws nothing; a framed one its box, its title (bold, or as a
  divider), and its own `hover` look while the selected card is inside it.
- Tested: the unit tests (format 1 as before, and format 2: a row holder and its boxes, a framed holder, templates by
  place and by rule, More and its submenu, rest none, a column per column, found items in a submenu, shownWhen at a
  right-click and in the preview, square, errors); `--compare` on the user's five layouts: the same boxes in every
  kind, in the preview and at a right-click.

### 6.2 Step 2: the editor, the shipped layouts, the conversion run

- The editor's model works on containers (the menu's `content`, a card's `content`): `cards`, `find` (with the
  container and the holding card), `moveCard` (into a container at a place), `moveCardNext` (above or below: in the
  target's container, a card in a plain row standing for the row; beside: into the target's row, or a new plain row
  of the two), `dropOnCard` (into a holder; a card with rules becomes a card with a submenu, its rules in a first
  card), `takeOut` (a plain row left with one card is that card again; a submenu left empty a card with rules).
- An older layout (format 1) is not opened: the cards view says it is converted once with the script. New layouts
  start from the DLL's base layout, now format 2.
- The cards view: a plain row is drawn as the line it was (selected from the gutter, then dragged by the grip beside
  it); other holders as cards with what they hold inside (a row side by side, else under each other); a card with
  rules shown in a row, column or submenu shows its templates as dashed cards ("+ Template", "x"), each selected as
  `<card id>~t<n>` and edited in the card panel (Names, Layout, Style).
- The shipped layouts converted with the same script; the user's five layouts converted (the old ones in
  `%APPDATA%\Dexmenu\layouts-format1-backup`) and compared: the same boxes in every kind.
- Tested: the editor's self-test, its fixtures written as format 2 (every move, drop, delete, divider and paste check
  as before, the older form refused); the unit tests; the editor rendered with the converted "First"; `--compare`.

### 6.3 Later changes

- A card's title above what it shows inside it: only its own `title` (the name no longer stands in, nor the item it
  unfolded); the editor fills the title from the name when Shows is set to side by side or under each other, and a
  title equal to the name follows a new name. Default B's program cards got their names as titles (shipped and the
  user's copy).
- The editor has Undo and Redo (buttons, Ctrl+Z, Ctrl+Y or Ctrl+Shift+Z) over every change of the window's session;
  Delete removes the selected card only after a click in the cards view.
- A template has its own right-click menu (Copy style, Paste style) and is the target of Ctrl+Shift+C / V when
  selected; before, the menu was its card's and pasted there.
- Tested: the unit tests (no title without one); the editor page in a browser (delete, undo, redo; a style pasted
  onto a template; a renamed name followed by its title).

### 6.4 The menu card

- The DLL keeps the menu as a card (`ILayout.MenuCard`, owning the menu's lines); a format 1 layout's has the defaults.
  The top level is placed as its lines, or arranged as the menu card says (a row, or columns of a set number, as any
  holder); the menu window is drawn in the theme's menu look with the menu card's style over it; its `submenus`
  overrules General's for the layout (the menu and the preview).
- The editor gives every layout's menu its id, name and show when it opens it; the cards view draws it as the outer
  frame, selected by its heading.
- Every layout given it: the user's five (their menus compared again: the same, but Default B's program cards, which
  now show their own titles), the shipped ones, the base layout, and the conversion script's output.
- Tested: unit tests (the menu card read; its cards in columns of 2, filled column by column; the window drawn in its
  style); the editor's self-test (every layout's menu card); the editor rendered with the menu card selected.
- A row of found items without `perRow` fills its card's width: each inner card its content's width, the room left
  shared by their weights (before, they stood at their content's width from the left). In the card panel "Fit in
  line" is "Height in row" (it is the card's height in a taller row, not its width); Height is greyed out with
  Square (the width sets the height). Tested: a unit test (the flowing row filled to its card's width).
- A row of found items without `perRow` is a grid: as many per row as its widest card lets fit, every row the same
  number in equal columns over the card's width (before: each card at its text's width, so six could wrap 3, 2, 1).
  Tested: a unit test (six found: rows of the same number).
- A template is copied on its own (its right-click menu "Copy template", or Ctrl+C with it selected) and pasted onto
  another card with rules (the card's right-click menu "Paste template", or Ctrl+V with the card or one of its
  templates selected): a copy added to that card's templates, through the clipboard, so also in another layout.
  Tested in the editor's self-test (pasted as a copy; not onto the remaining card or a card holding cards).
- A card selected in the editor that sits inside a submenu (in cards showing what they hold in a submenu) has the
  preview open the submenus on the way to it (`DexmenuPreviewMark`), as clicks on them would; one open already stays,
  and nothing closes for a card at the top. Tested by driving the preview from a script: a card two submenus deep
  marked, both submenus open and the card shown in the third level.
- A change in the editor rebuilds the preview with its submenus open as before: the open path is kept by its cards
  (layout card id, text, a "More" or not) across the rebuild and opened again as far as those cards are still there,
  then the path to the marked card opened as a selection does. Tested by driving the preview from a script: a card two
  submenus deep marked, the layout changed: both submenus open again; a top card marked with the submenus open, the
  layout changed: they stay open.
