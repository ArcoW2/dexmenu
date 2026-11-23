# Plan 13: The card panel grouped: its fields by what they are about, in panels the user arranges

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

At the top of the card panel, always shown and fixed, the card's name. Under it the card's fields are grouped by
subject: Names (what the card and its items show as text, the icon, the hint, the comment), Rules (what the card
finds), Inside (how what it found is shown and opens), Layout (its size and place on its line) and Look (its colours
and corners). Each group is a panel the user drags where they want it: onto another panel, the two become tabs; at
the top or bottom of another, they stand under each other, also inside a tab, which is then named for its groups
("Layout/Look"). So all as tabs, all under each other, or any mix is the user's choice, and the arrangement is
remembered. A card shows only the groups that apply to its kind. A group with anything set in it is marked, and the Rules group shows a
problem in red; the tab chosen in a panel stays when another card is selected.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Groups | the card's name fixed at the top; the other fields in the groups Names, Rules, Inside, Layout, Look; per kind of card the groups that apply | -- | 3.1; 3.2 |
| Panels arranged | each group a panel, dragged onto another (tabs) or to the top or bottom of another (under each other, also inside a tab, the tab named for its groups); the arrangement remembered | Groups | 3.3 |
| Group marks | a group with anything set marked; the Rules group red with an invalid rule; its count of rules | Groups | 3.4 |
| Tab kept | the chosen tab of each panel kept across selections; the Rules group shown when a rule is selected in the rules view or the preview | Panels arranged | 3.4 |
| Tests | 3.5 | Groups | 3.5 |

## 3. Details

### 3.1 The groups and their fields

Every field of the card panel now, in its group (a field still to come in brackets, with its plan):

- **The card (fixed, at the top):** Name (the editor's). Always shown, stuck to the top of the card panel when it
  scrolls; not a group, not moved.
- **Names:** Title, Rename (regex, replace with), Extra text, Extra text at, Icon (with plan 10's
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
- The remaining card: Names (Title, Extra text, Hint, Comment; no Icon, no Rename), Inside (Submenus open); the
  Rules group holds the text that says what the remaining card does; no Layout or Look (its items each take a line of
  their own, in their own look).
- A note: no groups (its text, where its text goes, and its size are few enough to stay one column).
- A divider, the search box: no groups, as now.
- Dexmenu's own card (until plan 12 turns it into a rule): Names (Title, Icon, Extra text), Layout, Look.

### 3.3 Panels the user arranges

- Under the fixed name, panels stand under each other. A panel holds one or more tabs; a tab holds one or more groups
  under each other. A panel with one tab shows no tab line: just its box with the tab's name on the border line (as
  a rule's box). A tab's name is its groups' names joined ("Layout/Look"); each group in it keeps its own title above
  its fields when there are several.
- A group's title (on its panel's border line, on its tab, or above its fields inside a tab) is its handle:
  - dropped onto another panel (its middle, or its tab line): a new tab of that panel;
  - dropped at the top or bottom edge of another panel: a panel of its own above or below it;
  - dropped at the top or bottom of a group inside a tab: under each other with that group, in that tab.
  A tab left without groups goes, a panel left without tabs goes. While dragging, the place it would go is shown;
  Esc cancels.
- So every arrangement is the user's: all groups as tabs of one panel, all under each other, or any mix (Names and
  Rules as tabs, a third tab Layout/Look, Inside under them).
- The arrangement is remembered by the editor (its own storage, the same in every editor window) until changed; not
  in the layout. The first arrangement: every group a panel of its own, under each other, in the order Names, Rules,
  Inside, Layout, Look.
- A card whose kind lacks a group (3.2) shows the panels without it: a tab holding only groups it lacks is not shown,
  nor a panel left with no tab to show, and a tab's name lists only the groups shown. The arrangement itself stays as
  the user made it.

### 3.4 Marks and the tab kept

- A group with anything set in it (a field not at its default) shows a dot by its name, on its tab or on its box's
  border, so it is seen where a card has something of its own.
- The Rules group shows the number of the card's rules ("Rules 3") and is red when one of them is invalid, as the card
  is outlined red in the cards view.
- In a panel of tabs, the tab chosen stays chosen when another card is selected; when that card's kind has no such
  group, the panel's first tab that applies shows. Selecting a rule (in the rules view, or by clicking an item in the
  preview) shows the Rules group (its tab chosen when it is one) and scrolls to the rule.
- The tabs chosen last the editor window's session; the arrangement is what is remembered.

### 3.5 Tests

- The editor's self-test: per kind of card the groups shown; every field of the card panel in exactly one group (a
  list in the model checked against the fields the panel builds); a group's dot with a field set; the Rules group's
  count and red with an invalid rule; an arrangement changed in the model (a group onto another panel as a tab, above
  and below a panel, at the top and bottom of a group inside a tab, the tab's name; the last group taken out of a tab
  and of a panel) and read back after a restart; the name always at the top.
- By hand: dragging groups into tabs and under each other, Esc while dragging; the tab kept across selections; the
  Rules group shown and scrolled to from the rules view and from the preview.

## 4. Open questions

1. In a panel of tabs, which tab first, for a card selected for the first time in a session: the panel's first tab
   in the arrangement, or Rules whenever the panel holds it (what is edited most)?
