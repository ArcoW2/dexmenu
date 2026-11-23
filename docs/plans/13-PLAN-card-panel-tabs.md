# Plan 13: The card panel grouped: its fields by what they are about, as tabs or as groups under each other

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

The card panel's fields are grouped by subject: Names (what the card and its items are called and show as text, the
icon, the hint, the comment), Rules (what the card finds), Inside (how what it found is shown and opens), Layout (its
size and place on its line) and Look (its colours and corners). The user chooses how the groups show: as tabs, one
at a time, or as group boxes under each other, all at once; the choice is kept. A card shows only the groups that
apply to its kind. A group with anything set in it is marked, and the Rules group shows a problem in red; as tabs, the
tab chosen stays when another card is selected.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Groups | the card panel's fields in the groups Names, Rules, Inside, Layout, Look; per kind of card the groups that apply | -- | 3.1; 3.2 |
| Tabs or groups | the user's choice: the groups as tabs or as group boxes under each other; kept | Groups | 3.3 |
| Group marks | a group with anything set marked; the Rules group red with an invalid rule; its count of rules | Groups | 3.4 |
| Tab kept | as tabs: the chosen tab kept across selections; the Rules tab chosen when a rule is selected in the rules view or the preview | Tabs or groups | 3.4 |
| Tests | 3.5 | Groups | 3.5 |

## 3. Details

### 3.1 The groups and their fields

Every field of the card panel now, in its group (a field still to come in brackets, with its plan):

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

- A card with rules: all five groups.
- A card with a menu: Names (no Rename), Inside (Submenus open), Layout, Look; no Rules group (its rules are in the
  cards of its menu).
- The remaining card: Names (Name, Title, Extra text, Hint, Comment; no Icon, no Rename), Inside (Submenus open); the
  Rules group holds the text that says what the remaining card does; no Layout or Look (its items each take a line of
  their own, in their own look).
- A note: no groups (its text, where its text goes, and its size are few enough to stay one column).
- A divider, the search box: no groups, as now.
- Dexmenu's own card (until plan 12 turns it into a rule): Names (Title, Icon, Extra text), Layout, Look.

### 3.3 Tabs or groups under each other

- A switch at the right of the card panel's heading: Tabs, or Groups.
- **Tabs:** the groups' names as tabs under the heading, one group's fields shown at a time.
- **Groups:** every group that applies shown at once, under each other, each a group box with its name on the border
  line (as a rule's box), its fields in the panel's two columns.
- The choice is the user's, kept by the editor (its own storage, the same in every editor window) until changed; not
  in the layout.

### 3.4 Marks and the tab kept

- A group with anything set in it (a field not at its default) shows a dot by its name, on its tab or on its box's
  border, so it is seen where a card has something of its own.
- The Rules group shows the number of the card's rules ("Rules 3") and is red when one of them is invalid, as the card
  is outlined red in the cards view.
- As tabs, the tab chosen stays chosen when another card is selected; when that card's kind has no such group, its
  first one shows. Selecting a rule (in the rules view, or by clicking an item in the preview) shows the Rules tab
  with the rule selected; as groups, the panel scrolls to that rule.
- The tab chosen lasts the editor window's session; not saved.

### 3.5 Tests

- The editor's self-test: per kind of card the groups shown; every field of the card panel in exactly one group (a
  list in the model checked against the fields the panel builds); a group's dot with a field set; the Rules group's
  count and red with an invalid rule; the choice of tabs or groups kept.
- By hand: both ways of showing; the tab kept across selections, the Rules tab chosen from the rules view and from
  the preview; as groups, the panel scrolled to a rule selected elsewhere.

## 4. Open questions

1. The group names: Names, Rules, Inside, Layout, Look, or others?
2. As tabs, which tab first, for a card selected for the first time in a session: Names (the card's own), or Rules
   (what is edited most)?
