# Plan 02: Dexmenu's own menu: drawn by Dexmenu, cards and rows, every item found by rules

Status: not started; see Status.

- 2026-11-21: draft.

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

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Item tree | Windows' menu read into a tree with names and paths, kept live while shown | plan 01 Delphi DLL | 3.1; 3.2 |
| Rules | cards with rules and cards with a menu; name, scope or path, match kinds, states, who gets an item, several found, the remaining card | Item tree | 3.3 |
| Layout editing | dragging cards: onto a card makes a menu (its rules kept in a first card), moving, the remaining card | Rules; plan 01 Settings app | 3.5 |
| Settings and layouts | global settings; layouts per kind of right-click, saved under a name; JSON with comments | Rules | 3.4; 3.5 |
| Window | Dexmenu's own window, drawn by the Delphi DLL: lines of cards, keys, mouse, closing, the id handed back | Settings and layouts | 3.6; 3.7; 3.8 |
| Submenus | next to, half under, or in place of the menu; on hover or on click; filled when opened (Send to) | Window | 3.7 |
| Edit menu | "Edit menu..." in the menu: the settings app's layout editor opened on this menu as it is | Window; plan 01 Settings app | 3.6 |
| Icons | the layout's, the item's own, cut from Explorer's drawing, or the first letter | Window | 3.8 |
| Preview | the same window drawn by the DLL inside the settings app, from the seen items and the layout being edited | Window; plan 01 Settings app | 3.8 |
| Use counts | every choice counted per item; the most used row; counts shown while editing | Window | 3.9 |
| Default layouts | the suggested layouts shipped, A the default | Settings and layouts | 3.10 |
| Safety | fallback to Windows' own menu; a key for Windows' menu | Window | 3.11 |
| Tests | 3.12 | -- | 3.12 |

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
- **Who gets an item:** a card's results are every item its rules find. When the rules of two cards find the same
  item, the card first in the layout (top to bottom, left to right) gets it; a rule with `also: true` shows it in its
  card as well (a favourite in the icon row that also stays in its group); both hand back the same id.
- **One expected, several found:** a card is an action when its rules find one item, and a card with a submenu
  holding all of them when they find more, without a change to the layout. A rule written for one item ("Open") that
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
  - An item with a submenu goes as a whole: its subitems follow it, as its submenu. A subitem another card's rule
    took (scope `anywhere`, or a path) is in that card instead; the submenu shows what is left.
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
- **Most used:** the row on or off and how many items it shows (3.9).
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
  - `divider`: between lines, with an optional label; its look (label alignment, height, background, colours) is
    plan 03 3.8.
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
  the next place; the `&` letters of Windows' texts kept as keys where they do not clash; Esc closes an open submenu,
  goes back from a `replace` submenu, or closes the menu.
- **Typing searches:** any letter typed with the window open goes into the search box (shown when typing starts, if
  the layout has none); it filters every item of every place, Windows' submenus included once filled, with the same
  match kinds as the rules (contains by default, a leading `/` for a regex). Enter runs the first hit.
- **Disabled items:** shown greyed, or left out, per rule (3.3).
- **Late changes:** an item that Explorer enables changes in place; a card Explorer removes goes at once and its
  line closes up. (In the preview such a card is striped instead, 3.8.)
- **No editing from the menu:** the menu does not pin, move, hide or rename items; removing an item while a menu is
  being used is too easily done by mistake. Changing the layout is the settings app's.
- **Edit menu...:** an item at the end of the menu (on or off in the global settings) that closes the menu and opens
  the settings app's layout editor on this menu as it was: this kind of right-click, the items it had (the DLL writes
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
- A card of the user's own with several items opens the same way.

### 3.8 Drawing, icons and the preview

- How the menu looks (themes, the window, lines and cards, their states, submenu panels) is plan 03's
  (`03-PLAN-menu-look.md`). Below: where it is drawn, icons, and the preview.
- In the program's process (Explorer first), so no .NET, WebView2 or other runtime (plan 01 3.8): a native popup
  window in the Delphi DLL (plan 01 3.2), drawn with Direct2D and DirectWrite, per-monitor DPI, light and dark, the
  accent colour. A right-click needs no other process.
- A window of Dexmenu's own replaces the show call: the hook runs its own message loop until a choice or close, so
  the program waits as it does for Windows' menu.
