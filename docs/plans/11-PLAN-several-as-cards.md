# Plan 11: A card that finds several items: on lines, in a submenu or as cards side by side

Status: not started; see Status.

- 2026-11-23: draft.

Builds on plan 02 (`executed/02-PLAN-own-menu.md`): a card places what it found where it stands (3.3), items as
buttons in a card (3.3, 6.1); plan 03 (`03-PLAN-menu-look.md`): a card's size on its line (3.5) and its own look
(3.6); plan 09 (`executed/09-PLAN-used-rules.md`): used rules, whose ranks often find several items.

## 1. What this is about

A card whose rules find more than one item always shows them the same way: each found item a card of its own, each on
its own line, stacked at the card's place. A user cannot have them side by side (the three most used items of plan 09
next to each other), nor folded away under the card's title in a submenu. And the cards made for the found items
cannot be given a look of their own (square, in a colour of the user's choice): they take the theme's.

## 2. The solution, in brief

A card gets a setting for what it does when its rules find several items: on lines (as now, the default), in a
submenu (the card shows its title and opens the found items as a submenu), or as cards (the found items as inner
cards side by side in the card's place, at most a set number per row, more on further rows). The inner cards take
the card's own size and look (height, square, background, text colour, border, radius, hover), so a user makes them
square and coloured on the card itself. One found item shows as now. The editor's card panel gets the choice and the
number per row.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Several setting | `"several"`: `lines` (default), `submenu`, `cards`, with `"perRow"` for cards; read by the DLL | -- | 3.1 |
| In a submenu | a card finding several items shown with its title and a submenu holding them | Several setting | 3.2 |
| As cards | the found items as inner cards in the card's place, at most `perRow` per row, wrapping | Several setting | 3.3 |
| Square | `"square": true`: a card (and so its inner cards) as high as it is wide | -- | 3.4 |
| In the editor | the card panel: "Several found" (on lines, in a submenu, as cards), "Per row", "Square"; the preview follows | Several setting | 3.5 |
| Tests | 3.6 | -- | 3.6 |

## 3. Details

### 3.1 The setting

- `"several"` on a card with rules: `"lines"` (each found item a card on its own line, as now; the default when not
  set), `"submenu"` or `"cards"`.
- `"perRow"` with `"cards"`: the most inner cards side by side; not set: all on one row.
- Only what the card found counts: one found item shows as one card, as now, whatever the setting; none, the card is
  not shown, as now.
- Not on the remaining card (it keeps its own placing) nor on a card with a menu (it has no rules). With
  `"buttons": true` the buttons win: `several` is not used.

### 3.2 In a submenu

- The card shows once, with its title (`title`, else its name) and the submenu mark; the found items are its
  submenu, each a line as in any submenu, in the order found.
- It opens as any submenu does: the card's own `submenus`, else the global setting.
- A found item with a submenu of its own keeps it: a submenu in the submenu.

### 3.3 As cards

- The card's place on its line (its share by `weight`, its `minWidth`) is filled by its inner cards: up to `perRow`
  side by side, equally wide, more on further rows under them, all inside the card's place. The other cards on the
  line keep their places; the line is as high as its highest card.
- Each inner card is a card as any: its item's title and icon (the card's `icon` first, as for items a card places),
  hover, a click, keys, its submenu when the item has one.
- Each inner card takes the card's own size and look: `height`, `square` (3.4), `background`, `foreground`, `border`,
  `borderWidth`, `radius`, `hover`, `pressed`, `extra`. The card itself draws nothing around them: no frame, no
  title.
- A tall or square inner card shows its icon on top and its title under it, as any tall card does (plan 03 3.6).
- Keys: the arrows move through the inner cards row by row, as through cards side by side.

### 3.4 Square

- `"square": true` on a card: as high as it is wide, whatever its `height`. For inner cards, each inner card is
  square at its own width.
- Useful on any card, not only on inner cards: a row of square cards with their icons on top.

### 3.5 In the editor

- In the card panel of a card with rules, under the rules: "Several found", a choice of on lines, in a submenu, as
  cards. With as cards, "Per row" (empty: all on one row; a number from 1).
- "Square" with the size fields (weight, min width, height).
- The preview shows the card as the setting says, from the seen items, as for any card.

### 3.6 Tests

- Placing: a card finding one item (one card, each setting), several (on lines, in a submenu, as cards), none (not
  shown); `perRow` 2 with three found items (two rows); a card with `buttons` and `several` (buttons win).
- Drawing: inner cards inside the card's place, equally wide, square when set, with the card's look; the hit test on
  an inner card; keys through the rows.
- A submenu: the card's title, the found items in it, a found item's own submenu kept.
- With plan 09: a used rule finding the three most used, as cards, `perRow` 3: one row of three.
- The editor's self-test: the choice written (`several`, `perRow`, `square`) and taken out again; the preview redrawn.

## 4. Open questions

1. The maximum: is it per row (more found items wrap onto further rows, as planned now), or a total (the cards
   shown, the rest left out or put in a "More" submenu)?
2. Items as buttons (`"buttons": true`) is close to this: should it become a fourth choice of the same setting
   (`"several": "buttons"`), with the layouts that use `buttons` read as before?
