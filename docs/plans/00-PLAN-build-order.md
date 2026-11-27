# Plan 00: Build order: from one card to the full menu

Status: partly executed; see Status.

- 2026-11-21: draft.
- 2026-11-21: partly executed: step 1.
- 2026-11-21: partly executed: step 2.
- 2026-11-21: partly executed: step 3 (by hand in Explorer, an Open dialog and Foldex still to do).
- 2026-11-21: partly executed: step 4.

Orders the parts of plan 01 (`01-PLAN-dexmenu.md`: the DLL, the hook, install), plan 02 (`executed/02-PLAN-own-menu.md`:
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
| Step 1: Delphi DLL | the spike in Delphi: handler, hook, late changes, the test host's checks passing (Explorer by hand with step 3) | 3.1; plan 01 6.3 |
| Step 2: the base layout | the layout file (JSON with comments) with the remaining card; read, checked, read again on change; unit tests | 3.2; 6.2 |
| Step 3: plain cards | Dexmenu's own menu drawn by the DLL: every item a card, submenus opened from their card and filled when opened, keys and mouse, the id handed back, late changes followed, Windows' menu on a broken layout; tested in the test host (by hand: still to do) | 3.3; 6.3 |
| Step 4: the editor's frame | the settings app (.NET 10, WebView2): the layout pane, the kind of right-click, the preview drawn by the DLL from the seen items, redrawn when the layout or seen items change | 3.4; 6.4 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Step 5: editing | built (6.5); the full suite's last part (Send to, a broken layout, the settings app, the editor's self-test in the suite, a layout of rules at a right-click and in the preview) not yet run through: the run was stopped for low memory | a full run of tests/run-tests.ps1 | 3.5; 6.5 |
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

- What: plan 02 3.3 and 3.5 in the editor: the cards view (click a card, set its title and rules; each rule showing
  its number in the priority list) and the rules view (the priority list: number, card, rule; draggable); the
  preview tied to both (an item clicked or hovered shows the card and rule that placed it); cards added, removed,
  titled; rules on a card (name, scope or path, match kinds, states); subitems following a found item; cards with a
  menu; dragging cards onto cards and between lines (rules kept as plan 02 3.5 says);
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

## 6. As built

### 6.1 Step 1

- See plan 01 6.3.

### 6.2 Step 2

- `src/dll/Dexmenu.Json.pas`: `//` comments taken out outside strings, then `System.JSON`.
- `src/dll/Dexmenu.Layout.pas`: the layout as objects (kinds, lines, cards with a title and either rules or a menu;
  a rule is `remaining` or an object kept as written for step 5), checked (exactly one remaining card per kind,
  wherever it is; `default` required; rules and menu not both), shared as a reference-counted `ILayout`.
- Which file: `DEXMENU_LAYOUT_FILE` (tests), else `%APPDATA%\Dexmenu\settings.json` `"layout": "<name>"` as
  `%APPDATA%\Dexmenu\layouts\<name>.json`; none of them: the built-in base layout (only the remaining card). Read again
  when its time stamp changes; a file that cannot be used: no layout, the reason in the log.
- Tested: `tests/unit/DexmenuUnitTests.dpr` (built to `bin\DexmenuUnitTests.exe` by `build.cmd`, run first by
  `tests/run-tests.ps1`): comments, valid and invalid layouts, the built-in base, reading, reading again on a change,
  a broken file. All passed; the menu cases still pass.
- Not yet: the DLL uses the layout from step 3 on (the arranged spike menu still uses its text layout).

### 6.3 Step 3

- `src/dll`: `Dexmenu.Tree` (Windows' items as a tree, a submenu read when opened), `Dexmenu.Place` (the layout
  applied: the remaining card's items each a card on its own line, Windows' separators as thin lines, a card with a
  menu opening its lines, a Windows submenu as its items), `Dexmenu.Draw` (Direct2D and DirectWrite into a 32-bit
  image shown by a layered window; one built-in look, light or dark as Windows' apps; check marks and submenu chevrons
  from Segoe MDL2 Assets; the default item semi-bold), `Dexmenu.Menu` (a window per level, the modal loop, placement
  as Windows' menu with the alignment flags and flipping at the work area's edges, scrolling when taller than the
  screen, hover with Windows' menu delay, click, arrows, Home / End, Enter, Esc, Left / Right, the `&` letters;
  closing when another window is activated; WM_ENTERMENULOOP, WM_INITMENUPOPUP for the top menu and each Windows
  submenu opened, WM_UNINITMENUPOPUP, WM_EXITMENULOOP as Windows' menu sends them; the id returned or posted as
  WM_COMMAND). `Dexmenu.Hook` now shows Dexmenu's menu; calls changing a menu while it is shown are made as always and
  make it read Windows' menu again and redraw. The spike's arranged menu, its text layout and `tests/layout-lexpen.txt`
  are gone.
- The DLL leaves its Direct2D and DirectWrite objects unreleased at process exit (it is pinned; releasing them then
  crashed the test host on exit).
- For the tests: `DEXMENU_DUMP` names a file the DLL writes every shown level and card to after each redraw.
- Tested: `tests/run-tests.ps1`, each selection off, on, off and on with the late changes, and on with a click on
  "View in LexPen" (its id returned); "Send to" opened from its card and filled when opened; a broken layout file
  giving Windows' own menu. All passed. A screenshot of the menu held open (`DexmenuTest --hold`): Windows 11's look.
- Not yet: by hand in Explorer, an Open dialog and Foldex.

### 6.4 Step 4

- The kind of right-click: the handler tells it from the items (`file`, `folder`, `several`, `background`, `drive`,
  else `default`); the menu uses that kind's lines in the layout (the default's when it has none).
- Seen items (`src/dll/Dexmenu.Seen.pas`): after each menu Dexmenu showed, the items of that right-click, with the
  Windows submenus that were opened, in `%APPDATA%\Dexmenu\seen\<kind>.json` (`DEXMENU_SEEN_FOLDER` for the tests),
  merged across right-clicks (6.5).
- The preview (`src/dll/Dexmenu.Preview.pas`, exported `DexmenuPreviewCreate`, `DexmenuPreviewSet`,
  `DexmenuBaseLayout`): a child window of the settings app; the seen items made into a real Windows menu again, then
  the same tree, placement and drawing as a right-click (the drawing split into rendering a level into an image and
  showing it: a layered window for the menu, painted into the preview). Live: hover, submenus open next to their
  card after Windows' delay or on a click, Esc; a choice does nothing. It writes the same dump as the menu.
- The settings app (`src/settings`, .NET 10, WinForms, WebView2 1.0.4258.31 as LexPen, built by `build.cmd` into
  `bin` next to the DLL): left, `web\index.html` with the kind of right-click and the layout's cards as a tree (read
  only); right, the preview. The layout file (`DEXMENU_LAYOUT_FILE`, else `settings.json`'s, else the built-in base),
  `settings.json` and the seen items are watched; a change redraws both panes.
- Tested (`tests/run-tests.ps1`): a right-click recorded, the app started on it: the preview's cards are the menu's
  (text, order, state, submenu mark); the layout file changed while it runs: the preview shows the new layout. The
  host's output is UTF-8 now, so titles beyond ASCII compare. Each host run is guarded (killed and failed after a
  minute), and on its own time-out the host closes Dexmenu's menu itself.
