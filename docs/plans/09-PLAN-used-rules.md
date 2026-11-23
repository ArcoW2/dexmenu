# Plan 09: Used rules, cards filled with the most used and most recently used items

Status: not started; see Status.

- 2026-11-23: draft.

Builds on plan 02 (`executed/02-PLAN-own-menu.md`): its rules (3.3), the priority list, and the use counts with the most used
row (3.9).

## 1. What this is about

The most used row (plan 02 3.9) is one fixed row: as many items as the global setting says, in one line. A user who
wants the most used or the most recently used items in a shape of their own (two columns of three, the top one large,
the next ones in a submenu) cannot make it: a rule only finds items by their name. And only counts are kept, so
"most recently used" cannot be known at all.

## 2. The solution, in brief

A rule can find items by their use instead of by name: the most used or the most recently used, with a rank that is
all of them, one (the third) or a range (the first three). Everything else about rules stays as it is, so any card
can show them and cards are not changed. With each choice the DLL keeps the time of the item's last use beside its
count. The editor's rule panel chooses the rule's type, Name or Usage; each has its own group of fields, and only the
chosen type's group is shown.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Last use | the time of each item's last use kept in `usage.json` with its count | -- | 3.2 |
| Used rules | a rule with `used` (`most`, `recent`) and `rank` (none, one, a range) finds items by use | Last use | 3.1 |
| In the editor | the rule panel: the type (Name, Usage) showing its own group (Name: match kind, text, case sensitive, where; Usage: most used or most recent, Rank); the rules view's text for such a rule | Used rules | 3.3 |
| Tests | 3.4 | -- | 3.4 |

## 3. Details

### 3.1 The rule

- `used` instead of `name`: `"most"` (the most used items) or `"recent"` (the most recently used), with a `rank`:
  none (all of them, in order), one number (`3`: the third) or a range (`"1-3"`).
- The ranks are counted over the items of this kind of right-click with a use that are in this menu and in the
  rule's states. A rank does not shift when another rule took an item: two cards side by side with `"1-3"` and
  `"4-6"` show the six most recent in two columns of three.
- Order: most used by count, a tie by the most recent; most recent by the last use.
- Everything else works as for a name: the states, `consume`, `also`, the card's `skipDuplicates`, the priority list,
  a found item taking its subitems, titles.
- Without a function here: the match kind, `caseSensitive`, `scope` and `path` (a used item is found at any depth).
- A rank past the items there finds nothing, as a name that matches nothing.

### 3.2 The last use

- `usage.json` per kind gets `last` beside the counts, by the same key: the time of the item's last use, written with
  each choice (as the count is, after the menu has closed).
- An item counted before this has no time and ranks after those that have one.
- A `usage.json` without `last` is read as before; the format number stays, as an older DLL ignores the new part.

### 3.3 In the editor

- The rule panel starts with the rule's type: Name or Usage. Each type has a group of its own, and only the chosen
  type's group is shown:
  - Name: the match kind and its text, case sensitive, Where (top level, anywhere, a path).
  - Usage: most used or most recently used, and a Rank field (empty, a number, a range).
- Below the group, for both types: the states, also when taken, skip duplicates, consumes the item, Delete rule.
- Switching the type writes the other kind of rule: to Usage, `name`, `caseSensitive`, `scope` and `path` are taken
  out and `used` is `most`; to Name, `used` and `rank` are taken out and `name` is an empty `contains`.
- The rules view shows such a rule as "most used 1-3" or "most recent 2".
- A wrong rank (`"3-1"`, text) outlines the rule red, as an invalid rule is now.

### 3.4 Tests

- `most` and `recent` with no rank, one rank and a range; a rank past the items there; ranks fixed when an earlier
  rule took an item; with `also`, `consume: false`, the states and `skipDuplicates`.
- The last use written with each choice; an older `usage.json` without times read; the order of a tie.
- The editor's self-test: the type switched between Name and Usage, only that type's group shown, the other type's
  keys gone from the rule, the rank checked, the layout written.

## 4. Open questions

None.
