# Plan 02: Dexmenu's own menu: drawn by Dexmenu, cards and rows, every item found by rules

Status: not started; see Status.

- 2026-11-21: draft.

Builds on plan 01 (`01-PLAN-dexmenu.md`): its DLL, the hook on the show call, following the changes a program makes
while the menu is shown, and handing back the chosen id. Plan 01's layout file moves here.

## 1. What this is about

Plan 01 shows the arranged items as a normal Windows menu. A Windows menu can only do lines of text with an icon,
submenus, lines between them and columns. The user wants a menu of Dexmenu's own design: cards, several cards next to
each other, a row of icons as Windows 11's Cut / Copy / Paste row, a card that holds a submenu. The structure is
defined in a file. Windows' items are found by rules (exact, contains, starts with, regex; case insensitive), with
disabled items taken or left per rule, and every item no rule found still placed somewhere.

## 2. The solution, in brief

The DLL keeps catching the show call with Windows' items, as in plan 01, but instead of a Windows menu it opens a
window of its own, drawn by Dexmenu from a layout file. The layout is a tree of places (a list, a row of icons, a
grid of cards, a card that opens a submenu); each place takes Windows' items by rules on their text and path, its
state and where it sits, and a place for the rest catches every item no rule took. The window follows the
program's changes while it is open and returns the chosen item's id exactly as Windows' menu would, so every item
still does what it does now. On any error the arranged Windows menu of plan 01 is shown, or Windows' own.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Item tree | Windows' menu read into a tree with names and paths, kept live while shown | plan 01 spike | 3.1; 3.2 |
| Rules | finding items: match kinds, fields, states, scope, first match, the rest | Item tree | 3.3 |
| Layout file | places, cards, rows, lists, submenu cards, per kind of right-click; read and checked | Rules; Open question 2 | 3.4 |
| Window | Dexmenu's own window: drawing, keys, mouse, closing, the id handed back | Open question 1 | 3.5; 3.6 |
| Submenus | Windows' submenus opened from a card, filled when opened (Send to, Open with) | Window; Open question 3 | 3.6 |
| Icons | an icon per item, also for Explorer's self-drawn items | Window; Open question 4 | 3.7 |
| Default layouts | the suggested layouts shipped as examples | Layout file; Open question 6 | 3.8 |
| Safety | fallback to plan 01's arranged menu or Windows' own; a key for Windows' menu | Window | 3.9 |
| Tests | 3.10 | -- | 3.10 |

## 3. Details

### 3.1 What stays from plan 01

- The DLL in every process that builds a right-click menu, the noted `HMENU`, the hook on `TrackPopupMenu(Ex)`.
- Changes while shown: Explorer sets Explorer commands' states after the show (plan 01 3.1, 3.4). Plan 01 redirects
  those calls to the arranged menu; here they go to the item tree, and the window redraws what changed (an item
  enabled, an item gone, a place left empty).
- The choice: the id of Windows' item, returned from the show call (`TPM_RETURNCMD`) or posted as `WM_COMMAND`, as
  Windows' menu would. The program runs it as always.
- Windows' items stay in Windows' menu while Dexmenu's window is open; nothing is moved. The window only reads them
  and hands back an id. That is simpler than plan 01's move and put back.

### 3.2 The item tree

- Each item of Windows' menu: its text, its name (text without `&` and accelerator), its path (the submenus it sits
  in: `7-Zip > Add to archive...`), its id, state (enabled, disabled, checked, default), whether it has a submenu,
  its place in Windows' order, its icon if it can be had (3.7).
- What is not there: the program or extension that added an item. Windows' menu carries only texts, ids and handles.
  Whether the verb (as the test host reads with `GetCommandString`, `LexPen.Edit`) can be had from inside the DLL:
  [not yet checked]. If it can, rules can match on it (3.3); it is far steadier than the text.
- Submenus that an extension fills only when opened have no items until then (3.6). Rules that look inside them can
  only see them after they were filled once; the seen items (plan 01 3.6) remember what was in them.

### 3.3 Rules: finding items

A rule picks items of the tree. Each place in the layout has one or more rules.

