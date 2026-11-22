# Plan 07: Groups: cards that belong together, under a divider of their own

Status: not started; see Status.

- 2026-11-22: draft.

Builds on plan 02 (`02-PLAN-own-menu.md`: lines, cards, dividers, the editor). A start: more to be added.

## 1. What this is about

A layout puts a divider above cards that belong together ("Programs", then a card per program). When none of those
cards finds anything at a right-click, the cards are left out but their divider is not tied to them: it stays, or is
only left out by the general divider rules (plan 02 3.5), which do not know which cards it was meant for.

## 2. The solution, in brief

A group: a part of the layout holding some lines of cards, with a divider as its header. It looks just like the
cards and the divider would without the group. When nothing in the group is shown, its divider is not shown either.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Group | a group in the layout format: its header divider and its lines; placed as its lines, the header left out when nothing below it shows | Open questions 1, 2 | 3.1 |
| Editor | groups made, filled and moved in the cards view | Group; Open question 3 | 3.2 |
| Preview | an empty group shown as the menu shows it | Group; Open question 4 | 3.3 |
| Tests | 3.4 | Group | 3.4 |

## 3. Details

### 3.1 The group

- In a layout's lines, an entry of its own beside lines, dividers and notes: its header (a divider: its text and
  alignment, or none) and its own lines of cards.
- Placed as if its lines stood there, with its header above them. When the group shows no card (each found nothing,
  is hidden, or is a card with a menu that shows nothing), the header goes as well.
- For now it looks the same as its cards and divider without a group; a look of its own may follow (plan 03).
- The general divider rules (plan 02 3.5) still apply to what remains.

### 3.2 The editor

- To be set: Open question 3.

### 3.3 The preview

- To be set: Open question 4.

### 3.4 Tests

- Unit tests: a group whose cards find items shows its header and cards; a group whose cards find nothing shows
  neither; a group with only hidden cards shows nothing.

## 4. Open questions

1. Can a group hold dividers and notes of its own, and other groups (nested)?
2. Can a group stand inside a card's menu (a submenu level), as well as in the top level?
3. In the editor: how is a group made and shown (a frame around its cards, "+ Group", selecting cards and grouping
   them), and how are cards dragged into and out of it?
4. In the preview: is an empty group's header left out, as at a right-click, or striped as the preview does with
   cards that show nothing?
5. Does the header have to have a text, or can it be a plain divider?
