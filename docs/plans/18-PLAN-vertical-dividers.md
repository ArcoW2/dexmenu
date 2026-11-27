# Plan 18: Vertical dividers and a divider's thickness

Status: partly executed; see Status.

- 2026-11-27: draft.
- 2026-11-27: partly executed: everything but the check by hand.

Builds on plan 03 3.8 (a divider's own look), plan 11 (cards holding cards: rows, columns, grids) and the dividers as a
group's border and the spacer (plan 00's log).

## 1. What this is about

A divider is always a horizontal line between lines of cards. The user wants a divider that stands upright between
cards side by side, to split columns, and a divider whose line has a thickness of its own.

## 2. The solution, in brief

A divider placed between cards that stand side by side (in a row) is drawn upright, as high as that row, in a narrow
width of its own; it has no text. A divider inside a group laid out as a grid (columns with a number per column, or
rows with a number per row) has no fixed place among the cards, so it is drawn between every two columns (or rows) of
that grid. Every divider gets a thickness: its line's width. In the editor a divider dropped on a card's left or right
edge in a row lands beside it, and the divider's panel has a Thickness field.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Thickness | `thickness` on a divider, its line drawn that wide | 3.1; 6 |
| Upright | a divider among a row's cards kept there and drawn upright | 3.2; 6 |
| Grid | a divider in a grid group drawn between every two columns or rows | 3.3; 6 |
| Editor | Thickness; a divider dropped beside a card in a row; dividers upright in a row in the cards view; a hint for a divider in a grid | 3.4; 6 |
| Tests | unit tests and the editor's self-test | 3.5; 6 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| By hand | the user's layout at a right-click, a divider between two columns | the user | 3.5 |

## 3. Details

### 3.1 Thickness

- `"thickness"` on a divider: the line's width in DIP, more than 0 (absent: 1). Horizontal, upright and grid dividers
  alike; a spacer has no line, so none. A divider's height grows to hold a thicker line.
- A group's dividers as its border keep the theme's line (1).

### 3.2 Upright dividers in a row

- A row (a card holding cards side by side, `show: row`, without a number per row) keeps the dividers among its
  cards; today they are dropped. Each is drawn upright between its neighbours: as high as the row, its line in the
  middle of its width, from the top to the bottom.
- Its width between a widest and a narrowest: `"width"` (absent: its `height` when set, else a plain divider's
  height) and `"minWidth"` (absent: its line and a little room). It takes its widest while the cards beside it fit
  (their minimum widths, a wrapping card's longest word); when they do not, the upright dividers of that row give
  room, each in proportion to what it can give, down to their narrowest. The cards share the rest by their weights,
  as now. The same width and min width make a fixed width. A row wraps only when its cards do not fit even with the
  dividers at their narrowest.
- It has no text: a text set on it is not shown upright. A spacer leaves the room without a line.
- The group divider rules (a bottom divider left out before a divider; a plain divider left out after a bordered
  group) look only at dividers on a line of their own, not at upright ones.

### 3.3 A divider in a grid

- A group shown as columns with a number per column (a grid filled column by column), or as a row with a number per
  row (a grid filled row by row), places its cards by count. A divider inside it (anywhere among its cards) is then
  drawn between every two columns (upright, in each line of the grid) or between every two rows (a line of its own),
  in its look. With several dividers in such a group, the first counts.
- Upright ones in the grid's lines reach over the gap between lines, so they read as one line from top to bottom.

### 3.4 The editor

- The divider's panel: Thickness (a number, empty: 1), under Line colour; an upright divider (in a row, or a grid's
  between columns) Width and Min width in place of Height.
- A divider dragged onto a card's left or right edge: when that card stands in a row, the divider goes beside it in
  that row; elsewhere above or below it, as now.
- In the cards view a divider in a row is drawn as a thin upright bar; it is selected, dragged and deleted as any.
- A divider inside a grid group: its panel says it is drawn between every two columns (or rows).

### 3.5 Tests

- Unit tests: thickness read; a row with a divider: the divider kept, upright, its width, the cards beside it sharing
  the rest; a column grid with a divider: an upright divider between every two cards of each line; a row grid: a
  divider line between every two lines; the group divider rules not affected by upright dividers.
- The editor's self-test: a divider moved beside a card in a row, and before/after a card not in a row (above/below).
- By hand: the user's layout, a divider between two columns.

## 4. Open questions

None.

## 6. As built

- Dexmenu.Layout: `TLine.DividerThickness` ("thickness", more than 0, at most 50). Dexmenu.Place: `TViewCard.Vertical`;
  `HeldCards` keeps the layout's dividers when Arrange asks (KeepDividers; "More" still counts the cards only);
  `Arrange` takes the dividers out before the capacity and "More", then puts them back: in one row upright in their
  place (not before the first card or after the last), in one column as lines in their place; a grid's divider is the
  first one in the layout's content (`FirstDivider`), read from the layout because placing the content drops a divider
  at its start or end.
- Dexmenu.Draw: an upright divider's width (`UprightWidth`: its height, else a plain divider's, at least its line and
  8) is fixed in the row's width split and in the line's need; its height follows the cards beside it; its box reaches
  over half the gap to the rows above and below; drawn as a line in the middle from top to bottom. `LineThickness` for
  every divider line; a plain divider is at least its line and 8 high. The group divider rules skip upright dividers.
- Editor: a divider's drop zone on a card has left and right edges when the card stands in a row (`moveDividerNext`
  puts it into the row there; elsewhere before and after mean above and below); a divider in a row is drawn upright in
  the cards view; Thickness in the divider's panel; a hint for a divider in a row and one in a grid.
- Upright widths: `TLine.DividerWidth`, `DividerMinWidth`; `UprightWidth` (widest) and `UprightMin` (narrowest: its
  min width, at most its widest, else its line and 4). In the row's width split the dividers start at their widest;
  what the cards' minimums lack is taken from them in proportion to what each can give. SplitRows counts a divider at
  its narrowest, so a row wraps only when the cards do not fit even then. Editor: Width and Min width for an upright
  divider.
- Tested: unit tests (a divider in a row: kept, upright, its thickness, its width and height; its widest while the
  cards fit, narrower as they need, not below its narrowest; a grid by columns: an
  upright divider between the columns in each line; a grid by rows: a line between the rows); the editor's self-test
  (a divider beside a card in a row, and beside one not in a row); the user's layout drawn by a probe with a divider
  between two cards of a row.

