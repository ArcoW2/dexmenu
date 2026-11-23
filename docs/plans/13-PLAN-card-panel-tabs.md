# Plan 13: The card panel in tabs: its fields grouped by what they are about

Status: not started; see Status.

- 2026-11-23: draft.

Builds on plan 02 (`executed/02-PLAN-own-menu.md`: the editor's card panel, 3.5) and plan 03 (`03-PLAN-menu-look.md`:
the size and look fields, 3.5, 3.6). Plans 10, 11 and 12 add fields to the same panel.

## 1. What this is about

The editor's card panel shows every field of a card in one long column: names, texts, the hint, the comment, hidden,
how submenus open, the size, the look, duplicates, items as buttons, the rename, then the rules. They are in the
order they were built, not by what they are about, so a field is found by scrolling and reading. Plans 10 (the icon
picker), 11 (several found as cards, per row, square) and 12 (own rules) add more.

## 2. The solution, in brief

The card panel gets tabs, each holding the fields of one subject: Names (what the card and its items are called and
show as text, the icon, the hint, the comment), Rules (what the card finds), Inside (how what it found is shown and
opens), Layout (its size and place on its line) and Look (its colours and corners). Above the tabs stays what says
which card this is. A card shows only the tabs that apply to its kind. The tab chosen stays when another card is
selected; a tab with anything set in it is marked, and the Rules tab shows a problem in red.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Tabs | the card panel's fields in the tabs Names, Rules, Inside, Layout, Look; per kind of card the tabs that apply | -- | 3.1; 3.2 |
| Tab marks | a tab with anything set marked; the Rules tab red with an invalid rule; its count of rules | Tabs | 3.3 |
| Tab kept | the chosen tab kept across selections; the Rules tab chosen when a rule is selected in the rules view or the preview | Tabs | 3.3 |
| Tests | 3.4 | Tabs | 3.4 |

## 3. Details

### 3.1 The tabs and their fields

Every field of the card panel now, in its tab (a field still to come in brackets, with its plan):

- **Names:** Name (the editor's), Title, Rename (regex, replace with), Extra text, Extra text at, Icon (with plan 10's
  picker), Hint, Hint regex (replace with), Comment (the editor's only).
- **Rules:** + Rule and the card's rules (each with its type, plan 09; [Edit Dexmenu, Windows' menu: plan 12]),
  Duplicates (skip: one item per name), Hidden.
- **Inside:** Items as buttons, [Several found: on lines, in a submenu, as cards; Per row: plan 11], Submenus open.
- **Layout:** Weight, Min width, Height, Wrap, Fit in line, [Square: plan 11].
- **Look:** Background, Text colour, Border, Radius, Hover background, [the pressed look when it gets fields].

Hidden sits with the rules because what it changes is where the found items go (nowhere), not how the card looks.
Submenus open sits in Inside: it is about what opens from the card.

### 3.2 Per kind of card

- A card with rules: all five tabs.
- A card with a menu: Names (no Rename), Inside (Submenus open), Layout, Look; no Rules tab (its rules are in the
  cards of its menu).
- The remaining card: Names (Name, Title, Extra text, Hint, Comment; no Icon, no Rename), Inside (Submenus open); the
  Rules tab holds the text that says what the remaining card does; no Layout or Look (its items each take a line of
  their own, in their own look).
- A note: no tabs (its text, where its text goes, and its size are few enough to stay one column).
- A divider, the search box, the most used row: no tabs, as now.
- Dexmenu's own card (until plan 12 turns it into a rule): Names (Title, Icon, Extra text), Layout, Look.

### 3.3 Marks and the tab kept

- A tab with anything set in it (a field not at its default) shows a dot, so it is seen without opening it where a
  card has something of its own.
- The Rules tab shows the number of the card's rules ("Rules 3") and is red when one of them is invalid, as the card
  is outlined red in the cards view.
- The tab chosen stays chosen when another card is selected; when that card's kind has no such tab, its first tab
  shows. Selecting a rule (in the rules view, or by clicking an item in the preview) shows the Rules tab with the rule
  selected.
- The tab chosen lasts the editor window's session; not saved.

### 3.4 Tests

- The editor's self-test: per kind of card the tabs shown; every field of the card panel in exactly one tab (a list
  in the model checked against the fields the panel builds); a tab's dot with a field set; the Rules tab's count and
  red with an invalid rule.
- By hand: the tab kept across selections, the Rules tab chosen from the rules view and from the preview.

## 4. Open questions

1. The tab names: Names, Rules, Inside, Layout, Look, or others?
2. Which tab first, for a card selected for the first time in a session: Names (the card's own), or Rules (what is
   edited most)?
