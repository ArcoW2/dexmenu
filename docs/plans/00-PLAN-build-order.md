# Plan 00: Build order: from one card to the full menu

Status: not started; see Status.

- 2026-11-21: draft.

Orders the parts of plan 01 (`01-PLAN-dexmenu.md`: the DLL, the hook, install), plan 02 (`02-PLAN-own-menu.md`:
cards, rules, layouts, the editor) and plan 03 (`03-PLAN-menu-look.md`: themes and the look) into steps. Each step
works on its own and is tested before the next starts. The details stay in those plans; this one says what comes
when.

## 1. What this is about

Plans 01 - 03 describe the whole of Dexmenu: what it shows, how it finds items, how it looks, how it is edited. Built
all at once it would be long before anything works. The simple things come first, each step usable and tested: a
menu of plain cards, then the editor's frame with its preview, then editing, then the look.

## 2. The solution, in brief

Seven steps. First the Delphi DLL takes over the spike's work. Then the simplest layout: one card, the remaining
card, with every item of Windows' menu shown as a plain card, so the DLL draws its own menu from the first day. Then
the settings app's frame: two panes, the right one the preview the DLL draws into. Then editing in it: cards, rules,
titles, dragging. Then the look: themes, colours, the card's structure, the layout of lines. After that the extras
(icons, use counts, search, "Edit menu...") and the installer; blur last.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Step 1: Delphi DLL | the spike in Delphi: handler, hook, late changes, the test host's checks passing | -- | 3.1 |
| Step 2: the base layout | the layout file with one card, the remaining card | -- | 3.2 |
| Step 3: plain cards | the DLL draws its own menu: every item a plain card, submenus as cards that open, the id handed back | Steps 1, 2 | 3.3 |
| Step 4: the editor's frame | the settings app: two panes, the preview on the right drawn by the DLL | Step 3 | 3.4 |
| Step 5: editing | cards, rules, titles, dragging, the remaining card moved; the preview following every change | Step 4 | 3.5 |
| Step 6: the look | themes, colours, the card's structure, lines of cards, dividers | Step 5 | 3.6 |
| Step 7: extras and install | icons, use counts and the most used row, search, "Edit menu...", the installer | Step 6 | 3.7 |
| Later | blur; animation | Step 6 | 3.8 |

## 3. Details

### 3.1 Step 1: the Delphi DLL

- What: plan 01's "Delphi DLL" part: the context menu handler, the hook (DDetours), noting the menu, following the
  changes made while shown (plan 01 3.4), the trace, the on / off switch, a build script. The C++ spike's work, in
  Delphi.
- Done when: the test host and `tests/run-tests.ps1` (plan 01 6.1, 6.2) pass against the Delphi DLL, `--late`
  included, and Explorer shows "from LexPen" as it does with the C++ DLL.
- Left out: everything drawn by Dexmenu; the arranged Windows menu stays only as long as the tests need it.

### 3.2 Step 2: the base layout

- What: the layout file of plan 02 3.5 in its smallest form: JSON with `//` comments, one layout `default`, one line,
  one card: the remaining card (`rules: ["remaining"]`), which takes every item no other rule took (plan 02 3.3).
  With no other cards, that is every item of Windows' menu. The global settings fixed in the DLL for now.
- Done when: the file is read, checked (exactly one remaining card), read again when it changes; a broken file gives
  Windows' own menu and a line in the log.
- Left out: every other rule kind, more cards, named layouts, the settings file.

### 3.3 Step 3: plain cards

- What: plan 02's window in its simplest form, drawn by the DLL (plan 03's engine with one fixed look): each item of
  Windows' menu a plain card alone on its line (so it looks like a menu item: its text, its state, the submenu
  mark); a Windows submenu a card that opens it next to it, filled when opened (Send to); keys, mouse, closing; the
  chosen id handed back; Explorer's late changes followed (an item enabled, a card removed, its line closed up).
  Windows' own menu on any error (plan 02 3.11). The remaining card at the root places every top-level item there as
  a card of its own, each with its subitems following it (plan 02 3.3), so the menu is Windows' menu as cards.
- Done when: in the test host and in Explorer, an Open dialog and Foldex the menu shows every item as a card, a
  choice runs the item as Windows' menu would (LexPen's items included, shown and hidden per selection), lazy
  submenus fill, a forced error shows Windows' menu.
- Left out: themes (one built-in look), icons, lines with several cards, dividers, rows, search.

### 3.4 Step 4: the editor's frame

- What: the settings app (plan 01 3.7): .NET 10, a WinForms window with WebView2, two panes. The left pane is
  WebView2 for the layout and settings (empty of editing for now: the layout shown as a tree of cards). The right
  pane is a window the DLL draws into: the preview (plan 02 3.8), from the seen items (plan 01 3.6) of a kind of
  right-click and the layout, live (hover, submenus open, a choice runs nothing).
- Also: the DLL records the seen items, so the preview has items to show.
- Done when: the app starts, loads the DLL (64-bit, no hook in the app), the preview shows the same menu as a
  right-click in Explorer for the same kind of right-click, and redraws when the layout file changes.
- Left out: editing.

### 3.5 Step 5: editing

- What: plan 02 3.3 and 3.5 in the editor: cards added, removed, titled; rules on a card (name, scope or path, match
  kinds, states); cards with a menu; dragging cards onto cards and between lines (rules kept as plan 02 3.5 says);
  the remaining card moved but never deleted; red outlines for useless cards; the extra text; named layouts (save,
  save as, active); per kind of right-click. Every change shown at once in the preview (the editor tells the DLL).
- Done when: plan 02 3.12's rule and editing tests pass; a layout made in the editor shows in Explorer as in the
  preview.
- Left out: the look beyond the built-in one.

### 3.6 Step 6: the look

- What: plan 03: theme files (palette, elements, states), the shipped themes (light, dark and the three pairs),
  backgrounds (colour, gradient, image with every fit, none: cards in space), the card's structure (icon, title,
  extra text above or below, mark, own background and colours), lines of several cards (weights, minimum widths,
  growing to the maximum then wrapping, `cardFit`), dividers, the icon row, submenu panels (next, under, replace with
  `<<`), the global settings tab. The editor gains the look's settings per card and per divider.
- Done when: plan 03 3.11's tests pass, the preview and Explorer give the same picture.

### 3.7 Step 7: extras and install

- In this order, each on its own:
  - icons (plan 02 3.8: the layout's, the item's own, cut from Explorer's drawing, the first letter);
  - use counts, the most used row, counts in the editor (plan 02 3.9);
  - search by typing (plan 02 3.6);
  - "Edit menu..." (plan 02 3.6);
  - the shipped layouts B - D (plan 02 3.10);
  - the installer: per machine, settings per user, off by default (plan 01 3.9); the full menu switch in the
    settings app (plan 01 3.10).

### 3.8 Later

- Blur (plan 03 3.4) and animation (plan 03 3.9).

## 4. Open questions

None.
