# Plan 07: Groups: cards that belong together, shown or left out together

Status: not started; see Status.

- 2026-11-22: draft.

Builds on plan 02 (`02-PLAN-own-menu.md`: lines, cards, dividers, the editor). A start: more to be added.

## 1. What this is about

A layout puts cards that belong together after each other, often under a divider ("Programs", then a card per
program). When none of those cards finds anything at a right-click, the cards are left out but whatever belongs with
them is not tied to them: a divider stays, or is only left out by the general divider rules (plan 02 3.5), which do
not know which cards it was meant for.

## 2. The solution, in brief

A group: a group card in the layout, holding cards, notes, dividers and other group cards; in the top level and in a
card's menu. It has no header of its own and looks just like its content would without the group; a divider the
user wants goes into the group as content. Each group says when it is shown: always, only with any item, or only
with items that can be chosen (the default). Dividers never count. When a group is not shown, all of its content is
left out. In the editor it is a card that holds cards, and cards and groups are dragged into it as into any place.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Group | a group card in the layout format: its content, when it shows; placed as its content, or left out whole | -- | 3.1; 3.2 |
| Editor | the group card in the cards view: "+ Group", cards and groups dragged into and out of it; its panel | Group | 3.3 |
| Preview | a group that is not shown, as the menu shows it | Group; Open question 1 | 3.4 |
| Tests | 3.5 | Group | 3.5 |

## 3. Details

### 3.1 The group

- A group card: an entry in a layout's lines beside lines, dividers and notes, in the top level and in a card's menu
  (a submenu level) alike. Its content: lines of cards, notes, dividers, and group cards in it (nested, to any
  depth).
- Headless: the group itself shows nothing. A divider above its cards is a divider inside the group, its first
  content, so it goes when the group goes.
- Placed as if its content stood there.
- For now it looks the same as its content would without a group; a look of its own may follow (plan 03).
- The general divider rules (plan 02 3.5) still apply to what remains, inside the group and around it.

### 3.2 When a group is shown

Each group has a setting, `show`:

- **Always:** its content as it would show anyway.
- **Only with any item:** when anything in it is shown: an item, a card with a menu, a note, or a group in it that
  is shown.
- **Only with items that can be chosen** (the default for a new group; its name: Open question 2): when something in
  it can be chosen: an item of Windows' menu, a card with a menu that holds one, and later a command card (plan 06).
  A note does not count.

Dividers never count: a group with nothing but dividers is not shown (with Always its dividers are left to the
general divider rules). When it is not shown, all of its content is left out. A nested group decides first; the
group it is in then counts what that group shows.

### 3.3 The editor

- A group is a card in the cards view, as a card with a menu is: a card that holds cards, drawn with its content
  inside it (collapsible as a card with a menu).
- "+ Group" beside "+ Card", "+ Divider", "+ Note"; a new group shows only with items that can be chosen.
- Dragging is the same as for any card: a card, a divider, a note or a group card is dragged into a group, out of
  it, and between groups, onto the same drop places as elsewhere.
- Its panel: its name (editor only) and when it shows.

### 3.4 The preview

- To be set: Open question 1.

### 3.5 Tests

- Unit tests, per setting: a group whose cards find items shows its cards; a group whose cards find nothing is left
  out unless it shows always; a group with only a note: shown with any item, left out with items that can be chosen;
  a group with only dividers: left out; a divider inside a group left out with the group; a group with only hidden
  cards is left out unless it shows always; a nested group left out makes the group around it empty; a group in a
  card's menu.

## 4. Open questions

1. In the preview: is a group that is not shown left out, as at a right-click, or striped as the preview does with
   cards that show nothing?
2. The name of "items that can be chosen": an item of Windows' menu now, later command cards, macros or other things
   that do something when chosen. Which word?
