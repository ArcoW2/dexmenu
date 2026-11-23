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
and corners). Each group is a panel the user drags where they want it: above or below another, they stand under each
other; onto another panel, the two become tabs; onto a tab, a new tab; into a tab, under each other in that tab,
which is then named for its panels ("Layout/Look"). A panel holds only its fields, never tabs. So all as tabs, all
under each other, or any mix is the user's choice, and the arrangement is remembered. A card shows only the groups that apply to its kind. A group with anything set in it is marked, and the Rules group shows a
problem in red; the tab chosen in a panel stays when another card is selected.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Groups | the card's name fixed at the top; the other fields in the groups Names, Rules, Inside, Layout, Look; per kind of card the groups that apply | -- | 3.1; 3.2 |
| Panels arranged | each group a panel, dragged above or below another (under each other), onto another (both tabs), onto a tab (a new tab) or into a tab (under each other in it, the tab named for its panels); the arrangement remembered | Groups | 3.3 |
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

- Each group is a panel: a box with its name on the border line (as a rule's box), its fields in two columns. A panel
  holds only its fields, never tabs.
- Under the fixed name stand, under each other, panels and sets of tabs. A set of tabs shows one tab at a time; a tab
  holds one or more panels under each other, and its name is its panels' names joined ("Layout/Look").
- A panel's name (on its border line) is its handle. Where it is dropped:
  - at the top or bottom edge of a panel or a set of tabs standing on its own: a panel on its own above or below it;
  - onto a panel standing on its own (its middle): the two become a set of tabs, a tab each;
  - onto a tab (its name in the tab line): a new tab of that set, after it;
  - inside a tab (its content): into that tab at that place, at the top, the bottom or between its panels; the
    panels there make room for it.
  A tab left without panels goes; a set of tabs left with one tab becomes the panels of that tab standing on their
  own. While dragging, the place it would go is shown; Esc cancels.
- So every arrangement is the user's: all as tabs of one set, all under each other, or any mix (Names on its own,
  then a set of tabs Rules, Inside and Layout/Look).
- The arrangement is remembered by the editor (its own storage, the same in every editor window) until changed; not
  in the layout. The first arrangement: every group a panel of its own, under each other, in the order Names, Rules,
  Inside, Layout, Look.
- A card whose kind lacks a group (3.2) shows the arrangement without that panel: a tab holding only panels it lacks
  is not shown, nor a set of tabs left with none, and a tab's name lists only the panels shown. The arrangement itself stays as
  the user made it.

### 3.4 Marks and the tab kept

- A group with anything set in it (a field not at its default) shows a dot by its name, on its tab or on its box's
  border, so it is seen where a card has something of its own.
- The Rules group shows the number of the card's rules ("Rules 3") and is red when one of them is invalid, as the card
  is outlined red in the cards view.
- In a set of tabs, the first tab shows until the user chooses another; the tab chosen stays chosen when another card
  is selected; when that card's kind has none of its panels, the set's first tab that applies shows. Selecting a rule (in the rules view, or by clicking an item in the
  preview) shows the Rules group (its tab chosen when it is one) and scrolls to the rule.
- The tabs chosen last the editor window's session; the arrangement is what is remembered.

### 3.5 Tests

- The editor's self-test: per kind of card the groups shown; every field of the card panel in exactly one group (a
  list in the model checked against the fields the panel builds); a group's dot with a field set; the Rules group's
  count and red with an invalid rule; an arrangement changed in the model (a panel above and below another, onto
  another as a set of tabs, onto a tab, into a tab at its top, bottom and between its panels, the tab's name; the last
  panel taken out of a tab, a set left with one tab) and read back after a restart; the name always at the top.
- By hand: dragging panels into tabs and under each other, Esc while dragging; the tab kept across selections; the
  Rules group shown and scrolled to from the rules view and from the preview.

## 4. Open questions

None.
