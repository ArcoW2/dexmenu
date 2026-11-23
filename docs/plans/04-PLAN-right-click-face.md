# Plan 04: A card's second face: its right-click menu

Status: not started; see Status.

- 2026-11-22: draft.

Builds on plan 02 (`executed/02-PLAN-own-menu.md`: cards, rules, the priority list, hidden cards, the editor) and plan 03
(`03-PLAN-menu-look.md`: the look). The build order (plan 00) gets it as a step of its own once agreed.

## 1. What this is about

A card has one face: hover or click opens or chooses it. Many items have related actions that are rarely used: the
other "Open with" programs, LexPen's compare items for a file, 7-Zip's variants, TortoiseGit's less common commands.
Placed in the menu they make it long; hidden they are gone. The user wants a second face per card: a right-click on
a card opens that card's own right-click menu, so the main menu shows what is used and the rest sits one right-click
away.

## 2. The solution, in brief

Every card can have a right-click menu: lines of cards, written in the layout as a card's menu is (`rightClick`),
filled by rules like any card, its rules part of the one priority list. In Dexmenu's menu a right-click on a card that
has one opens it next to the card, as a submenu opens; hover and a left click act as now. The keyboard opens it with
the Menu key or Shift+F10 on the selected card. The editor shows the right-click menu as a second part of the card,
and the preview opens it on a right-click as the menu does.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Layout | `rightClick` on a card: lines of cards; read, checked, its rules in the priority list | -- | 3.1 |
| Placement | the right-click menu placed as a card's menu is; found items there | Layout | 3.2 |
| Menu | a right-click (and the Menu key, Shift+F10) on a card opens its right-click menu; a mark on cards that have one | Placement | 3.3 |
| Editor | the right-click menu edited as a part of the card: cards dragged into it, added, deleted | Layout | 3.4 |
| Preview | a right-click in the preview opens it as in the menu | Menu | 3.5 |
| Tests | 3.6 | -- | 3.6 |

## 3. Details

### 3.1 The layout

- `"rightClick": [ { "line": [ card, ... ] }, ... ]` on a card with rules or with a menu (the remaining card: Open
  question 5), next to its `rules` or `menu`. The cards in it are ordinary cards: rules, a menu, hidden,
  titles; they get ids as all cards do.
- Their rules are in the layout's one priority list (plan 02 3.3): who gets an item does not depend on which face it
  is in. A rule there with `consume: false`, or one elsewhere with `also`, shows an item on both faces.
- The remaining card is never in a right-click menu: the rest stays in the menu itself, so nothing disappears into a
  face the user has to know about.

### 3.2 Placement

- A right-click menu's lines are placed as a card's menu is (`MenuLevel` in `src/dll/Dexmenu.Place.pas`): a card
  places what it found at its own place, a card with a menu opens its lines, a hidden card shows nothing.
- A card whose right-click menu found nothing has no right-click face then (no empty menu opens).
- A Windows item with its own submenu (7-Zip) keeps it on hover and click; its right-click face is the layout's.

### 3.3 In the menu

- A right-click on a card with a right-click face opens it as a level next to the card, as a submenu opens; it
  closes as submenus do (Esc, a click elsewhere, a click on the card again). Choosing in it hands back the item's id
  as any choice does.
- Keyboard: the Menu key or Shift+F10 on the selected card opens it; the arrows and Enter act inside it as in a
  submenu.
- A mark shows which cards have a right-click face (its look in plan 03: a small mark at the card's right edge, apart
  from the submenu chevron).
- Programs that show the menu with `TPM_RIGHTBUTTON` (Windows' menu then also chooses on a right click): Open
  question 3.

### 3.4 The editor

- In the cards view a card with a right-click menu shows it under its own lines, headed "right-click", drawn apart
  from a card's menu (another border style), so the two faces cannot be mistaken for each other.
- The card's panel gets "+ Right-click menu" (an empty one with one new card) and, when there is one, "Remove
  right-click menu" (what happens to its cards' rules: Open question 4).
- Cards are dragged into and out of a right-click menu as into a card's menu (`moveCard`, `dropOnCard` in
  `layout-model.js` learn the second set of lines).
- The rules view names the face: "LexPen (right-click of Open...)".

### 3.5 The preview

- A right-click in the preview opens the face as the menu does; hover and click report the card and rule as now
  (plan 02 3.5). The same drawing engine, so the preview stays the result.

### 3.6 Tests

- Unit (the DLL): a right-click menu's cards take their items in the priority list's order; found items placed
  there; one that found nothing gives no face; `consume: false` shows an item on both faces; the remaining card
  refused in a right-click menu.
- The test host: a right-click on a card opens a level holding the right-click menu's cards; a click there hands
  back the item's id; the Menu key opens it too.
- The editor's self-test: a right-click menu added, a card moved into it and out, deleted with its rules handled as
  answered below.

## 4. Open questions

1. A card without a right-click menu of its own: does a right-click do nothing, act as a left click, or open a
   default face for every card (Dexmenu's own actions: "Hide this item", "Pin to most used", "Edit menu..." on that
   card)?
2. May a card inside a right-click menu have a right-click menu itself? Suggested: no, one level of faces.
3. When the program shows the menu with `TPM_RIGHTBUTTON`: should a right-click on a card with a face open the face
   (suggested), and on a card without one choose it, as Windows' menu would?
4. "Remove right-click menu": its cards' rules go to the card itself (as when a submenu's last card is deleted, plan
   02), or are they deleted with it?
5. May the remaining card have a right-click face, and if so, does every remaining item share it?
