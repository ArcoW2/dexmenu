# Plan 01: Dexmenu: Windows' right-click menu arranged your way, every program's items still working

Status: partly executed; see Status.

- 2026-11-21: draft.
- 2026-11-21: partly executed: the spike in a test host (DLL, hook, a minimal layout, LexPen's items into a submenu).

Dexmenu arranges the menu for every program that shows Windows' right-click menu for files and folders: Explorer, the
Open and Save dialogs, other file managers.

## 1. What this is about

Windows' right-click menu for a file or folder is long and chaotic: Windows' own items, and every installed program
adds its own (registry verbs, and shell extensions as a .dll: 7-Zip, TortoiseGit, a cloud drive's items), in an order
no one chose. Some of those items appear only for some files, or only once something is switched on. Tools that
rearrange the menu (Nilesoft Shell) do not keep up with items that extensions add themselves. The user wants to decide
which item goes where, or is hidden, in every program, while every item still does exactly what it does now.

## 2. The solution, in brief

Windows keeps building its menu as it does now, every extension adding its items; Dexmenu changes only how it is
shown. A small shell extension of Dexmenu's own is loaded with every right-click menu; it notes which menu is being
built, and when the program shows that menu, Dexmenu lays the same items out by the user's layout and shows that
instead, as a normal Windows menu. The item chosen is handed back by its own id, so the program runs it on the menu
Windows built, exactly as before. A separate settings app edits the layout from the items Dexmenu has actually seen.
On any doubt, Windows' own menu is shown untouched.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Spike, test host | the shell extension loaded, the show call caught, the top level arranged into a submenu of the user's own with Windows' items moved (same ids), put back after; checked in a test host | 3.1 - 3.4; 6.1 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Spike, Explorer and Open dialog | the same, by hand, in Explorer's full menu and an Open dialog: in Explorer the states set after the show onto the moved items | Open questions 1, 2, 6 | 3.1; 3.2; 6.1; 6.2 |
| Layout engine | the layout file as planned (`layout.json`, kinds of right-click, items in submenus by path, Hidden, Other, groups) | -- | 3.3; 3.4 |
| Showing it | the arranged menu shown, lazy submenus and self-drawn items working, the choice handed back | Spike | 3.4; 3.5 |
| Seen items | each item seen recorded per kind of right-click, for the settings app | Layout engine | 3.6 |
| Settings app | the layout edited from the seen items; Dexmenu on and off | Seen items; Open question 3 | 3.7 |
| Safety | fallback to Windows' menu on any error, a key to get Windows' menu, off switch | Showing it | 3.8 |
| Install | registration, per user or per machine, removal | Open question 4 | 3.9 |
| Windows 11 menu | the short menu of Windows 11 | Open question 5 | 3.10 |
| Tests | 3.11 | -- | 3.11 |

## 3. Details

### 3.1 How a program shows the menu, and where Dexmenu comes in

- A program asks Windows for the menu of the items (`IContextMenu` over them: `SHCreateDefaultContextMenu`, the
  folder's `GetUIObjectOf`), lets it fill an empty `HMENU` (`QueryContextMenu`; every shell extension registered for
  those items adds its items then), shows it (`TrackPopupMenu` or `TrackPopupMenuEx`) and runs the chosen id
  (`InvokeCommand`). Explorer, the file dialogs and other file managers all do this.
- Dexmenu is one more shell extension (`IShellExtInit`, `IContextMenu`), registered for files, folders, a folder's
  empty part and drives (`*`, `Directory`, `Directory\Background`, `Drive`, `AllFilesystemObjects`; the exact set:
  [not yet checked]). So it is loaded into every process that builds such a menu, the same way 7-Zip's is.
- Its `QueryContextMenu` adds nothing; it only notes the `HMENU` it was given: that handle is a shell right-click menu
  being built. `IShellExtInit.Initialize` gives it the items (their types, one or several, a folder's empty part), for
  a layout per kind of right-click (3.3).
- In each process it is loaded into, it hooks the show call once (`TrackPopupMenu` and `TrackPopupMenuEx`; which one
  each program uses: [not yet checked]). A call with a noted `HMENU`: Dexmenu's turn (3.4). Any other menu (a program's
  own menus): passed through untouched.
- By the time the menu is shown, every extension has added its items. Submenus an extension fills only when they open
  are filled when they open, in the arranged menu too (3.5).
- Not every item's state is final then. Explorer builds its full menu with `CMF_ASYNCVERBSTATE`: an Explorer command
  (`IExplorerCommand`, as LexPen's items) is put in disabled, and its state (shown, hidden, enabled) is asked for in
  the background and set on the menu while it is open. Seen in Explorer: every LexPen item disabled when the menu is
  shown, the hidden ones included. A program that builds the menu without that flag (Foldex, the test host) has
  every state before the show call. How Explorer sets the states later (which calls, by id or by position): [not yet
  checked]; Open question 6.
- Explorer's full menu has every item owner-drawn by the time it is shown (Explorer draws them itself); each item
  keeps its text, so it is named as any other.

### 3.2 The hook

- A small hooking library in the DLL (MinHook or Detours for C++; DDetours for Delphi: Open question 1), set when the
  DLL is first loaded into a process and removed when it unloads.
- Explorer keeps it loaded; a dialog's process loads it when its first right-click menu is built. Before that first
  menu nothing is hooked, which is fine: nothing to arrange yet.
- The DLL holds no state across processes; each process reads the layout file itself (3.3), and reads it again when
  it changed (its time stamp).

### 3.3 The layout

- A file of the user's (`layout.json` in `%APPDATA%\Dexmenu`; [not yet decided]), written by the settings app, read
  by the DLL.
- Per kind of right-click (a file, several items, a folder, a folder's empty part, a drive; by type where wanted, as
  `.zip`): an ordered list of places, each a group (with a line between groups) or a submenu of the user's own, holding
  the items that go there, matched by name.
- An item's name: its text without the `&`, with the submenu it sits in (Windows' or a program's) before it
  (`7-Zip > Add to archive...`). Windows' menu carries only texts and ids, so this is the only name it has. A pattern
  may match several (`7-Zip > *`). A program that changes its wording needs placing again (3.6 shows it as new).
- Hidden: a place of its own; those items do not show (Windows' menu still has them, 3.8).
- Not placed (a new program, a new item): in the group "Other", in Windows' order, so nothing disappears silently.
- Windows' own lines and empty groups are dropped and redrawn from the layout's groups.

### 3.4 Showing the arranged menu

- On the caught call: Windows' menu read into a tree (each item: text, id, state, bitmap, submenu handle, self-drawn
  or not), the layout applied, and a new `HMENU` built from it with the same ids. The original show call is then made
  with the new menu, so Windows draws it: its look, dark mode, keys, the `&` letters, nothing of Dexmenu's own to draw.
- Submenus are moved, not copied: a submenu handle of Windows' menu is taken out of it (`RemoveMenu`, not destroyed)
  and put into the new one, so the extension that owns it still recognises it (3.5). After the call everything is put
  back where it was, so the program destroys its menu as it always does.
- The chosen id: returned as Windows' call would return it (with `TPM_RETURNCMD`), or posted to the owner window as
  `WM_COMMAND` (without it), exactly as the original call would have. The program then runs it on its own menu.
- A submenu of the user's own (a group folded into a submenu): a new popup holding moved items; its ids are Windows'.

### 3.5 Submenus filled on opening, self-drawn items

- A submenu an extension fills only when it opens (Send to, Open with, 7-Zip's): Windows sends `WM_INITMENUPOPUP` for
  it to the owner window, which hands it to the extension (`IContextMenu2/3.HandleMenuMsg`). The arranged menu has the
  same owner and the same submenu handle, so this happens unchanged. Whether every common extension works so with a
  submenu that sits elsewhere in the menu: [not yet checked], in the spike.
- An item an extension draws itself (owner-drawn: `WM_MEASUREITEM`, `WM_DRAWITEM` to the owner): kept as such in the
  new menu, with its item data, so the extension still draws it.
- Items whose text an extension changes on opening a submenu are named after the change only from the next
  right-click; [not yet checked] whether any does this.

### 3.6 Seen items

- The DLL writes each item it saw, per kind of right-click, with its submenu, to a file next to the layout (merged,
  not one per right-click), so the settings app lists what is really there on this computer, programs added later
  included.
- New items (seen, not placed) are marked new in the settings app.

### 3.7 The settings app

- Shows, per kind of right-click, the places of the layout and the items in them; items are dragged between places,
  into a submenu of their own, or into Hidden; groups and submenus added, renamed, ordered.
- Dexmenu on and off for everything (3.8).
- A separate program, not loaded into Explorer: its language and look are free (Open question 3).

### 3.8 Safety

- Any error while reading, arranging or building: Windows' own menu shown untouched, the error written to a log.
- A key held while right-clicking (Shift is Windows' extended menu, so another one: [not yet decided]) shows Windows'
  own menu.
- "More (Windows' menu)" at the bottom of every arranged menu: Windows' own menu, for whatever the layout hides.
- Dexmenu off: the hook passes every call through; the DLL stays registered.
- The DLL lives in other programs' processes (Explorer first): no .NET or other runtime loaded into them, no threads
  of its own, nothing slow on the show call (the layout read once per change, not per right-click).

### 3.9 Install

- The DLL registered as a COM class and as a context menu handler for the types of 3.1, signed.
- Per user (`HKCU\Software\Classes`) needs no administrator, but elevated programs do not read per-user COM classes,
  so their menus stay Windows' own; per machine (`HKLM`) covers those too: Open question 4.
- Removal: the registration taken away; Explorer restarted or signed out and in, as for any shell extension.

### 3.10 Windows 11's short menu

- Windows 11 shows a short menu of its own first (not a `TrackPopupMenu` menu) and the full one under "Show more
  options". Dexmenu arranges the full one. Either the user switches Windows to the full menu straight away (the
  registry switch under `HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}`, which the settings app
  can set and undo), or Dexmenu applies only under "Show more options": Open question 5.

### 3.11 Tests

- Unit: the layout engine on a menu tree made for the test (placing, patterns, hidden, Other, groups and lines,
  submenus of the user's own), no Windows menu needed.
- A test host program: builds Windows' menu for given items as Explorer does and shows it, with Dexmenu loaded; checks
  the arranged menu's items against the layout, and that the id chosen is the one Windows' menu has for that item.
- By hand, in Explorer and an Open dialog: a registry verb, a .dll extension's item (7-Zip, TortoiseGit when
  installed) and a lazy submenu (Send to) chosen from the arranged menu, each doing what it does now; the fallback key;
  "More (Windows' menu)"; an error forced (a broken layout file): Windows' menu shown.
- Another file manager that shows Windows' menu itself: its right-click shows the arranged menu, with the items it
  adds of its own placed by the layout like any other.

## 4. Open questions

1. **The DLL's language.** C++ (MinHook or Detours) or Delphi (DDetours)? Both make a native DLL without a runtime to
   load into Explorer. The settings app can be another language.
2. **Which programs.** Every program that builds a shell right-click menu (Explorer, file dialogs, other file managers), or
   only some (a list in the settings app)?
3. **The settings app.** Its language and look: .NET WinForms, a WebView2 page, Delphi?
4. **Per user or per machine.** Per user needs no administrator but leaves elevated programs' menus as Windows' own;
   per machine covers them and needs an installer with administrator rights.
5. **Windows 11's short menu.** Switch Windows to the full menu (the settings app sets the switch), or arrange only
   under "Show more options"?
6. **States set after the show (Explorer).** Explorer sets an Explorer command's state on its own menu while it is
   open (3.1), so a moved item keeps the disabled state it had at the show. Follow Explorer's changes onto the moved
   items (hook the menu calls Explorer makes, once the trace has shown which), or wait for the states before
   arranging, or leave Explorer commands where Explorer put them?

## 6. As built

### 6.1 The spike, in a test host

- `src/shell/DexmenuShell.cpp`: C++ with WRL and MinHook (v1.3.4, `src/vendor/minhook`), built by `build.cmd`
  into `bin`. C++ for the spike only, the same toolchain as LexPen's `LexPenShell.dll`; Open question 1 stays open.
- A context menu handler (`IShellExtInit`, `IContextMenu`) that adds nothing; its `QueryContextMenu` notes the
  `HMENU`. On first use it hooks `TrackPopupMenu` and `TrackPopupMenuEx` (user32) and pins the DLL, so the hooks
  never point into an unloaded DLL. The hook only acts on a noted menu.
- On only when `HKCU\Software\Dexmenu` `Enabled` is 1 (`register.ps1 -Enable`) or the process has `DEXMENU=1` (the
  tests). Registered but off, the handler sets no hook, so Explorer's menu stays Windows' own.
- `register.ps1`: per user, for `AllFilesystemObjects`, `Directory\Background` and `Drive`; `-Remove` takes it away.
- The layout is a minimal text file, not yet 3.3: `[submenu name]` then one pattern per line (`*`, `?`), matched
  against top-level texts without `&` and accelerator; `DEXMENU_LAYOUT`, else `%APPDATA%\Dexmenu\layout.txt`; read
  again when its time stamp changes. No layout or no match: Windows' menu shown untouched.
- Arranging: Windows' items read (type, state, id, bitmap, item data, check marks, submenu handle), taken out of
  Windows' menu with `RemoveMenu`, inserted into the new menu or the group's submenu, which sits where its first item
  was; stray lines dropped. After the call the new menus are emptied and destroyed and Windows' items put back in
  their order. Any failure: put back, Windows' menu shown, a line in `%LOCALAPPDATA%\Dexmenu\dexmenu.log`.
- Tested with `tests/host/DexmenuTest.exe` (the parent folder's `GetUIObjectOf`, `QueryContextMenu`,
  `TrackPopupMenuEx`; it reads the menu actually shown from the first `WM_INITMENUPOPUP`, then `EndMenu`). LexPen's
  items are found by their verb (`LexPen.*`, `GetCommandString`), not by the layout's texts. Checks: Dexmenu off, the
  shown menu is Windows' menu; on, "from LexPen" holds exactly LexPen's items with the same text, id, state, type,
  bitmap, item data and submenu, in Windows' order, where the first was; every other item unchanged and in order;
  after the call Windows' menu is as it was; 0 returned on close.
- `tests/run-tests.ps1` runs the host off and on for selections where LexPen shows other items or titles: one file;
  one with a `.bak`; two files; a folder; a file and a folder; a file with a left side chosen (it sets LexPen's
  `LeftFile` for the run and puts the key back). Each case checks LexPen's items against what `LexPenShell.cpp`
  gives for it, and that LexPen gives the same items with Dexmenu on. All cases passed, in three runs in a row.
- Not covered: LexPen only shows or hides (`ECS_ENABLED`, `ECS_HIDDEN`), it never disables, so a disabled LexPen
  item is not tested; the state is copied as a whole, and a disabled item of Windows' ("Retrieving libraries...",
  in a submenu) is shown disabled. LexPen's submenu mode (`explorerPlace` "submenu") not tested. Choosing an item
  (the id handed back) is checked only by the ids being Windows' ids, not by a choice made. An Open dialog not tried.

### 6.2 The spike in Explorer and Foldex

- Foldex: "from LexPen" shown with LexPen's items as Windows gives them; a choice reached LexPen's command. That
  command failed with "Windows cannot find ..." also without Dexmenu (`DexmenuTest --invoke LexPen.CompareLeft`:
  `0x80070002`): LexPen's `HKCU\Software\Classes\LexPen.Shell` key, which holds its exe, is missing on this computer.
- Explorer (full menu): the show call is made with the noted `HMENU`, so the hook works there. Every item is
  owner-drawn by then; the DLL reads their text too. "from LexPen" is shown, but LexPen's items in it stay disabled
  and the hidden ones show: Explorer's later state changes (3.1) reach its own menu, not the moved items. Open
  question 6.
- The trace (`HKCU\Software\Dexmenu` `Trace` 1): each menu noted, each show call and each item in
  `%LOCALAPPDATA%\Dexmenu\dexmenu.log`. `DEXMENU=0` forces the DLL off in a process, so the tests hold while the
  registry has Dexmenu on.
