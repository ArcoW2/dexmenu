# Plan 12: Dexmenu's own items found by rules, placed in any card

Status: executed; see Status.

- 2026-11-23: draft.
- 2026-11-23: executed.

Builds on plan 02 (`executed/02-PLAN-own-menu.md`): rules (3.3), Dexmenu's own items "Edit menu..." and "Windows'
menu" (3.6, 3.11); plan 09 (`executed/09-PLAN-used-rules.md`): a rule's type in the editor (Name, Usage).

## 1. What this is about

Dexmenu's own items, "Edit menu..." and "Windows' menu", are cards of their own (`"own": "editMenu"`). A card holds
one of them and nothing else: they cannot sit among other items in a card, be buttons in a card with buttons, or go
in a card's submenu beside the items its rules found.

## 2. The solution, in brief

A rule gets two more types beside Name and Usage: Edit Dexmenu and Windows' menu. Such a rule finds Dexmenu's own
item instead of Windows' items, so any card can place it where it places what its rules found: alone, among other
items, as a button, in a submenu. Each own item carries a tag (`editMenu`, `windowsMenu`), and when it is chosen the
DLL starts what the tag names instead of handing an id back to Windows. The own card goes: the DLL still reads one
as a card with an own rule, and the editor writes the rule form.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Own rules | a rule `{ "own": "editMenu" \| "windowsMenu" }` finding Dexmenu's own item, tagged, placed as any found item; chosen, its tag started | 3.1; 3.2; 6.1 |
| Own cards read as rules | a card with `"own"` read by the DLL as a card with one own rule | 3.3; 6.1 |
| In the editor | the rule's type: Name, Usage, Edit Dexmenu, Windows' menu; an own card turned into a card with an own rule; "+ Dexmenu" gone | 3.4; 6.1 |
| Shipped layouts | Default A - D written with own rules | 3.5; 6.1 |
| Tests | unit tests, the editor's self-test, the preview | 3.6; 6.1 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|

## 3. Details

### 3.1 The rule

- `{ "own": "editMenu" }` or `{ "own": "windowsMenu" }`: finds Dexmenu's own item, once per rule. Nothing else of a
  rule has a function there (name, use, states, `also`, `consume`, `skipDuplicates`); the priority does: it sets the
  item's place among the card's other found items, as for any rule.
- An unknown tag makes the rule invalid: it finds nothing, as any invalid rule.
- The item's title is Dexmenu's ("Edit menu...", "Windows' menu"); the card's `title`, `rename`, `icon`, `hint` and
  look apply as to any item the card places.
- Two rules with the same tag show the item twice; both run the same.

### 3.2 The item and its tag

- The found own item is an item of Dexmenu's, not of Windows' menu: it has no id, it carries its tag. It is placed as
  any found item: the only item of its card (the card shows it), one of several, a button in a card with buttons, an
  item in a card's submenu.
- Chosen: the menu closes and the DLL starts what the tag names, as the own card does now (`editMenu`: the last
  right-click written, the settings app started on the layout in use; `windowsMenu`: Windows' menu shown at the same
  place).
- Not counted in the use counts (it is no item of Windows'), so the most used row and used rules never show it; not
  in the search (that lists Windows' items).
- In the preview it is shown and chosen does nothing, as any item there.

### 3.3 Own cards

- A card with `"own"` is read by the DLL as a card with that card's title and one own rule: layouts already written
  keep working.
- The remaining card and cards with a menu are not affected.

### 3.4 In the editor

- The rule's type select gets Edit Dexmenu and Windows' menu beside Name and Usage. These two have no group of
  fields; only Delete rule. Switching to one writes `own` and takes out the name, the use and the shared fields;
  switching away takes `own` out.
- The rules view shows such a rule as "Dexmenu: Edit menu..." or "Dexmenu: Windows' menu".
- A layout opened with an own card: the card becomes a card with an own rule (the change saved with the layout, as
  any other bringing up to date).
- "+ Dexmenu" goes: an own item is added as a rule on any card ("+ Rule", then its type).

### 3.5 Shipped layouts

- Default A - D get their "Edit menu..." and "Windows' menu" as cards with an own rule. Layouts already written into
  the layouts folder are left as they are (3.3 reads them).

### 3.6 Tests

- Placing: an own rule alone in a card, with a name rule in the same card (the order by priority), in a card with
  buttons, in a card's submenu; two own rules with the same tag; an unknown tag (nothing found); an own card read as
  a card with an own rule.
- Choosing: the tag handed to the show call (the command), no id; not counted in `usage.json`.
- The editor's self-test: the type switched to and from Edit Dexmenu and Windows' menu, the keys rewritten; an own
  card turned into a card with an own rule.
- By hand: "Edit menu..." as a button in a card with buttons, at a right-click in Explorer.

## 4. Open questions

None.

## 6. As built

### 6.1 Own rules

- The rule unit parses `own` first: with `name` or `used` too, or an unknown tag, the rule is invalid. Only its
  priority is read.
- A found item is `{ Node, Rule, Own }`: an own rule adds one with no node and its tag (`ccEditMenu`,
  `ccWindowsMenu`) to its card's list, in the priority order with the card's other rules. Placed as a command card
  (`vkCommand`): the card's only item, one of several (a line of its own), or a button in a card with buttons. Its
  text is Dexmenu's ("Edit menu...", "Windows' menu"); the card's `title` when it is the card's only item, and the
  card's rename. Choosing it hands the tag to the show call as the own card did; it is not counted.
- An own card (`"own"` on a card) is read as a card with one own rule and its name as its `title`; the editor turns
  it into that when a layout opens (its name the title only when it is not the item's own text), saved with the
  layout.
- In the rule panel the two types have no fields of their own: a line saying what the item does; no states, no
  options. The rules view: "Dexmenu: Edit menu...", "Dexmenu: Windows' menu".
- Tested: unit tests (alone, the card's title on it, beside a rule by name in both priority orders, twice, an unknown
  tag, own with a name, as a button tagged editMenu, an own card read as a card with an own rule tagged windowsMenu,
  not among the remaining items); the editor's self-test (the types switched both ways, outlined red when wrong, own
  cards converted, also in a menu); the preview of a layout with own cards. Not yet tried at a right-click.
