# Plan 17: The order of what rules find

Status: partly executed; see Status.

- 2026-11-27: draft.
- 2026-11-27: partly executed: everything but the check by hand.

Builds on plan 02 (rules, the priority list, the use counts), plan 09 (used rules, the times of last use) and plan 11
(found items shown inside a card or in a submenu).

## 1. What this is about

A card shows what its rules found in the order they found it: each rule's items as they stand in Windows' menu (a
used rule's in rank order), the rules one after another in the priority list's order. The user wants to choose that
order: per rule, and for the card as a whole, by recent use, by most use or alphabetically, each ascending or
descending.

## 2. The solution, in brief

A rule gets an order for what it finds: as found (the default, as now), most recent, most used or by name, and a
descending checkbox. A card gets an order for everything its rules found together: by rule (the default: each rule's
items in that rule's order, the rules in turn), most recent, most used or by name, with the same checkbox. After the
rules have run, each card's found items are sorted: first each rule's items by the rule's order, then, unless the card
says by rule, the whole list by the card's order. Ties keep the order found. By name is the text as shown. The
editor has an Order row in a rule's panel and in the card's Inside panel.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Format | `order` and `descending` on a rule and on a card, read by the DLL | 3.1; 6 |
| Sorting | each card's found items sorted after the rules ran | 3.2; 6 |
| Editor | the Order rows (rule panel, card's Inside panel), the rules view's text, the model's checks | 3.3; 6 |
| Tests | unit tests and the editor's self-test | 3.4; 6 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| By hand | the user's layout at a right-click, the Open with card by name | the user | 3.4 |

## 3. Details

### 3.1 The format

- On a rule: `"order"`: `"recent"` (most recently used first), `"used"` (most used first) or `"name"` (A to Z by the
  text as shown); absent: as found (Windows' menu's order; a used rule's rank order). `"descending": true` reverses
  it, also without an order (as found, reversed).
- On a card: `"order"`: `"recent"`, `"used"` or `"name"`; absent: by rule. `"descending": true` reverses the card's
  order; with no card order it has no function.
- Another value of `order`, or a `descending` that is no true/false, makes a rule invalid (it finds nothing); on a
  card it is a layout error, as other wrong card values are.
- An exclude rule (it takes nothing) and Dexmenu's own items' rules have no order: written there it has no function.
- `order` and `descending` are not used by any card or rule key yet (checked in Dexmenu.Layout, Dexmenu.Rules and the
  editor's model).

### 3.2 Sorting

- When: after the rules ran (TPlacement.Evaluate), on each card's list of found items, which every way of showing
  them uses (one item, each a card of its own, inside the card, in a submenu). "latest" has chosen what shows before
  that: the order then lines up those.
- A card's list holds each rule's items together, the rules in the priority list's order. First each rule's items
  are sorted by that rule's order; then, when the card has an order, the whole list by the card's order.
- Most recent: the time of last use (Dexmenu.Usage's "last", by UsageKey), newest first. Most used: the use count,
  highest first. Items never used have no time and a count of 0: last. Descending reverses the whole order, so those
  come first then.
- By name: the text as shown: the item's name with the rename it gets (as TViewCard.Title): a card showing its items
  inside it or in a submenu its template's rename (the template its rule names, else the first; no template: no
  rename), any other card its own rename; Dexmenu's own items their own text. Compared without case.
- Ties (the same time, count or name): the order found. The sort is stable.
- The remaining card is not sorted: Windows' order stays.

### 3.3 The editor

- A rule's panel, for a rule by Name or by Usage that is not an exclude rule: a row "Order" with a select (as found,
  most recent, most used, name) and a checkbox "descending".
- The card's Inside panel, for a card with rules (not a holder, a note or the remaining card): a row "Order" with a
  select (by rule, most recent, most used, name) and a checkbox "descending", the checkbox disabled with "by rule".
- The rules view: ", order <what>" and ", descending" after a rule's other settings.
- The model's ruleProblem: a wrong `order` or `descending` outlined red. Switching a rule to Edit Dexmenu or Windows'
  menu drops `order` and `descending`; switching to an exclude rule too.

### 3.4 Tests

- Unit tests: a menu with items of known counts and times; a rule by name sorted by each order, ascending and
  descending (never used ones last, first when descending); a used rule ("1-3") by name; two rules on one card, each
  sorted, the card by rule and by name; ties in the order found; by name with a rename; wrong values invalid.
- The editor's self-test: ruleProblem on the new values; the switch to another type dropping them.
- By hand: the user's layout, the Open with card by name.

## 4. Open questions

None.

## 6. As built

- Dexmenu.Rules: `TOrderBy` (as found, recent, used, name) and `ParseOrder`, shared by a rule (`TRuleSpec.Order`,
  `Descending`) and a card (`TCard.Order`, `Descending`, read in ParseShow). A wrong value: the rule invalid (it finds
  nothing, the layout still valid), the card a layout error.
- Dexmenu.Place: `TPlacement.SortFound` at the end of Evaluate. A card's list is grouped by rule in the order the
  rules ran, each group sorted by its rule, then the whole list by the card's order when it has one. Every key is
  read once per item; ties go by the place the item had before that sort (the sort itself is not stable, the place
  is the last key). The remaining card is left as it is.
- Editor: one helper (`orderFields`) gives the select and the "descending" checkbox to the rule panel (rules by Name,
  not exclude, and by Usage) and to the card's Inside panel (cards with rules, not the remaining card; descending
  disabled, and dropped, with "by rule"). Ticking exclude, or switching a rule to Edit Dexmenu or Windows' menu, drops
  `order` and `descending`.
- Tested: unit tests (TestOrder: as found ascending and descending, most used, most recent, by name both ways, the
  three most used by name, two rules by rule and by the card's order, by name with a rename, wrong values on a rule
  and on a card); the editor's self-test (ruleProblem on the values, also on a rule by use; dropped on a switch to
  Edit Dexmenu). While at it the unit tests' checks of a wrong `latest`, an exclude rule by use and a wrong `order`
  were made to check the rule itself: they had used a layout without the remaining card, invalid whatever the rule.

