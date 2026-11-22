# Plan 05: The settings app as a main window and an editor window per layout

Status: partly executed; see Status.

- 2026-11-22: draft.
- 2026-11-22: partly executed: the layout format.

Builds on plan 01 (`01-PLAN-dexmenu.md` 3.7, 3.9: the settings app, registration) and plan 02 (`02-PLAN-own-menu.md`
3.4, 3.5: layouts, the editor). Changes how layouts are chosen per kind of right-click and where they are edited.

## 1. What this is about

The settings app is one window that mixes everything: registering Dexmenu, choosing a layout, a layout's separate
menus per kind of right-click ("This kind of right-click uses the default layout. Give it its own"), editing, and
"Make active", which does not say what it makes active for. Which menu a right-click on a file, a folder or a
folder's empty part gets is hidden inside one layout file and hard to see.

## 2. The solution, in brief

The app opens a main window with two panels. "General" holds the registration (a line saying whether Dexmenu is
registered, and Register, Unregister and Restart Explorer buttons) and every kind of right-click, the desktop's empty
part among them, each with the layout it uses. "Layouts" lists the layouts with New..., Edit, Copy, Rename and
Delete. Each panel has a minimum size; the panels stand next to each other or above each other when both fit at
that size, and become tabs when they do not. The window never gets smaller than one panel's minimum. Edit and New open an editor window for one layout, named in its title: its
name at the top (changeable), Save, Save as... and Close, and below it today's panes and preview. A layout is one
menu; which kinds use it is set in General, not inside the layout. "Make active" and "Give it its own" go.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Layout format | a layout is one menu (`format`, `lines`); an older file read by its default menu, brought to the current form by the editor | 3.1; 6.1 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Layout versions | a format number in each layout; the editor updates an older file when it opens it; the DLL shows a warning (a note card) and the remaining card for a file it cannot use | Layout format; plan 02 Note card | 3.1.1 |
| Kinds setting | settings.json maps each kind of right-click to a layout; the DLL takes a right-click's layout from it | Layout format | 3.2 |
| Open dialog | a right-click in an Open or Save dialog as kinds of their own (a file, a folder, several, an empty part, a drive in a dialog) | Kinds setting | 3.2 |
| Desktop kind | the desktop's empty part as a kind of its own: the handler registered for it, told apart from a folder's empty part | -- | 3.2 |
| Main window | the panels General and Layouts, each with a minimum size: side by side, stacked or as tabs by what fits; the window not smaller than one panel | Kinds setting | 3.3 |
| General panel | the registration line and buttons (Restart Explorer lit after a change); each kind of right-click with its layout (or none) | Main window | 3.4 |
| Layouts panel | the list; New..., Edit, Copy, Rename, Delete | Main window | 3.5 |
| Editor window | one layout: name, Save, Save as..., Close (asks to save); the panes and preview; every kind in the preview, marked when not meant for it; several windows, cards and rules copied or moved between them | Layouts panel | 3.6 |
| Tests | 3.7 | -- | 3.7 |

## 3. Details

### 3.1 A layout is one menu

- A layout file holds one menu: `{ "lines": [ ... ] }` (cards, dividers, cards with a menu, the one remaining
  card), with `//` comments as now. It no longer has a section per kind of right-click (`file`, `folder`,
  `default`, ...).
- The same layout can serve several kinds (a file and several items), and each kind can have a layout of its own.
- The Default layout: made on first start (`layouts\Default.json`), holding only the remaining card, and set for
  `default`, so every kind starts with it: Windows' menu as cards until the user changes it or sets other layouts.
- The user's layouts stay as they are on an update: no file is rewritten, none is made from another. A file of
  today's form (a section per kind, as "First") is read by its `default` section as its one menu; its other kinds'
  sections are ignored, and dropped when the user saves that layout. A menu for another kind is a layout the user
  makes (New, or Copy).

### 3.1.1 Versions of the format

- Each layout file says which form it has: `"format": <n>`, written by the editor (a file without it is of today's
  form). A new option that needs other entries raises the number.
- A file is updated only by the editor: opening an older file there brings it to the current form in the editor
  (entries added or renamed, nothing the user made lost), shown as a change not yet saved; it is written with the
  next Save. Nothing else rewrites a layout: not an update of Dexmenu, not the DLL, not the main window.
- The DLL reads every older form it knows as it is. A file it cannot use (a form newer than it knows, or one too old
  to read): the menu shows, as its first card, a note card (plan 02 3.3) with the warning that the layout needs
  updating ("Layout <name> needs updating: open it in Dexmenu's editor"), then the remaining card with every item
  of Windows' menu, so nothing is missing. A note card is no button, so the warning only tells.
- A file that is not valid JSON or breaks a rule (no remaining card): as now, Windows' own menu, the reason in the
  log; the editor shows the reason when the file is opened.