- Seen by hand: a screenshot of the app with the preview of a file's menu.

### 6.5 Step 5

- Rules in the DLL (`src/dll/Dexmenu.Rules.pas`): name (and path) matched by equals, contains, startsWith, endsWith,
  wildcard, regex or any, case insensitive unless `caseSensitive`; `scope` top or anywhere, or a `path`, not both;
  `states`; `also`; `priority`. A regex is compiled when the rule is read (TRegEx otherwise compiles on first use).
  An invalid rule finds nothing.
- Placement (`src/dll/Dexmenu.Place.pas`): the rules in the priority list's order; an item to the first rule that finds
  it, its subitems with it except those taken earlier, which a Windows submenu then leaves out; `also`; the remaining
  card last. A card with rules shows its one item, or a card with a submenu of what it found under its name, or nothing.
  Items are keyed by their menu and id, as a submenu is read again when it opens. A card's `title` and `rename` (regex
  replace) give the item's text. Cards get an id (`c1`, ...) when the layout has none.
- The menu and the preview: the dump names the card and rule that placed
  each item. The preview reports a hover or click (card and rule) to the settings app and marks the items of the card
  selected in the editor (`DexmenuPreviewSetCallback`, `DexmenuPreviewMark`).
- The editor (`src/settings/web`): `layout-model.js` holds the operations (drop onto a card, move between and into
  lines, delete, the last card of a submenu, the remaining card never deleted, add, make a menu, the priority list,
  useless cards); `editor.js` the views: the cards (a tree, dragged; rules numbered by priority; useless cards outlined
  red), the selected card (name, title, extra text, rename, its rules edited in place) and the rules in priority order
  (dragged). Every change goes to the preview at once; Save, Save as, opening another layout and Make active
  (`settings.json`). The editor adds ids and priorities to a layout it opens; saving writes plain JSON, so comments
  written by hand in a layout file are not kept.
