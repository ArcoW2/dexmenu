# Plan 02: Dexmenu's own menu: drawn by Dexmenu, cards and rows, every item found by rules

Status: partly executed; see Status.

- 2026-11-21: draft.
- 2026-11-21: partly executed: the item tree and the window's first form (plan 00 steps 2 and 3).
- 2026-11-21: partly executed: the preview's first form (plan 00 step 4).
- 2026-11-22: partly executed: the rules, layout editing, layouts and the preview (plan 00 step 5 and after; plan 05).
- 2026-11-22: partly executed: note cards; how submenus open.
- 2026-11-22: partly executed: "Edit menu..." and Windows' menu (Shift, the item).
- 2026-11-22: partly executed: the global settings (marks, widths per level, a rule's default states).
- 2026-11-22: partly executed: use counts and the most used row.
- 2026-11-22: partly executed: the text size (Ctrl+scroll).
- 2026-11-22: partly executed: the use counts in the editor.
- 2026-11-22: partly executed: icons (the layout's, the item's own bitmap).
- 2026-11-22: partly executed: Dexmenu's own items as cards; the shipped layouts Default A, C and D.
- 2026-11-22: partly executed: the items' icons in the preview.

Builds on plan 01 (`01-PLAN-dexmenu.md`): its Delphi DLL, the hook on the show call, following the changes a program
makes while the menu is shown, and handing back the chosen id. Plan 01's layout engine and its arranged Windows menu
are replaced by this plan.

## 1. What this is about

Plan 01 shows the arranged items as a normal Windows menu. A Windows menu can only do lines of text with an icon,
submenus, lines between them and columns. The user wants a menu of Dexmenu's own design: cards, several cards next to
each other, a row of icons as Windows 11's Cut / Copy / Paste row, a card that holds a submenu. The structure is
defined in a file. Windows' items are found by rules (exact, contains, starts with, regex; case insensitive), with
disabled items taken or left per rule, and every item no rule found still placed somewhere.

## 2. The solution, in brief

The DLL keeps catching the show call with Windows' items, as in plan 01, but instead of a Windows menu it opens a
window of its own, drawn by Dexmenu from a layout. A layout is lines of cards and dividers; each card has rules that
take Windows' items by their text and where they sit, and is an action when it finds one item, a card with a submenu
when it finds more. Global settings decide how submenus open, the menu's width per level and the marks for actions
and submenus; a card can overrule them. A card with a menu has no rules; the cards in its submenu do. Every layout has
one remaining card that takes every item no rule took; the user puts it where the rest should go, at the root or in a
submenu. A row of the most used items comes from counting every choice. The
window follows the program's changes while it is open and returns the chosen item's id
exactly as Windows' menu would, so every item still does what it does now. On any error Windows' own menu is shown.
Layouts are saved under a name; the settings app shows the menu while a layout is edited, drawn by the same code, so
the preview is the result.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Item tree | Windows' menu read into a tree (names, paths, ids, states), a submenu read when opened, read again on a change while shown | 3.2; plan 00 6.3 |
| Window | Dexmenu's own window: lines of cards (side by side), dividers, keys, mouse, submenus next to their card, closing, the id handed back; one built-in look; empty submenus and empty cards with a menu left out | 3.6; 3.7; plan 00 6.3, 6.5 |
| Rules | cards with rules and cards with a menu; name, scope or path, match kinds, states, subitems following an item, the priority list, several found at the card's place, `also`, `consume`, `skipDuplicates`, hidden cards, the remaining card; submenus filled only when opened opened first for rules that look inside | 3.3; plan 00 6.5 |
| Layout editing | the cards view and the rules view (priority list, draggable); dragging cards and dividers (onto a card, beside, above or below), the remaining card; preview and editor tied; comments, hints | 3.5; plan 00 6.5; plan 05 6.3 |
| Layouts | saved under a name, JSON with comments, one menu per layout; which kinds use which layout: plan 05 | 3.4; 3.5; plan 05 |
| Submenus | `next` (beside the card), `under` (from the card's middle, over the lines below), `replace` (in place of the menu, "<<" back, on a click only); on hover or only on a click; set for every menu (main window, settings.json `menu`) or per card (`submenus`); the same in the preview | 3.4; 3.7 |
| Edit menu | "Edit menu..." as a card a layout places (`"own": "editMenu"`; "+ Dexmenu" in the editor): the menu closes, the last right-click is written, the settings app starts on the layout in use (its editor, the preview on this right-click) | 3.6 |
| Windows' menu | Shift held while right-clicking shows Windows' own menu (in Explorer its extended menu); "Windows' menu" as a card a layout places (`"own": "windowsMenu"`) closes Dexmenu's and shows Windows' at the same place; a layout that cannot be read: Windows' menu | 3.11 |
| Global settings | in the main window, settings.json `menu`: how submenus open, only on a click, the marks (a submenu's: the chevron unless set; an item's: none unless set), a rule's default states (a change reads every layout again), the width per level (the menu, a first submenu, deeper: min and max). The most used row: with the use counts. Animation and the themes: plan 03 | 3.4 |
| Use counts | every choice counted per item (its path in Windows' menu and its text) and kind of right-click, in usage.json, after the menu closed; `{ "mostUsed": true }` in a layout: the items chosen most, side by side, most first, also items in submenus, disabled ones left out; how many: the main window (1 - 10, 3 when unset); "+ Most used" in the editor, moved and deleted as a divider; in the editor every card's count in the cards view's gutter (a card with a menu: the sum of what is in it); none on the preview | 3.9 |
| Text size | Ctrl+scroll in the open menu: its text, cards and widths 10% larger or smaller (60% - 250%), its submenus closed, drawn again where it is; kept in settings.json (menu.textSize) once the menu closed; also set in the main window; the preview follows it | 3.4 |
| Icons | left of the text, the first there is: the layout card's `icon` (a glyph of Segoe Fluent Icons by its code point, `E8C8`, or an icon in a file, `path,index`; on a card with a menu and on the items a card places, not the remaining card's), the item's own bitmap in Windows' menu, else none (an empty slot: a letter there would look like a key to type); set in the editor's card panel | 3.8 |
| Shipped layouts | "Default A", "Default C" (by task) and "Default D" (minimal, without its search box yet), each written once into the layouts folder (settings.json `shipped`); every other kind on Default A at a first start; each ends with a note, "Edit menu..." and "Windows' menu" | 3.10 |
| Icons in the preview | the items' own bitmaps kept as PNG files in the seen folder's `icons` (by a hash of the item's path and text), by every right-click and by the settings app's real menu of a folder; the preview draws them; an icon this process kept with the same pixels is not encoded again | 3.8 |
| Icon probe | opt-in (HKCU Software Dexmenu, ProbeIcons = 1): at a right-click every owner-drawn item without a bitmap drawn by its owner window into Dexmenu's memory on black and on white, the icon cut from its left part; the drawings written to %LOCALAPPDATA%\Dexmenu\probe, the icon kept for the preview, the result logged; not yet run in Explorer | 3.8 |
| Access keys and shortcuts | the `&` letter underlined in an item's own title, its key picks the item; the shortcut after a tab in Windows' text shown dim at the right, the card wide enough for it | 3.6 |
| Note card | `{ "note": "<text>", "align": ... }` (left, with the items' text, centered, right): no button (no hover, skipped by keys and clicks), its text wrapped in the dim colour, as high as its text; "+ Note" in the editor, its text edited in the panel | 3.3 |
| Preview | the same window drawn by the DLL inside the editor, from the seen items or Windows' live menu of a right-click in a chosen folder, and the layout being edited; items not always there striped | 3.8; plan 00 6.4, 6.5 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Explorer's own icons | Explorer's owner-drawn items' icons read at a right-click and used in the menu and the preview | the probe's result | 3.8 |
| Default B | the shipped layout "Default B" (cards per program, their items as buttons in the card) | items as buttons in a card; the search box | 3.10 |
| Search box in Default D | Default D's search box | the search box (3.6) | 3.10 |
| Tests | 3.12: the rules, placement and editor parts tested (plan 00 6.5); the rest with their parts | -- | 3.12 |

## 3. Details

### 3.1 What stays from plan 01

- The DLL in every process that builds a right-click menu, the noted `HMENU`, the hook on `TrackPopupMenu(Ex)`.
- Changes while shown: Explorer sets Explorer commands' states after the show (plan 01 3.1, 3.4). Here they go to the
  item tree, and the window redraws what changed (an item enabled, an item gone, a card left empty).
- The choice: the id of Windows' item, returned from the show call (`TPM_RETURNCMD`) or posted as `WM_COMMAND`, as
  Windows' menu would. The program runs it as always.
- Windows' items stay in Windows' menu while Dexmenu's window is open; nothing is moved. The window only reads them
  and hands back an id.

### 3.2 The item tree

- Each item of Windows' menu: its text, its name (text without `&` and accelerator), its path (the submenus it sits
  in: `7-Zip > Add to archive...`), its id, state (enabled, disabled, checked, default), whether it has a submenu,
  its place in Windows' order, its icon if it can be had (3.8).
- What is not there: the program or extension that added an item. Windows' menu carries only texts, ids and handles.
  Whether the verb (as the test host reads with `GetCommandString`, `LexPen.Edit`) can be had from inside the DLL:
  [not yet checked]. If it can, rules can match on it (3.3); it is far steadier than the text.
- Submenus that an extension fills only when opened have no items until then (3.7). Rules that look inside them can
  only see them after they were filled once; the seen items (plan 01 3.6) remember what was in them.

### 3.3 Rules: finding items

Cards first: the layout defines cards, and each card has rules that fill it from Windows' menu. Where a card stands
in the layout is where its items show.

- **Two kinds of card:**
  - a **card with rules**: filled from Windows' menu; an action when its rules find one item, a submenu of them when
    they find more;
  - a **card with a menu**: has no rules; its submenu holds cards of its own, and the rules are on those. Made as
    such, it starts with one card in its submenu.

- **A rule:** a `name` to match (the item's text without `&`), and where to look: either a `scope` or a `path`,
  never both.
  - `scope`: `top` (Windows' top level) or `anywhere` (every level).
  - `path`: (part of) the submenu path the item sits in, matched as the name is (`7-Zip`, or `startsWith: "Tortoise"`).
  - Neither: `top`.
  - `verb` instead of `name`, if 3.2 allows it.
- **Match kinds:** `equals`, `contains`, `startsWith`, `endsWith`, `wildcard` (`*`, `?`), `regex`. Case insensitive by
  default; `caseSensitive: true` per rule. `any` takes a list of patterns (one of them).
- **States:** a set, `["enabled"]`, `["disabled"]` or both; an item whose state is in the set is taken. The default
  set is in the global settings (3.4). An item left out because it is disabled can be taken once Explorer enables it
  (plan 01 3.1).
- **A found item takes its subitems:** an item with a submenu that a rule finds goes to that card as a whole, its
  subitems following it as its submenu, except subitems already taken by a rule earlier in the order below.
- **The order of the rules:** because of that, who gets an item cannot follow the cards' places in the layout. A
  layout (per kind of right-click) has one priority list of all its rules, independent of where their cards stand;
  the editor shows it and the user orders it by dragging. Rules take items in that order: an item goes to the first
  rule that finds it and is not found again by a later one. So a rule for a deeper item (`7-Zip > Add to archive...`)
  placed before the rule for its parent (`7-Zip`) takes that item first; the parent, taken later, keeps the rest of
  its submenu. The other way round, the parent takes all its subitems and the later rule finds none of them. The
  remaining card's rule is always last and is not in the list. A new rule goes at the end of the list, before the
  remaining card's.
- **Also:** a rule with `also: true` takes items even when an earlier rule has taken them, and shows them in its card
  as well (a favourite in the icon row that also stays in its group); both hand back the same id.
- **Consume:** a rule takes what it finds (`consume`, on by default). With `consume: false` it shows what it found
  without taking it: later rules and the remaining card can show the same item too, each copy handing back the
  same id. `also` is the same seen from the later rule's side.
- **A card places what it found where it stands:** as the remaining card does, each found item a card of its own on
  its own line at the card's place, in the order found: one item, several, or none (then nothing shows). The card's
  title is the item's when it found one. So a card with a menu holds an unknown number of found items beside cards
  of its own (a menu "Open..." with a card finding the items of Windows' "Open with" and a card of the user's own).
- **Note card:** `{ "note": "<text>" }` (or `"note": ""` for an empty space): a card that is no button. It finds
  nothing and runs nothing: hover does not light it, a click and the keys pass it by (the arrows skip it), and it
  has no rules or menu. Its text, when it has one, may hold several lines (a memo) and wraps to the card's width;
  the card is as high as its text, or one line's height when empty. Its text is placed by `"align"`: `left` (the
  card's edge; the default), `text` (in line with the items' text, past the room for a check mark or an icon),
  `center` or `right`. It stands in a line like any card (beside
  other cards too) and is never in the priority list. Its look (text colour, background) comes with the themes
  (plan 03); until then the dim text colour. In the editor: "+ Note" beside "+ Card" and "+ Divider", dragged or
  clicked, its text edited in the panel as a text box. Used for the warning of a layout the DLL cannot use (plan 05
  3.1.1).
- **Hidden:** a card with `hidden: true` shows nothing, while its rules (and those of the cards in its menu) still
  take their items: a way to leave items out of the menu, the remaining card included. The editor draws a hidden
  card with diagonal stripes. The remaining card cannot be hidden.
- **Templates for items placed in a submenu:** items that Dexmenu puts in a submenu itself (the subitems following a
  found item) are cards that are not in the layout; they get their look from
  a template card. A layout has one template card for them; it has no rules, only a look (plan 03 3.6). A card can
  overrule it with a submenu template card of its own, used for every item placed in its submenu, deeper levels
  included, unless a card further down has its own. The remaining card's items take the remaining card's own look
  (below). A rule written for one item ("Open") that
  also finds "Open with" and "Open in new window" therefore still works. Found none: the card is not shown (the
  preview shows it striped, 3.8).
- **Items no card took: the remaining card.** Every layout has exactly one card with the rule `remaining`; it cannot
  be removed. It takes every top-level item of Windows' menu no other card's rules took, and is evaluated after all
  other cards, wherever it stands.
  - Its place is where those items go: each becomes a card of its own at that place, in Windows' order, in the
    remaining card's style. At the root: they are at the root of the new menu. Inside a card with a menu: they are
    in that submenu.
  - So a layout with only the remaining card at the root shows Windows' menu as it is, as cards: the starting point
    of every layout.
  - An item with a submenu goes as a whole, as with any rule: its subitems follow it, except those another rule
    took (scope `anywhere`, or a path); the submenu shows what is left.
  - By default it is at the root; the user can move it into any submenu and back, so the user decides where the rest
    goes. Items not seen before (plan 01 3.6) can be marked new.
- **An item taken out of a Windows submenu** shows in its card; the submenu shows what is left.
- **Titles:** a card shows the item's own text unless the layout gives a title, or rewrites it with a regex replace
  (`Kopieren naar... "SynologyDrive"` shown as `SynologyDrive`).

### 3.4 Global settings

The settings app shows them on a tab of their own; they are in `%APPDATA%\Dexmenu\settings.json`.

- **Opening submenus:** `next` (next to the item, as a classic menu), `under` (below the item, starting at its
  middle, over the lines below it) or `replace` (the submenu takes the place of the menu; only on a click; a `<<`
  item at its top goes back, as Esc does). A card or item can overrule it.
- **Only on click:** submenus open only on a click, never on hover. `replace` is always on click.
- **Marks:** the character shown on an action and the one shown on an item or card with a submenu (for example none
  and `>`), chosen by the user.
- **Menu width per level:** the width of the top level, of a first submenu, of a submenu in that, and so on, and a
  maximum width per level. The cards on one line share that width; a line whose cards do not fit makes the level
  wider, up to the maximum, before its cards wrap (plan 03 3.5).
- **States taken:** the default set of a rule, enabled, disabled or both (3.3).
- **Most used:** how many items the row shows (3.9); a layout has the row where it puts `{ "mostUsed": true }`.
- **Text size:** Ctrl+scroll while the menu is open makes its text larger or smaller, the cards and levels with it;
  the size is kept for every next menu.
- **The active layout:** which named layout is used (3.5).
- **Light and dark:** follow Windows' mode, or fixed to light or to dark; a theme for light and one for dark
  (`themeLight`, `themeDark`; plan 03 3.3).
- **Animation:** for submenus and the `replace` change: none, slide (with a direction), fade or crossfade, and the
  time it takes (plan 03 3.9).

### 3.5 Layouts

- A layout is a file `%APPDATA%\Dexmenu\layouts\<name>.json`, saved under a name. The settings app opens one, saves
  it, saves it under a new name, and makes one the active layout. The user can start from one of the shipped layouts
  (3.10), change it, save it as their own, and switch between layouts.
- JSON with comments: `//` to the end of the line is a comment, except inside a string, so a regex or a path holding
  `//` is kept. Read again when the file changes. An invalid file: the error in the log, Windows' own menu shown.
- Per kind of right-click: one file, several items, a folder, a folder's empty part, a drive; by extension where
  wanted (`.zip`). A kind without a layout of its own uses the layout's default.
- A layout is a list of lines, top to bottom. A line holds one card alone (it looks and feels like a menu item), or
  several cards next to each other that share the level's width (equally, or by a weight per card). The other kinds
  take a line of their own:
  - `card`: a title; an optional extra text; an optional icon; either its rules or its menu (3.3); optionally its
    own way of opening a submenu; its own look where wanted (plan 03 3.6: where the extra text goes, height, minimum
    width, background, colours).
  - `template`: the layout's template card for items placed in a submenu (3.3): no rules, only a look; exactly one.
    A card's own submenu template is a `template` inside that card (`submenuTemplate`).
  - `divider`: between lines, with an optional label; its look (label alignment, height, background, colours) is
    plan 03 3.8.
    Shown only where it divides something: any divider is left out at the bottom of a level; one without a label
    also at the top and right after another divider or separator; one with a label also when another with a label
    follows it at once. This is decided on what is shown, after cards that found nothing are gone (the menu and the preview).
  - `row`: items as icons in one line, the text as tooltip (Windows 11's Cut / Copy / Paste row).
  - `mostUsed`: the row of the items chosen most (3.9).
  - `search`: a box that filters all items as you type (3.6).
- A card with a menu (3.3) holds lines of cards and dividers again, one level down, with that level's width.
- **Editing in the settings app** (plan 01 3.7), by dragging cards:
  - a card dragged onto another card makes that card a card with a menu, holding both. When the target had rules,
    they go to a new card, the first in the new submenu, so nothing is lost; the dragged card follows it. The user
    then orders the cards in the submenu as wanted;
  - a card dragged onto a line or between lines moves there, at that level;
  - deleting the last card of a submenu makes its parent a card with rules again: the deleted card's rules go to
    the parent, so they are not lost (the reverse of dropping a card onto a card). Dividers in that submenu go with
    it;
  - dragging the last card out of a submenu: it keeps its rules, and the parent becomes a card with rules that has
    none. It stays in the layout, finds nothing and is not shown in the menu;
  - the remaining card is moved as any other, never deleted;
  - the editor's left pane shows two views of one layout:
    - **the cards:** the layout's cards as a tree of lines and submenus, as they stand; clicking a card opens it: its
      title, extra text, kind (rules or a menu), its rules, its look, its own submenu template if it has one. The
      layout's template card is shown apart, edited as a card without rules. Each rule on a card shows its number in the
      priority list, so the order is visible throughout the cards;
    - **the rules:** the priority list (3.3): one row per rule, in order, with its number, the card it belongs to
      and the rule itself; the order changed by dragging a row. The remaining card's rule shown last, fixed.
    Selecting a card or a rule in one view selects it in the other;
  - the preview and the editor are tied: clicking or hovering over an item in the preview selects the layout card
    that placed it, and the rule that found it (the DLL reports which card and rule placed each item); selecting a
    card in the editor marks the items it placed in the preview;
  - cards that can never show anything are marked in the editor and the preview with a red outline (plan 03 3.10):
    a card with no rules, and a card with a rule that is invalid (a bad regex, a scope and a path both given). The
    layout is still saved and used; such a card is left out of the menu.
  - a card made as a card with a menu starts with one empty card in its submenu, ready for rules.
- A card or line without items is not shown (also when late states empty it).
- An example, in the shape it may take:

  ```json
  // Layout "Classic plus"
  { "default": [
      { "row": "actions", "rules": [ { "name": { "any": ["Cut", "Copy", "Paste", "Rename", "Delete"] } } ] },
      { "mostUsed": true },
      { "line": [ { "card": "Open", "rules": [ { "name": { "startsWith": "Open" } } ] } ] },
      { "divider": "Programs", "align": "left" },
      { "line": [
          { "card": "LexPen", "icon": "lexpen.ico", "rules": [ { "verb": { "startsWith": "LexPen." } } ] },
          { "card": "Tools", "submenu": "replace", "menu": [          // a card with a menu: no rules of its own
              { "line": [ { "card": "Archive", "extra": "7-Zip", "rules": [
                  { "name": { "wildcard": "*" }, "path": { "equals": "7-Zip" }, "states": ["enabled"] } ] } ] },
              { "line": [ { "card": "Git", "rules": [
                  { "name": { "wildcard": "*" }, "path": { "startsWith": "Tortoise" } } ] } ] }
          ] } ] },
      { "line": [ { "card": "More", "menu": [                        // the rest in a submenu "More":
          { "line": [ { "card": "Remaining", "rules": [ "remaining" ] } ] } ] } ] }   // the remaining card, always one
  ] }
  ```

### 3.6 Interaction

- **Choosing:** a click, or Enter on the focused item: the id handed back, the window closed.
- **Keys:** arrows move through the layout in two directions (across a line of cards, down through the lines); Tab to
  the next place; the `&` letters of Windows' texts kept as keys (the letter underlined in the
  title when the title is the item's own text; pressing it picks the item, or moves between items with the same
  letter); an item's shortcut (the text after a tab in Windows' text, "Ctrl+X") shown dim at the right of its card; Esc closes an open submenu,
  goes back from a `replace` submenu, or closes the menu.
- **Typing searches:** any letter typed with the window open goes into the search box (shown when typing starts, if
  the layout has none); it filters every item of every place, Windows' submenus included once filled, with the same
  match kinds as the rules (contains by default, a leading `/` for a regex). Enter runs the first hit.
- **Disabled items:** shown greyed, or left out, per rule (3.3).
- **Late changes:** an item that Explorer enables changes in place; a card Explorer removes goes at once and its
  line closes up. (In the preview such a card is striped instead, 3.8.)
- **No editing from the menu:** the menu does not pin, move, hide or rename items; removing an item while a menu is
  being used is too easily done by mistake. Changing the layout is the settings app's.
- **Edit menu...:** Dexmenu's own item, a card the layout places where it wants (`{ "card": "Edit menu...", "own":
  "editMenu" }`; a layout without it does not show it) that closes the menu and opens the settings app's layout
  editor on this menu as it was: this kind of right-click, the items it had (the DLL writes
  them to a file and starts the settings app with it), the layout in use. The user places what they just saw.
- **Closing:** a click outside, the window losing focus, Esc on the top level, Alt: closed without a choice, as
  Windows' menu.

### 3.7 Submenus

- Three ways, from the global settings or a card's own (3.4):
  - `next`: a panel next to the item, as a classic menu.
  - `under`: below the item, starting at the item's middle, lying over the lines below it.
  - `replace`: the submenu takes the place of the menu, on a click only, with `<<` at the top; `<<` and Esc go back a
    level. The path can show at the top.
- On hover or on click: on hover unless "only on click" is set; `replace` always on click.
- A Windows submenu filled only when opened (Send to, Open with, 7-Zip's): Dexmenu sends `WM_INITMENUPOPUP` for it to
  the owner window, as Windows' menu does when it opens, and reads it then. Whether every common extension fills it
  that way without Windows' menu window being there: [not yet checked], in the spike.
- A card with a menu opens the same way; a click on the card of an open submenu closes that submenu.

### 3.8 Drawing, icons and the preview

- How the menu looks (themes, the window, lines and cards, their states, submenu panels) is plan 03's
  (`03-PLAN-menu-look.md`). Below: where it is drawn, icons, and the preview.
- In the program's process (Explorer first), so no .NET, WebView2 or other runtime (plan 01 3.8): a native popup
  window in the Delphi DLL (plan 01 3.2), drawn with Direct2D and DirectWrite, per-monitor DPI, light and dark, the
  accent colour. A right-click needs no other process.
- A window of Dexmenu's own replaces the show call: the hook runs its own message loop until a choice or close, so
  the program waits as it does for Windows' menu.
- Icons, in a slot left of the text, the first one there is:
  - the layout's own icon for the card, `"icon"`: a glyph of Segoe Fluent Icons by its code point in hex (`"E8C8"`;
    Segoe MDL2 Assets where Fluent is missing) or an icon in a file (`"%SystemRoot%\\System32\\shell32.dll,4"` in the JSON); on a
    card with a menu and on every item a card places, not on the remaining card's items;
  - the item's own bitmap where Windows' menu has one (most extensions' items outside Explorer);
  - in Explorer's full menu, where Explorer draws every item itself (plan 01 6.2) and there is no bitmap to read:
    Explorer asked to draw the item into Dexmenu's memory (`WM_MEASUREITEM` / `WM_DRAWITEM` to the owner window) and
    the icon cut out of it: [not yet checked] whether it works;
  - otherwise none: the slot stays empty (a letter there would look like a key to type).
  A checked item shows its check mark in the slot instead.
- The preview draws the items' own icons too: every right-click, and the settings app's real menu of a folder, keep
  the items' bitmaps as PNG files in the seen folder's `icons`, named by a hash of the item's path and text (its key,
  as the use counts', 3.9); the preview reads them. Items Explorer draws itself have no bitmap to keep: they show
  no icon until Explorer's own icons are read (below).
- One drawing engine for the menu and its preview. The settings app (plan 01 3.7, .NET 10 and WebView2) loads the same
  DLL and gives it a window of its own next to the editor; the DLL draws the menu there from the seen items (plan 01
  3.6) and the layout being edited, and draws it again on every change. The preview is the real window, live: hover,
  keys, typing to search and submenus work as at a right-click; choosing an item does nothing, there being no program
  to run it.
- In the preview, an item that is not always there (seen, but hidden for some selections, or removed late by
  Explorer) and a card that would be empty are shown as unavailable: diagonal stripes, so the layout can be made for
  them too. No use counts on the preview: they would change how it lays out (3.9).
- What the preview is a right-click of: chosen above it, the kind of right-click and a base folder with the item(s)
  in it (a file or a folder picked from the folder's, several checked, nothing more for the folder's empty part or
  its drive). With a folder the settings app asks Windows for the real menu of that right-click there, as Explorer
  does, every submenu opened once, so a Git folder shows TortoiseGit's items, an SVN folder TortoiseSVN's, a folder
  without source control neither; the seen items' other items show too, striped. Without a folder: the seen items.
  The folder's empty part is asked from a folder view made for the folder, as Explorer's own view gives it: its
  View, Sort by, Group by, Refresh, Paste and Customise this folder with the extensions' items.
- In the settings app the DLL sets no hook: it only draws. Dexmenu's handler runs there too while the real menu is
  built (maybe the registered copy of the DLL, not the app's own); the app marks its process (`DEXMENU_EDITOR`), so
  it notes nothing; Explorer started again from the app does not get the mark. The DLL is 64-bit, so the settings app runs 64-bit.
- A preview drawn by the settings app itself (in HTML) is not made: it would drift from the real menu.
- Screen readers: the window as UI Automation elements: [not yet checked] what that takes.

### 3.9 Use counts and the most used row

- Every choice counted per item (its path and the kind of right-click), in `%APPDATA%\Dexmenu\usage.json`, written by
  the DLL after the menu has closed, so the choice is not slowed.
- `mostUsed` in a layout: a row of the items chosen most, for this kind of right-click, as many as the global setting
  says; only items present in this menu.
- An item may show both in the most used row and at its own place: the row is a shortcut.
- Items inside a submenu count too (their key is their path and text, `7-Zip > Add to archive...`); the submenus
  that fill only when opened are opened early when the row may need them.
- While editing: every card's count in the gutter beside it in the cards view, so the user sees what matters most
  and places it: the stored counts of the items the card gets in the preview, each with the items in its submenu; the
  remaining card's of the remaining items; a card with a menu the sum of the cards in it. Not on the preview itself:
  a mark there would change how it lays out, and the preview is to show the menu as it is.

### 3.10 Suggested layouts

Shipped as named layouts, "Default A", "Default B", ...: each written into the layouts folder once (settings.json
`shipped` remembers which), so one the user changed or deleted is left as it is. A new user's every other kind of
right-click uses Default A; the user can pick another, change it and save it as their own (3.5). Their rules match
Windows' texts, so they fit an English Windows until a rule on the verb is possible.

- **A. Default A (the default).** Cut, Copy, Paste, Rename and Delete side by side, each with its icon; Properties
  under them; a divider; Open and Open with on one line; a divider; the rest (the remaining card, not in a submenu);
  a divider; the note "Dexmenu - default menu", "Edit menu..." and "Windows' menu" on one line.

  ```
  [Cut] [Copy] [Paste] [Rename] [Delete]
  [Properties]
  ----------------------------------------
  [Open]              [Open with        >]
  ----------------------------------------
  (every other item, each a card)
  ----------------------------------------
  Dexmenu - default menu  [Edit menu...] [Windows' menu]
  ```

- **B. Default B, cards per program** (not yet shipped: it needs items as buttons in a card). Each program's card shows its items as buttons in it (not a submenu); the icon row on
  top; a search box.

  ```
  [search............................]
  [Cut] [Copy] [Paste] [Rename] [Delete]
  +----------------+ +----------------+
  | LexPen         | | 7-Zip          |
  | Edit  View     | | Add  Zip  7z   |
  | Compare left   | | Extract here   |
  +----------------+ +----------------+
  ```

- **C. Default C, by task.** Places named after what is done, filled by rules across programs: Open (Open, Open with, Edit in
  ...), Share and send (Share, Send to, Copy as path), Archive (`regex: zip|7z|archive|extract`), Version control
  (Git, SVN), File (Rename, Delete, Properties), More. Best when the rules fit the programs installed, which Dexmenu
  cannot know in advance; hence not the default.
- **D. Default D, minimal.** A search box (not yet: it comes with the search box, 3.6), the most used row, and "All
  items" (Windows' menu in Windows' order) one click away.

### 3.11 Safety

- As plan 01 3.8: any error before the window shows, or a layout that cannot be read: Windows' own menu shown
  instead; the error in the log.
- Shift held while right-clicking shows Windows' own menu (in Explorer that is its extended menu, with more items);
  "Windows' menu", Dexmenu's own item as a card the layout places (`"own": "windowsMenu"`), closes Dexmenu's menu
  and shows Windows' at the same place.
- Nothing slow on the show call: settings and layout read once per change; icons cached per process.

### 3.12 Tests

- Rules on a tree made for the test, and on trees read by the test host (plan 01 6.1): every match kind, case,
  the states set, scope or path (both given: an error), a found item taking its subitems, the priority order (a
  deeper item's rule before its parent's and after it, with the parent's submenu showing what is left), `also`,
  `consume`, one and several found at the card's place,
  none found, the remaining card wherever it stands (root, a submenu), a card with a menu holding cards with rules,
  titles.
- Templates: items a card found and its found items' subitems drawn with the layout's template; a card's own
  submenu template used instead, deeper levels included until a card with its own; the remaining card's items in
  its own look.
- Editor views: a rule dragged in the rules view changes the order, its number on its card, and the preview; an
  item clicked or hovered in the preview selects the card and rule that placed it; a card selected marks its items
  in the preview.
- Editing: a card dropped onto a card with rules makes a card with a menu whose first card has those rules; onto a
  card with a menu, it joins it; the last card of a submenu deleted, its parent a card with rules with its rules;
  the last card dragged out, its parent a card without rules, outlined red; an invalid rule outlined red; the
  remaining card moved but never deleted; a layout without exactly one remaining
  card reported as invalid.
- Settings and layouts: valid and invalid files, comments (also `//` inside a string kept), save under a name, switch
  the active layout, the fallback.
- The window in the test host: the cards shown per line for a given tree and layout, widths per level; keys and
  typing; each way of opening a submenu, on hover and on click, `<<` and Esc back; a choice hands back the right id
  (the host clicks or presses Enter through the window, not through Windows' menu).
- Late changes (`--late` of plan 01): an item enabled and one removed while the window is open, the window updated
  (the removed card gone, its line closed up), the right id handed back after.
- Edit menu...: the settings app started with this menu's items and kind of right-click.
- Use counts: a choice counted once, the most used row in order of counts.
- The preview: the same tree and layout drawn in the test host's menu window and in the preview window give the same
  picture (both captured and compared); a layout edit redraws the preview; striped items; a choice in the preview
  runs nothing.
- By hand in Explorer, an Open dialog and Foldex: each shipped layout, lazy submenus (Send to, Open with), icons, dark
  and light, a second monitor with another DPI.

## 4. Open questions

None.
