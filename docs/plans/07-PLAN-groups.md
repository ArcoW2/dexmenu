# Plan 07: Groups: cards that belong together, under a divider of their own

Status: not started; see Status.

- 2026-11-22: draft.

Builds on plan 02 (`02-PLAN-own-menu.md`: lines, cards, dividers, the editor). A start: more to be added.

## 1. What this is about

A layout puts a divider above cards that belong together ("Programs", then a card per program). When none of those
cards finds anything at a right-click, the cards are left out but their divider is not tied to them: it stays, or is
only left out by the general divider rules (plan 02 3.5), which do not know which cards it was meant for.

## 2. The solution, in brief

A group: a group card in the layout, holding cards, notes, dividers and other group cards, with a divider as its
header; in the top level and in a card's menu. It looks just like its content and the divider would without the
group. In the editor it is a card that holds cards, and cards and groups are dragged into it as into any place. Each group says when it is shown: always,
only when it shows any item, or only when it shows an item that can be chosen. When it is not shown, its header and
everything in it are left out.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Group | a group card in the layout format: its header divider, its content, when it shows; placed as its content, or left out whole | -- | 3.1; 3.2 |
| Editor | the group card in the cards view: "+ Group", cards and groups dragged into and out of it; its panel | Group | 3.3 |
| Preview | a group that is not shown, as the menu shows it | Group; Open question 1 | 3.4 |
| Tests | 3.5 | Group | 3.5 |

## 3. Details

### 3.1 The group

- A group card: an entry in a layout's lines beside lines, dividers and notes, in the top level and in a card's menu
  (a submenu level) alike. It has its header (a divider: its text and alignment) and its own content: lines of
  cards, notes, dividers, and group cards in it (nested, to any depth).
- Placed as if its content stood there, with its header above it.
- For now it looks the same as its content and divider without a group; a look of its own may follow (plan 03).
- The general divider rules (plan 02 3.5) still apply to what remains, inside the group and around it.

### 3.2 When a group is shown

Each group has a setting, `show`:

- **Always:** its header and its content, whatever the content shows (an empty group shows its header only).
- **Only with any item:** when anything in it is shown: an item, a card with a menu, a note, or a group in it that
  is shown. Its dividers alone do not count.
- **Only with executable items:** when something in it can be chosen: an item of Windows' menu, a card with a menu
  that holds one, and later a command card (plan 06). A note does not count.

When it is not shown, its header and all of its content are left out. A nested group decides first; the group it is
in then counts what that group shows.

### 3.3 The editor

- A group is a card in the cards view, as a card with a menu is: a card that holds cards, drawn with its content
  inside it (collapsible as a card with a menu).
- "+ Group" beside "+ Card", "+ Divider", "+ Note".
- Dragging is the same as for any card: a card, or a group card, is dragged into a group, out of it, and between
  groups, onto the same drop places as elsewhere.
- Its panel: the header (text, alignment) and when it shows.

### 3.4 The preview

- To be set: Open question 1.

### 3.5 Tests

- Unit tests, per setting: a group whose cards find items shows its header and cards; a group whose cards find
  nothing is left out unless it shows always; a group with only a note: shown with any item, left out with
  executable items only; a group with only hidden cards is left out unless it shows always; a nested group left out
  makes the group around it empty.

## 4. Open questions

1. In the preview: is a group that is not shown left out, as at a right-click, or striped as the preview does with
   cards that show nothing?
2. Does the header have to have a text, or can it be a plain divider?
3. Which setting does a new group get: always, only with any item, or only with executable items?