- Tested: the DLL's unit tests now include the rules on a menu made in the test (every match kind, case, states, scope,
  path, both given, a bad regex, the priority order both ways, subitems following and left out, also, the layout's
  order, the remaining card in a submenu, a card with a menu holding rule cards, rename, title, found none): all pass.
  The editor's self-test (`DexmenuSettings.exe --selftest`, in WebView2): all pass. `tests/run-tests.ps1` up to the
  selection cases: all pass; the rest (Send to, a broken layout, the settings app's preview, the self-test in the
  suite, a layout of rules at a right-click against the preview, a click inside a found card's submenu) was not run
  through: the run was stopped for low memory.
- Seen items merged (`src/dll/Dexmenu.Seen.pas`): every item any right-click of a kind showed stays in its file, so
  items an extension hides for some selections can be placed too. Items are matched per level by name (two of one
  name one to one); an item missing from a level is kept after the item it followed (after the separator it followed,
  too), and a submenu not opened this time keeps what was seen in it. An item not there every time is marked
  `"sometimes"`: one of an earlier right-click missing now, one of this right-click missing earlier, and one Windows'
  menu lost while shown (the session keeps what it read before each change, as Explorer deletes the items it hides
  after the show). The preview draws those items, and a found card holding only such items, with diagonal stripes;
  the menu at a right-click never does (`Render`'s `Editing`). Once marked, an item stays marked; an item no
  right-click shows any more stays in the file (no way yet to forget one). Tested: unit tests of the merge (order,
  separators, marking both ways, sticky, submenus opened or not, two of one name, the mark read back from the
  preview's menu); a suite case: one file right-clicked without and with a left side chosen in LexPen, the preview
  shows LexPen's items of both, the ones of only one striped (`sometimes=1` in the dump), Edit and View in LexPen not.
  The suite names `tests\layout-base.json` for its base-layout cases, as an unset `DEXMENU_LAYOUT_FILE` picks the
  user's own chosen layout.
- A card places what it found at its own place, each found item a card on its own line, as the remaining card does
  (no card with a submenu of found items); its title is the item's only when it found one. A rule's `consume: false`
  leaves what it found free for later rules and the remaining card (a checkbox "consumes the item" in the editor). A
  click on the card of an open submenu closes it, in the menu and the preview. Dragging cards in the editor: a drop on
  a gap or line end inside a card's menu no longer also drops onto that card, and a card alone on its line dropped
  next to that line stays there instead of going to the end. Tested: unit tests (several found at the card's place,
  in a card with a menu beside a card of its own, the title, `consume` for a later rule, the remaining card and
  subitems); the editor's self-test (the drops next to a card's own line, `consume` valid or not); the suite's rules
  case (LexPen's items at the top, then Tools; the preview the same; View in LexPen chosen). Not tested automatically:
  the click closing a submenu.
- The preview's right-click (plan 02 3.8): "Right-click on" moved from the page to a bar above the preview, with a
  base folder and the item(s) in it; with a folder, Windows' real menu of that right-click there
  (`src/settings/ShellMenu.cs`, made into seen items' text by the DLL's `DexmenuSeenOfMenu`, merged with the seen
  file so hidden items show striped). `DexmenuSettings.exe --live <out> <kind> <folder> [item ...]` writes that text,
  for the tests. Tested: a suite case (a file in the work folder: LexPen's items, 7-Zip's submenu filled; a folder's
  empty part: a menu); by a run here, this repository's empty part shows TortoiseGit's Pull, Push and Commit, a
  folder outside it Clone and Create repository. The bar itself only started, not driven by a test.
- Hidden cards (plan 02 3.3): `"hidden": true` on a card; a checkbox in the card's panel, the card striped and
  dimmed in the cards view. Tested: unit tests (its items nowhere, also not in the remaining card; a hidden card with
  a menu; the remaining card not hidden).
- Dragging next to a card: a card's left or right edge puts the dragged card beside it in its line, its top or bottom
  edge on a line of its own above or below that line (a card that shared a line becomes menu-wide again), the middle
  onto it as before; the edge drawn while dragging. Tested: the editor's self-test (beside, both sides; above and
  below; into a card's menu; not into the card's own menu).
- Rules and cards: the selected card's rules highlighted in the rules view; a rule dragged (from the rules view or
  the card's panel) onto another card with rules is moved there, keeping its place in the priority list, or with
  Shift copied, the copy right after the original. Never the remaining card's rule, never onto a card with a menu
  or the remaining card. Tested: the editor's self-test.
- The cards view: "+ Card" dragged to where the new card goes (a gap, a line's end, a card's edge or onto a card;
  a click still adds it at the end); a card's own actions on hover (a card beside it, one in its menu, make it a card
  with a menu, delete) instead of in the card's panel; a card with a menu folds and unfolds from a gutter on its
  left, collapse all and expand all at the top (folding is not saved). Splitters between the rules, the cards and the
  card's panel, their widths kept in the page's storage. The self-test also parses editor.js. Not tested: the
  dragging, folding and splitters by hand.
- The last right-click: the handler tells where a right-click is (the folder, the items on disk; nothing for what is
  not on disk) and after Dexmenu's menu for it the DLL writes it to `seen\last.json`. The settings app, started
  without `--kind`, sets the preview to it (kind, folder, items: the live menu of that right-click); "Last
  right-click" above the preview goes back to it. Tested: a unit test (the text written); the app started on a
  `last.json` written for the test: the preview shows that file's live menu; a suite case (a right-click writes it),
  which needs bin's DLL registered, as the suite does.
- The folder's empty part in the live preview from a folder view made for the folder (`SHCreateShellFolderView`,
  its background menu), so View, Sort by, Group by, Refresh and Paste are there as in Explorer. Tested: `--live
  background` on a folder gave them; the suite's live case asks for its submenus. A card just added gets the focus:
  selected, scrolled into view, its name selected in its panel.