### 3.2 Which layout a right-click gets

- `%APPDATA%\Dexmenu\settings.json` sets a layout per kind (the order and the form: below). `default` is used for
  every kind not set. A kind set to `none` gets Windows' own menu: Dexmenu leaves that kind to
  Windows.
- The DLL (`Dexmenu.Layout.CurrentLayout`) takes the right-click's kind (as now, from the handler), looks it up in
  `kinds`, and reads that layout file (read again when it changes, as now). `DEXMENU_LAYOUT_FILE` stays for the
  tests: one layout for every kind.
- `"layout"` in settings.json (today's "Make active") goes; on first start the layout it names is set for `default`
  (`"kinds": [ ..., { "kind": "default", "layout": "<that name>" } ]`), else the Default layout (3.1).
- The kinds: a file, a folder, several items, a folder's empty part, the desktop's empty part, a drive, and every
  other (`default`). No kinds by file type: one menu per type has no use seen.
- In an Open or Save dialog a right-click may want another menu than in Explorer (no "Open in new window", fewer
  programs): the kinds there are kinds of their own, `dialog-file`, `dialog-folder`, `dialog-several`,
  `dialog-background` and `dialog-drive` (the desktop's empty part does not occur in a dialog). One menu for all of
  them is one layout set for each.
- The kinds are in an order, and a right-click gets the layout of the first kind that fits it: a right-click on a
  file in an Open dialog fits both `dialog-file` and `file`, and whichever is first wins. In settings.json the order
  is kept: `"kinds": [ { "kind": "dialog-file", "layout": "Dialog" }, { "kind": "file", "layout": "First" }, ...,
  { "kind": "default", "layout": "Default" } ]`. A kind without a layout set is skipped (the next that fits
  decides); one set to `none` decides: Windows' own menu. `default` fits every right-click and is always last. The
  starting order: the dialog kinds (not set, so a dialog gets Explorer's kinds until the user sets them), then file,
  folder, several, background, desktop, drive, default.
- The handler tells a dialog by the window that shows the menu: its top window is a file dialog
  (class `#32770` holding a shell view): [not yet checked] that this holds for every program's dialog.
- The desktop's empty part (`desktop`): the handler is registered for it too (`DesktopBackground`, by
  `Registration.cs` and `register.ps1`, removed with the others); the handler tells it from a folder's empty part
  by its folder being the desktop. Its seen items, last right-click and live preview as for the other kinds; the
  live preview asks the desktop's folder view (as for a folder's empty part, plan 02 3.8): [not yet checked]
  whether it gives the desktop's own items (View, Sort by, Refresh, Display settings, Personalise) or only a
  folder's.

### 3.3 The main window

- Only about Dexmenu itself, never inside a layout: the registration, which layout each kind uses, and the layouts
  as files (new, copy, rename, delete). Editing a layout happens in its editor window (3.6), which knows only that
  layout.

- Two panels, General and Layouts. Each has a minimum width and height, set by Dexmenu: what its content needs, a
  list or table at least three rows (General: the registration and three kinds; Layouts: its buttons and three
  layouts). The sizes themselves: [not yet calculated]; measured from the panels when built.
- Placed by what fits, in this order:
  - next to each other (General left), when the window is at least both minimum widths wide and the higher of the
    minimum heights high;
  - else above each other (General on top), when it is at least the wider minimum width wide and both minimum
    heights high;
  - else tabs, one panel at a time.
  Within a placement the panels share the room the window has (more than their minimum when there is).
- The window's minimum size is set for its inside (its client area; WinForms `MinimumSize` from it plus the frame):
  - width: the largest of the panels' minimum widths, plus the page's margins at the sides;
  - height: the largest of the panels' minimum heights, plus the page's margins at the top and bottom, plus the
    tabs' height (the smallest window shows tabs).
  So the smallest window holds one panel at its minimum, as a tab.
- A screen smaller than that minimum (not expected: a 640x480 window should hold it): the window does not fit, and
  the page's content scrolls.
- The editor window (3.6) is much larger and has its own minimum, from its panes and the preview.
- No preview here: the preview belongs to editing (3.6).
- The panels are one page; the page measures the panels' minimums and tells the app (its `MinimumSize`), and on
  every resize chooses the placement, so resizing the window rearranges them at once, without a reload.
- A WebView2 page as today's editor (`web/main.html`), the same host code serving it.

### 3.4 The General panel

- At its top, the registration: a line ("Dexmenu is registered for you: <the DLL's path>", "not registered", or
  "another DLL is registered: <path>") and the buttons Register, Unregister and Restart Explorer. Restart Explorer
  is its own button (today a checkbox with Register), since a registration takes effect in Explorer only after it.
- After Register or Unregister, Restart Explorer gets the focus and is lit (drawn as the main button, in the accent
  colour), with the line saying the change takes effect in Explorer after a restart. It stays lit until Explorer has
  restarted (from this button, or Explorer started again otherwise, which the app sees by Explorer's process).
- Below it, one row per kind of right-click (3.2), the dialog kinds among them ("a file in an Open or Save dialog",
  ...), each with a choice of the
  layouts, None (Windows' own menu) and Not set (the next kind that fits decides). The rows are in the order the
  kinds are tried, dragged to sort them; "Every other" (`default`) stays last and has no Not set.
- A change is written to settings.json at once (no Save here); the DLL reads it at the next right-click.
- Beside each row, Edit opens that layout's editor (3.6).

### 3.5 The Layouts panel

- The layouts (`%APPDATA%\Dexmenu\layouts\*.json`), by name, each with the kinds that use it.
- New...: asks a name, makes a layout with only the remaining card (the base layout) and opens its editor.
- Edit: opens the selected layout's editor.
- Copy: a copy under a new name ("First copy", the name asked), not used by any kind yet.
- Rename: the file renamed; the kinds using it follow (settings.json changed with it).
- Delete: asks first; for a layout in use the question names the kinds using it and says they will be set to None
  (Windows' own menu) when it is deleted. Then the file goes to the recycle bin and those kinds are set to `none`.

### 3.6 The editor window

- One layout. Its title names it: "Dexmenu - `layout name`".
- At the top: the name (editable; a change renames on Save, as Rename does), Save, Save as... and Close.
- Closing the window (Close, or the window's own close) with unsaved changes asks whether to save them: Yes (save,
  then close), No (close without saving), Cancel (stay open).
- Below: today's panes (rules, cards, the selected card) and the preview with its bar ("Right-click on", the folder,
  the item, Last right-click). A layout can serve several kinds, so the kind stays a choice there, and every kind
  can be chosen: the kind is only what the preview shows. It starts on a kind that uses this layout. A kind this
  layout is not set for in General shows a small text above the preview: "This layout is not meant for this kind".
- Gone from the editor: the layout choice in its header, Make active, "This kind of right-click uses the default
  layout" and Give it its own.
- Several editor windows at once, one per layout (Edit on a layout already open brings its window to the front), so
  cards, dividers and rules can be copied or moved from one layout to another: dragged between the windows (a move;
  with Shift a copy, as rules between cards now), and copied with Ctrl+C / Ctrl+V as a fallback. Whether WebView2
  carries a drag with the editor's own data types from one window to another: [not yet checked]; if not, only
  Ctrl+C / Ctrl+V (the item as JSON on the clipboard).
- A card copied into another layout gets a new id there; a rule copied gets a place at the end of that layout's
  priority list; the remaining card is never copied or moved (each layout has its own).

### 3.7 Tests

- The DLL's unit tests: a right-click's layout from `kinds` (a listed kind, `default` for the rest, none);
  read again when settings.json changes; a file of a newer format: the warning card, then every item as cards.
- The editor's self-test: an older file opened is brought to the current form and marked not saved.
- The settings app: its self-test extended with the main page's operations (the kinds written, rename following,
  copy, delete); the editor's self-test as now, plus a card and a rule copied into another layout (new id, end of
  the priority list) and the remaining card refused. The three arrangements of the panels seen by hand (a wide, a narrow
  and a narrow short window), and the window refusing to get smaller than a panel's minimum.
- The suite: a right-click on a file and on a folder's empty part with two different layouts in `kinds`, each
  showing its own menu; a kind set to none showing Windows' menu; a right-click in an Open dialog with `dialog` set
  showing that layout; an old file read by its default menu, the file itself unchanged until saved; registration
  adds and removes the
  desktop's handler key; the desktop's empty part right-clicked in the test host gives the kind `desktop`.

## 4. Open questions

None.

## 6. As built

### 6.1 The layout format

- The DLL (`src/dll/Dexmenu.Layout.pas`): `FormatVersion` 1; a file with `"format": 1` is read by its `lines`; one
  without `format` by its `default` section, its other sections ignored (not checked either); a newer format is not
  used, the reason naming both numbers (Windows' menu until the warning card, 3.1.1). `ILayout.Lines(Kind)` gives
  the one menu for every kind. The built-in base layout is in the new form.
- The editor (`layout-model.js` `upToDate`, `editor.js`): it edits `lines`; an older file opened is brought to the
  new form (its `default` section as `lines`) and shown as not saved, written with the next Save. The banner "This
  kind of right-click uses the default layout" and "Give it its own" are gone.
- Not yet: the Default layout file made on first start (with the kinds setting, 3.2), the warning card (3.1.1).
- Tested: unit tests (format 1 read; without `lines` refused; a newer format refused with its reason; the older
  form read by its default menu, a broken other section ignored); the editor's self-test (an older file brought to
  the current form and marked changed, a current one unchanged); the settings app started on a format-1 layout: the
  preview showed it (its dump).
