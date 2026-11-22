# Plan 05: The settings app as a main window and an editor window per layout

Status: not started; see Status.

- 2026-11-22: draft.

Builds on plan 01 (`01-PLAN-dexmenu.md` 3.7, 3.9: the settings app, registration) and plan 02 (`02-PLAN-own-menu.md`
3.4, 3.5: layouts, the editor). Changes how layouts are chosen per kind of right-click and where they are edited.

## 1. What this is about

The settings app is one window that mixes everything: registering Dexmenu, choosing a layout, a layout's separate
menus per kind of right-click ("This kind of right-click uses the default layout. Give it its own"), editing, and
"Make active", which does not say what it makes active for. Which menu a right-click on a file, a folder or a
folder's empty part gets is hidden inside one layout file and hard to see.

## 2. The solution, in brief

The app opens a main window with the registration at the top (a line saying whether Dexmenu is registered, and
Register, Unregister and Restart Explorer buttons) and two tabs. "General" lists every kind of right-click, each
with the layout it uses. "Layouts" lists the layouts with New..., Edit, Copy, Rename and Delete. Edit and New open
an editor window for one layout, named in its title: its name at the top (changeable), Save, Save as... and Close,
and below it today's panes and preview. A layout is one menu; which kinds use it is set in General, not inside the
layout. "Make active" and "Give it its own" go.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Layout format | a layout is one menu (its lines); old files with a menu per kind converted | Open question 1 | 3.1 |
| Kinds setting | settings.json maps each kind of right-click to a layout; the DLL takes a right-click's layout from it | Layout format | 3.2 |
| Main window | registration line and buttons; tabs General and Layouts | Kinds setting | 3.3 |
| General tab | each kind of right-click with its layout (or none) | Main window | 3.4 |
| Layouts tab | the list; New..., Edit, Copy, Rename, Delete | Main window | 3.5 |
| Editor window | one layout: name, Save, Save as..., Close; the panes and preview of today | Layouts tab | 3.6 |
| Tests | 3.7 | -- | 3.7 |

## 3. Details

### 3.1 A layout is one menu

- A layout file holds one menu: `{ "lines": [ ... ] }` (cards, dividers, cards with a menu, the one remaining
  card), with `//` comments as now. It no longer has a section per kind of right-click (`file`, `folder`,
  `default`, ...).
- The same layout can serve several kinds (a file and several items), and each kind can have a layout of its own.
- Files of today's form (a section per kind, as "First"): Open question 1.

### 3.2 Which layout a right-click gets

- `%APPDATA%\Dexmenu\settings.json`: `"kinds": { "file": "First", "folder": "Folders", "background": "Empty part",
  "default": "First" }`. `default` is used for every kind not listed; a kind set to none: Open question 2.
- The DLL (`Dexmenu.Layout.CurrentLayout`) takes the right-click's kind (as now, from the handler), looks it up in
  `kinds`, and reads that layout file (read again when it changes, as now). `DEXMENU_LAYOUT_FILE` stays for the
  tests: one layout for every kind.
- `"layout"` in settings.json (today's "Make active") goes; on first start it becomes `"kinds": { "default": ... }`.

### 3.3 The main window

- At the top, the registration: a line ("Dexmenu is registered for you: <the DLL's path>", "not registered", or
  "another DLL is registered: <path>") and the buttons Register, Unregister and Restart Explorer. Restart Explorer
  is its own button (today a checkbox with Register), since a registration takes effect in Explorer only after it.
- Below it two tabs, General and Layouts.
- No preview here: the preview belongs to editing (3.6).
- A WebView2 page as today's editor (`web/main.html`), the same host code serving it.

### 3.4 The General tab

- One row per kind of right-click: a file, a folder, several items, a folder's empty part, a drive, and "every
  other" (`default`), each with a choice of the layouts (and none, Open question 2).
- A change is written to settings.json at once (no Save here); the DLL reads it at the next right-click.
- Beside each row, Edit opens that layout's editor (3.6).

### 3.5 The Layouts tab

- The layouts (`%APPDATA%\Dexmenu\layouts\*.json`), by name, each with the kinds that use it.
- New...: asks a name, makes a layout with only the remaining card (the base layout) and opens its editor.
- Edit: opens the selected layout's editor.
- Copy: a copy under a new name ("First copy", the name asked), not used by any kind yet.
- Rename: the file renamed; the kinds using it follow (settings.json changed with it).
- Delete: the file removed (to the recycle bin); a layout in use: Open question 5.

### 3.6 The editor window

- One layout. Its title names it: "Dexmenu - First".
- At the top: the name (editable; a change renames on Save, as Rename does), Save, Save as... and Close. Close with
  unsaved changes: Open question 4.
- Below: today's panes (rules, cards, the selected card) and the preview with its bar ("Right-click on", the folder,
  the item, Last right-click). The kind chosen there is only what the preview shows; it starts on a kind that uses
  this layout.
- Gone from the editor: the layout choice in its header, Make active, "This kind of right-click uses the default
  layout" and Give it its own.
- Several editor windows at once: Open question 3.

### 3.7 Tests

- The DLL's unit tests: a right-click's layout from `kinds` (a listed kind, `default` for the rest, none);
  read again when settings.json changes.
- The settings app: its self-test extended with the main page's operations (the kinds written, rename following,
  copy, delete); the editor's self-test as now.
- The suite: a right-click on a file and on a folder's empty part with two different layouts in `kinds`, each
  showing its own menu; the conversion of an old file (Open question 1).

## 4. Open questions

1. Today's layout files with a menu per kind (as "First"): split on first start into one layout per kind
   ("First - file", "First - folder", ...) with `kinds` set to match, or keep only the `default` menu and drop the
   others?
2. A kind set to no layout: Windows' own menu for that kind (Dexmenu off for it)? Suggested: yes, so a kind can be
   left to Windows.
3. May several layouts be open in editor windows at once, or one editor window at a time?
4. Close with unsaved changes: ask Save / Discard / Cancel? Suggested: yes.
5. Delete a layout that kinds use: refuse until no kind uses it, or set those kinds to none (Windows' menu)?
6. Does the main window need anything of the editor (a preview, the last right-click), or is it only registration
   and the two tabs? Suggested: only those.