- Empty Windows submenus: at a right-click, an item whose submenu holds nothing even when opened (Bash's on a DLL) is
  not shown; a submenu with no items yet is opened once (`WM_INITMENUPOPUP`, then `WM_UNINITMENUPOPUP`, as Windows'
  menu does on hover) and read; one with items is never opened early. The preview still shows such items. Tested: a
  unit test (the placement leaves the item out with the list, shows it without); at a right-click: not yet.
- Rules into submenus an extension fills only when opened: when a layout has a rule with scope anywhere or a path,
  a right-click opens every submenu without items yet, deeper levels too, before the rules run, so such a rule finds
  what the extension puts there (Send to's targets). A submenu opened early stays open until the menu closes (as
  if hovered), so the item chosen is still there when its id goes back; Dexmenu does not open it a second time when
  the user opens it. Tested: built, unit tests pass; the suite case (Send to's Desktop target taken to the top by a
  rule with a path) needs bin's DLL registered and has not run yet.
- A card with a menu that shows nothing (its cards found nothing in this right-click) is left out at a right-click;
  the preview shows it, striped (plan 02 3.8). Tested: unit tests.
- A card's comment (`comment`, the editor's only) and hint (`hint`: a text in place of the item's own hint, or
  `{ "regex", "replace" }` on it, so it can be added to). The items' own hints are their handlers' help texts
  (`GCS_HELPTEXTW`), read by the settings app when it builds the live menu and kept with the seen items (a right-click
  keeps them); a text equal to the item's name or its command's name is no hint. The menu and the preview show the
  hint on hover after Windows' hover time, in Windows' tooltip, just below the card (`src/dll/Dexmenu.Tip.pas`).
  Tested: unit tests (the text and regex forms, a hint kept by a merge, read back by path and name); `--live` gave
  real hints (Cut, Copy, the view's items, TortoiseGit's). Not tested: the tooltip showing, by hand.