- **Fields:** `name` (default), `path` (the full `A > B > C`), `verb` (if 3.2 allows it), `parent` (the submenu it
  sits in), `position` (first / last in Windows' menu, before or after another item).
- **Match kinds:** `equals`, `contains`, `startsWith`, `endsWith`, `wildcard` (`*`, `?`), `regex`. Case insensitive by
  default; `caseSensitive: true` per rule.
- **Combining:** `any` (one of), `all`, `not`; a rule can be a list of patterns.
- **States:** `disabled: include | exclude | only` per rule, with a default for the whole layout. `exclude` leaves a
  disabled item to the next rule or to the rest; with late states (plan 01 3.1) the item can move once Explorer
  enables it (3.6).
- **Scope:** `top` (Windows' top level only), `in: "7-Zip"` (inside one submenu), `anywhere` (every level). An item
  taken out of a Windows submenu is shown in its new place; the submenu shows what is left.
- **Who wins:** an item goes to the first place whose rule takes it, in the order of the layout file. A rule can say
  `also: true` to show an item in a second place as well (a favourite in the icon row that also stays in its group);
  both hand back the same id.
- **The rest:** one place marked `rest` takes every item no rule took, in Windows' order. Without one: a "More" card
  at the end. Items not seen before (plan 01 3.6) can be marked new there.
- **Hidden:** a place `hidden`; its items are not shown. Windows' menu (3.9) still has them.
- **Labels:** a place can show an item under another text (`label`), or rewrite it with a regex replace (`Kopieren
  naar... "SynologyDrive"` shown as `SynologyDrive`), and give it another icon.

### 3.4 The layout file

- One file of the user's, `%APPDATA%\Dexmenu\layout.json` (format: Open question 2), read again when it changes.
  An invalid file: the error in the log, plan 01's arranged menu or Windows' own shown (3.9).
- Per kind of right-click: one file, several items, a folder, a folder's empty part, a drive; by extension where
  wanted (`.zip`). A kind without a layout of its own uses the default one.
- A layout is a tree of places, top to bottom:
  - `list`: items as lines, as a classic menu.
  - `row`: items as icons in one line, text as tooltip (Windows 11's Cut / Copy / Paste row).
  - `cards`: items as cards in a grid, a number of columns or as many as fit; a card has a title, an icon, a second
    line (the item's full text, its submenu path) and a size.
  - `card` with a submenu: one card standing for a group or a Windows submenu; it opens it (3.6).
  - `heading` and `line`: text and lines between places.
  - `search`: a box that filters all items as you type (3.5).
- A place without items is not shown (also when late states empty it).
- An example, in the shape it may take:

  ```json
  { "default": [
      { "row": "actions", "rules": [ { "name": { "any": ["Cut", "Copy", "Paste", "Rename", "Delete"] } } ] },
      { "cards": "Programs", "columns": 3, "places": [
          { "card": "LexPen", "rules": [ { "verb": { "startsWith": "LexPen." } } ] },
          { "card": "Archive", "rules": [ { "path": { "regex": "^7-Zip > " }, "disabled": "exclude" } ] } ] },
      { "list": "Open", "rules": [ { "name": { "startsWith": "Open" } } ] },
      { "list": "More", "rest": true }
  ] }
  ```

### 3.5 Interaction

- **Choosing:** a click, or Enter on the focused item: the id handed back, the window closed.
- **Keys:** arrows move through the layout in two directions (across a row or a grid of cards, down through the
  places); Tab to the next place; the `&` letters of Windows' texts kept as keys where they do not clash; Esc closes
  (or closes the open submenu first).
- **Typing searches:** any letter typed with the window open goes into the search box (shown when typing starts, if
  the layout has none); it filters every item of every place, Windows' submenus included once filled, with the same
  match kinds as the rules (contains by default, a leading `/` for a regex). Enter runs the first hit.
- **Disabled items:** shown greyed, or left out, per place (`disabled` in 3.3); a greyed item says why it cannot be
  chosen only if the program says so (it does not: [not yet checked] whether anything can be had).
- **Late changes:** an item that Explorer enables or removes while the window is open changes in place; the layout
  does not jump under the mouse (a removed card leaves its space until the mouse moves on: Open question 5).
- **Closing:** a click outside, the window losing focus, Esc, Alt: closed without a choice, as Windows' menu.
- **Changing the layout from the menu (suggestion):** right-click an item in Dexmenu's window: Pin to the icon row,
  Move to..., Hide, Rename. It writes the layout file; no settings app needed for small changes.
- **Recent (suggestion):** a row of the items chosen most, counted on this computer.

### 3.6 Submenus

- A card or line standing for a Windows submenu opens it the way the user picks (Open question 3):
  - **Flyout:** a panel to the side, as a menu.
  - **In place:** the card opens downward, its items under it, the rest moves down.
  - **Drill in:** the window shows the submenu with a Back item; the path at the top.
- A Windows submenu filled only when opened (Send to, Open with, 7-Zip's): Dexmenu sends `WM_INITMENUPOPUP` for it to
  the owner window, as Windows' menu does when it opens, and reads it then. Whether every common extension fills it
  that way without Windows' menu window being there: [not yet checked], in the spike.
- A group of the user's own (a card holding items from several places) opens the same way.

### 3.7 Drawing and icons

- In the program's process (Explorer first), so no .NET, WebView2 or other runtime (plan 01 3.8): a native popup
  window drawn with Direct2D and DirectWrite, per-monitor DPI, light and dark as Windows has it, the accent colour.
  Open question 1 weighs a separate process instead.
- A window of Dexmenu's own replaces the show call: the hook runs its own message loop until a choice or close, so
  the program waits as it does for Windows' menu.
- Icons:
  - an item's own bitmap where Windows' menu has one (most extensions' items outside Explorer);
  - Explorer's full menu draws every item itself (plan 01 6.2), with no bitmap to read. Asking Explorer to draw an
    item into Dexmenu's memory (`WM_MEASUREITEM` / `WM_DRAWITEM` sent to the owner window) and cutting the icon out:
    [not yet checked];
  - the layout's own icon for an item or card (a file and index, or a glyph of Segoe Fluent Icons);
  - otherwise the first letter.
- Screen readers: the window as UI Automation elements: [not yet checked] what that takes.

### 3.8 Suggested layouts

Shipped as examples; the user starts from one (Open question 6).

- **A. Classic plus.** An icon row on top (Cut, Copy, Paste, Rename, Delete, Properties); a list with Open and Open
  with; one card per program with a submenu of its items (LexPen, 7-Zip, TortoiseGit); "More" with the rest.

  ```
  [Cut] [Copy] [Paste] [Rename] [Delete] [Properties]
  Open
  Open with            >
  +-----------+ +-----------+ +-----------+
  | LexPen  > | | 7-Zip   > | | Git     > |
  +-----------+ +-----------+ +-----------+
  More                 >
  ```

- **B. Cards per program.** A grid of cards, one per program, each card showing its items as buttons in it (not a
  submenu); the icon row on top; a search box.

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
  ...), Share and send (Share, Send to, Copy as path, email), Archive (`regex: zip|7z|archive|extract`), Version
  control (Git, SVN), File (Rename, Delete, Properties), More.
- **D. Minimal.** A search box, a row of favourites, and "All items" (Windows' menu in Windows' order) one click away.

### 3.9 Safety

- As plan 01 3.8: any error before the window shows, or a layout that cannot be read: plan 01's arranged menu, or
  Windows' own menu, shown instead; the error in the log.
- A key held while right-clicking shows Windows' own menu; "Windows' menu" as the last item of every layout.
- Nothing slow on the show call: the layout read once per change; icons cached per process.

### 3.10 Tests

- Rules on a tree made for the test, and on trees read by the test host (plan 01 6.1): every match kind, case,
  disabled include / exclude / only, scope, first match and `also`, the rest, hidden, labels.
- The layout file: valid and invalid files, the fallback.
- The window in the test host: the items shown per place for a given tree and layout; keys and typing; a choice
  hands back the right id (the host clicks or presses Enter through the window, not through Windows' menu).
- Late changes (`--late` of plan 01): an item enabled and one removed while the window is open, the window updated,
  the right id handed back after.
- By hand in Explorer, an Open dialog and Foldex: each suggested layout, lazy submenus (Send to, Open with), icons,
  dark and light, a second monitor with another DPI.

## 4. Open questions

1. **Where the window runs.** In the program's process, native (Direct2D), fast, no runtime, all drawing written by
   hand; or a separate Dexmenu process the DLL talks to on every right-click, which can use WinUI or WebView2 and
   makes cards and animation easy, at the cost of starting or waking it on the right-click ([not yet checked] how
   long that takes)?
2. **The file format.** JSON (as plan 01 said), or a format with comments and less punctuation (JSON5, YAML, TOML),
   since the user edits it by hand?
3. **Submenus.** Flyout, open in place, or drill in; one for all, or per card in the layout?
4. **Icons in Explorer.** Ask Explorer to draw each item and cut the icon out (to be tried), or only icons the
   layout gives, plus the first letter?
5. **Late removals.** A card Explorer removes while the window is open: leave its space until the mouse moves, or
   close up at once?
6. **The starting layout.** Which of 3.8 A - D is the default for a new user?
7. **Plan 01's arranged Windows menu.** Kept as the fallback when Dexmenu's window cannot be shown, or dropped (the
   fallback then being Windows' own menu)?
8. **Changing the layout from the menu.** Pin / Move / Hide / Rename on a right-click in Dexmenu's window, and the
   Recent row: wanted?