- Icons, the first one there is:
  - the layout's own icon for the card (a file and index, or a glyph of Segoe Fluent Icons);
  - the item's own bitmap where Windows' menu has one (most extensions' items outside Explorer);
  - in Explorer's full menu, where Explorer draws every item itself (plan 01 6.2) and there is no bitmap to read:
    Explorer asked to draw the item into Dexmenu's memory (`WM_MEASUREITEM` / `WM_DRAWITEM` to the owner window) and
    the icon cut out of it: [not yet checked] whether it works;
  - otherwise the first letter.
- One drawing engine for the menu and its preview. The settings app (plan 01 3.7, .NET 10 and WebView2) loads the same
  DLL and gives it a window of its own next to the editor; the DLL draws the menu there from the seen items (plan 01
  3.6) and the layout being edited, and draws it again on every change. The preview is the real window, live: hover,
  keys, typing to search and submenus work as at a right-click; choosing an item does nothing, there being no program
  to run it.
- In the preview, an item that is not always there (seen, but hidden for some selections, or removed late by
  Explorer) and a card that would be empty are shown as unavailable: diagonal stripes, so the layout can be made for
  them too. The use count of every item can be shown on it (3.9).
- In the settings app the DLL sets no hook: it only draws. The DLL is 64-bit, so the settings app runs 64-bit.
- A preview drawn by the settings app itself (in HTML) is not made: it would drift from the real menu.
- Screen readers: the window as UI Automation elements: [not yet checked] what that takes.

### 3.9 Use counts and the most used row

- Every choice counted per item (its path and the kind of right-click), in `%APPDATA%\Dexmenu\usage.json`, written by
  the DLL after the menu has closed, so the choice is not slowed.
- `mostUsed` in a layout: a row of the items chosen most, for this kind of right-click, as many as the global setting
  says; only items present in this menu.
- While editing: the count shown on every item in the preview and in the editor's item list, so the user sees what
  matters most and places it.

### 3.10 Suggested layouts

Shipped as named layouts; A is active for a new user, who can pick another, change it and save it as their own (3.5).

- **A. Classic plus (default).** An icon row on top (Cut, Copy, Paste, Rename, Delete, Properties); the most used row;
  Open and Open with; a divider "Programs"; one card per program with a submenu of its items (LexPen, 7-Zip,
  TortoiseGit); a "More" card with a menu holding the remaining card, so the rest is in that submenu.

  ```
  [Cut] [Copy] [Paste] [Rename] [Delete] [Properties]
  [most used 1] [most used 2] [most used 3]
  Open
  Open with            >
  +-----------+ +-----------+ +-----------+
  | LexPen  > | | 7-Zip   > | | Git     > |
  +-----------+ +-----------+ +-----------+
  More                 >
  ```

- **B. Cards per program.** Each program's card shows its items as buttons in it (not a submenu); the icon row on
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

- **C. By task.** Places named after what is done, filled by rules across programs: Open (Open, Open with, Edit in
  ...), Share and send (Share, Send to, Copy as path), Archive (`regex: zip|7z|archive|extract`), Version control
  (Git, SVN), File (Rename, Delete, Properties), More. Best when the rules fit the programs installed, which Dexmenu
  cannot know in advance; hence not the default.
- **D. Minimal.** A search box, the most used row, and "All items" (Windows' menu in Windows' order) one click away.

### 3.11 Safety

- As plan 01 3.8: any error before the window shows, or a layout that cannot be read: Windows' own menu shown
  instead; the error in the log.
- A key held while right-clicking shows Windows' own menu; "Windows' menu" as the last item of every layout.
- Nothing slow on the show call: settings and layout read once per change; icons cached per process.

### 3.12 Tests

- Rules on a tree made for the test, and on trees read by the test host (plan 01 6.1): every match kind, case,
  the states set, scope or path (both given: an error), who gets an item and `also`, one expected and several found,
  none found, the remaining card wherever it stands (root, a submenu), a card with a menu holding cards with rules,
  titles.
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

1. **Ordinary cards with several items.** The remaining card places its items at its own place, each as a card in
   its style (3.3). Is that so for every card with rules too (a card "Open" finding "Open" and "Open with" puts both
   there as cards, its title not shown), or does an ordinary card keep the rule written now: one item an action, more
   a submenu under the card's title?