- Dividers (plan 02 3.4; their look with step 6): `{ "divider": "<text>" or true, "align": "left|center|right" }`
  between lines, at any level; drawn as a thin line in the theme's separator colour, the text (when there is one)
  left, in the middle or right with the line on the rest. The layout's dividers stay where they are; a Windows
  separator next to one goes. Editor: "+ Divider" (icon) beside "+ Card", clicked (at the end) or dragged (a gap, a
  line's end, a card's top or bottom half); a divider in the cards view is dragged, selected (its text and
  alignment in the panel) and deleted on hover. Tested: unit tests (dividers placed, with and without text; the
  Windows separator next to one); the editor's self-test (added, moved between lines and into a card's menu, ids,
  deleted); the preview with dividers drawn (its dump).
- Skip duplicates (`skipDuplicates` on a rule, or on a card for all its rules): of the items found with one name
  (without `&`, any case), only the first shows; the others are taken all the same, so not in the remaining card
  either. Why: Windows' own menu has some items twice (seen with the test host, Dexmenu off, `--hold 3000`: the
  newer-style Move to OneDrive, Unlock with File Locksmith, Rename with PowerRename beside their older copies).
  Checkboxes on the rule and the card. Tested: unit tests (without, on a rule, on a card).
- Latest (`latest` on a rule, a whole number from 1): of the items the rule finds only that many show, the ones seen
  most recently; the others are taken all the same. Why: an item whose name changes each time ("Compare to <file>")
  piles up in the seen items, so the preview showed every name ever seen. The seen file holds a last-seen time per
  item (`seen`, UTC); at a right-click every item is there now, so the first in the menu's order show. Field
  "Latest" in the rule panel (Name rules). Tested: unit tests (valid values; without times, with times, more than
  found; seen times stamped, merged and read back); the editor's self-test (its check).
- Exclude (`exclude: true` on a rule by name): the rule finds nothing; what it matches, the card's rules after it (in
  the card's order, as the editor shows them) do not take, so it stays free for other cards or in its Windows submenu. Why: every item of Open with's
  submenu but LexPen's. Checkbox "exclude" in the rule's Options; drawn reddish with a red handle, "exclude:" in the
  rules view. A card with only exclude rules finds nothing (outlined red). Tested: unit tests (without, with, only
  its own card, only the rules after it, by use invalid); the editor's self-test.
- Dividers as a border (`"border": "divider"` on a card holding or showing cards inside it; `"dividerTop": false`,
  `"dividerBottom": true`): no frame line and no padding, its items in line with the menu's; a divider at the top
  with its title as the text (a plain line without one), one at the bottom when set, left out where nothing follows
  or what follows starts with a border of its own (a divider, a framed group, a group's top divider); its
  background and hover look stay. Editor: Border "dividers (top, bottom)" with the two checkboxes; "Title shown as" not offered then. Tested:
  unit tests (the boxes: no side padding, the titled divider above, the plain one below; neither; the bottom one with
  nothing after, before a framed group, before an item); the user's layout
  drawn by a probe.
- The test host's `--hold <ms>` with Dexmenu off: Windows' menu kept open that long, then printed as it is (the
  shell's late changes in).
- Seen by hand: a screenshot of the editor with a layout of rules (a card with a menu, a useless card outlined red, the
  priority list with a rule's problem) and its preview.
- Not yet: by hand in Explorer; the preview's hover / click selecting a card has no automated test.