# Plan 09: Used rules, cards filled with the most used and most recently used items

Status: executed; see Status.

- 2026-11-23: draft.
- 2026-11-23: executed.

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
| Last use | the time of each item's last use kept in `usage.json` with its count | 3.2; 6.1 |
| Used rules | a rule with `used` (`most`, `recent`) and `rank` (none, one, a range, a range from high to low) finds items by use | 3.1; 6.2 |
| In the editor | the rule panel: the type (Name, Usage) showing its own group (Name: match kind, text, case sensitive, where; Usage: most used or most recent, Rank); the rules view's text for such a rule | 3.3; 6.3 |
| Tests | 3.4: unit tests, the editor's self-test, the preview | 3.4; 6.4 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|

## 3. Details

### 3.1 The rule

- `used` instead of `name`: `"most"` (the most used items) or `"recent"` (the most recently used), with a `rank`:
  none (all of them, in order), one number (`3`: the third) or a range (`"1-3"`). Ranks count from 1: the most used
  or most recent item is rank 1. A range from high to low reverses the order: `"3-1"` finds the same three items as
  `"1-3"`, the third first and the most used (or most recent) last.
- The ranks are counted over the items of this kind of right-click with a use that are in this menu and in the
  rule's states. A rank does not shift when another rule took an item: two cards side by side with `"1-3"` and
  `"4-6"` show the six most recent in two columns of three.
- Order: most used by count, a tie by the most recent; most recent by the last use.
- Everything else works as for a name: the states, `consume`, `also`, the card's `skipDuplicates`, the priority list,
  a found item taking its subitems, titles.
- Without a function here: the match kind, `caseSensitive`, `scope` and `path` (a used item is found at any depth).
- A rank past the items there finds nothing, as a name that matches nothing: with two used items, rank 3 finds
  nothing, a range `"2-5"` finds only the second and `"5-1"` the second, then the first. A card left without items is
  not drawn, as any card whose rules find nothing; no error, nothing in the log.

### 3.2 The last use

- `usage.json` gets `last` beside `kinds`, per kind and by the same key: the time of the item's last use, written with
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
- A wrong rank outlines the rule red, as an invalid rule is now: 0 or lower (`0`, `"0-3"`, `"3-0"`), text. At a
  right-click such a rule finds nothing, as an invalid rule does now (a regex that does not compile); no error.

### 3.4 Tests

- `most` and `recent` with no rank, one rank and a range; a rank past the items there (no items, the card not drawn,
  no error); a range partly past them; a reversed range (`"3-1"`), also partly past them; a wrong rank finding
  nothing; ranks fixed when an earlier rule took an item; with `also`, `consume: false`, the states and
  `skipDuplicates`.
- The last use written with each choice; an older `usage.json` without times read; the order of a tie.
- The editor's self-test: the type switched between Name and Usage, only that type's group shown, the other type's
  keys gone from the rule, the rank checked (0, `"0-3"` and text outlined red, `"3-1"`
  not), the layout written.

## 4. Open questions

None.

## 6. As built

### 6.1 Last use

- `"last": { "<kind>": { "<key>": "2026-11-23T14:05:09.120Z" } }` at the top of `usage.json`, beside `kinds`: a
  separate object, so an item key can never clash with it. The time is UTC in a fixed form, so comparing the texts
  orders the times; nothing parses them.
- Written in the same write as the count (`CountChoice`, under the same mutex). An older DLL keeps the object when it
  writes a count, as it rewrites the whole file it read.

### 6.2 Used rules

- The DLL parses `used` and `rank` in the rule itself (`Dexmenu.Rules`): a rule with both `name` and `used`, an
  unknown `used` or a wrong rank is invalid and finds nothing. A rank is a whole number from 1, or a text with one
  (`"2"`) or a range (`"1-3"`, `"3-1"`, spaces allowed).
- In the priority list a used rule ranks this menu's items with a count (at any depth, in its states, one per key),
  then takes the ranks asked for in their order, each unless an earlier rule took it (with `also`: all the same).
  The rest is as for a rule by name (`Take`: duplicates, `consume`, the subitems following).
- The counts and times are given to the placement when it is made (a second constructor), as the rules run then.
  At a right-click a used rule opens the submenus an extension fills only when opened when a count is of an item in
  one (`UsesUsage`), as the most used row does.

### 6.3 In the editor

- The type is a select at the top of the rule (Name, Usage). Switching rewrites the rule (`setRuleType`): to Usage
  `used: "most"` and the name, case sensitive, scope and path gone; to Name an empty `contains` (outlined red until
  filled) and `used` and `rank` gone. The Name group holds the match kind and text, case sensitive and Where; the
  Usage group "most used" or "most recently used" and Rank (a number written as a number, else as text).
- The rules view: "most used 1-3", "most recent 2", "most used" (no rank), then the shared parts as for a name.

### 6.4 Tests

- Unit tests (TestUsedRules): the ranks valid and wrong; most used and most recent with no rank, one, a range, a
  reversed range, ranges partly past the items, a rank past them; ranks fixed when an earlier rule took an item;
  `also`, `consume: false`; the default states taking a disabled item; no counts; `UsesUsage`; the time written with a
  choice, an older `usage.json` without times.
- The editor's self-test: the type switched both ways and the keys rewritten; ranks valid and wrong; a card with a
  wrong rank outlined red, a reversed range not. Which group shows is not in the self-test (it tests the model, not
  the page).
- In the preview, from the test data's counts: a card with `"1-2"` and one with `"4-3"` showing the two most used,
  then the fourth and third. The rule panel itself not yet looked at by hand.
