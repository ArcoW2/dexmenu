# Plan 16: Diagnostics: where the time of a right-click goes

Status: not started; see Status.

- 2026-11-26: draft.

Builds on the timing in the log (the log's times in ms; with tracing on, `menu shown, ms:` with Dexmenu's steps) and
the test host's `timing:` lines.

## 1. What this is about

A right-click takes a while before the menu shows. Most of it is Windows building its menu with every installed shell
extension (TortoiseSVN, Foxit, PowerToys, ...), before Dexmenu sees the menu; a smaller part is Dexmenu's own, large
only on the first right-click in a program. Today this can only be found with scripts and the trace log. The user
wants to see it in the settings app: which extension costs how much, and what Dexmenu itself takes.

## 2. The solution, in brief

A Diagnostics page in the main window with two tables. Extensions: every context menu handler registered for a kind
of right-click (file, folder, background, drive), each timed in a separate measuring process on a sample of that
kind, loaded fresh and again warm, with its name, file and the items it adds; a slow one the user does not need can
be switched off there, and on again. Right-clicks: the last ten right-clicks Dexmenu showed per program (Explorer,
Foldex, a dialog), with the time from Dexmenu's handler being asked to the menu shown, and Dexmenu's own steps. The
DLL writes these timings to a small file; the page reads it.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Timing in the log | ms in the log; Dexmenu's steps logged with tracing on; the test host's timings | 3.4 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Measuring process | each handler of a kind timed (create, Initialize, QueryContextMenu), fresh and warm | -- | 3.1 |
| Right-click timings | the DLL keeps the last right-clicks' timings per program in a file | -- | 3.2 |
| Diagnostics page | the main window's page with both tables and a Measure button | Measuring process; Right-click timings | 3.3 |
| Switching off | a handler switched off and on from the page (Windows' blocked list for the user) | Diagnostics page | 3.6 |
| Hang setting | how long one handler may take before it is stopped, a setting | Measuring process | 3.1 |
| Tests | 3.5 | -- | 3.5 |

## 3. Details

### 3.1 The extensions

- The handlers come from the registry, as Windows finds them for the kind: `*`, `AllFilesystemObjects` and the
  sample file's type for a file; `Directory`, `Folder` and `AllFilesystemObjects` for a folder;
  `Directory\Background` for a background; `Drive` for a drive. A handler on the blocked list is shown as blocked,
  not timed.
- The sample: a file and a folder the measuring process makes in a temp folder (a `.txt` file), the temp folder's
  background, the system drive. A handler that acts on a file's type only (Foxit on PDFs) is timed only with a file of
  that type; the page can be given a file of the user's choice to measure with.
- Each handler is timed in its own measuring process (the settings app started with an argument), so a handler that
  crashes or hangs does not take the app with it. How long one handler may take before it is stopped and shown as
  hanging is a setting on the page; its default is chosen once the first measurements show what is usual
  ([not yet decided]). While a measurement runs, the page shows how long the current handler has taken, with a Stop
  button that stops it by hand. Per handler: create (loading its DLL), Initialize, QueryContextMenu, fresh (first in the process) and
  warm (a second time in the same process), and the number of items it added.
- Windows' own total for the kind: the menu built the way Explorer builds it (the test host's way), fresh and warm.
- Not covered: Windows 11's newer kind of extension (IExplorerCommand, the items of packaged apps) and the static
  verbs from `shell` keys are part of Windows' total, not timed one by one.

The measuring process times each extension on its own, not inside Explorer: the numbers show an extension's own
cost, not the order or the sharing of a real right-click. Timing them inside the real right-click was looked at:
Dexmenu could tell the extensions apart by which DLL calls InsertMenuItemW, but the time between those calls is not
the extension's time (one that adds nothing is never seen), so it is not done.

### 3.2 The right-clicks

- At each right-click it shows, the DLL appends one entry to `%LOCALAPPDATA%\Dexmenu\timings.json`: the time, the
  program (its exe), the kind, the time from Dexmenu's handler being asked (QueryContextMenu) to the show call, and
  Dexmenu's steps (layout read, reading Windows' menu, files, submenus opened early, placing, measuring, drawing,
  showing), whether it was the first menu in that process, and Windows' menu instead when Dexmenu passed it on.
- Kept: the last 10 entries per program; older ones dropped when written. A fixed number for now, not a setting.
- Written always, not only with tracing on: one small write after the menu shows. The trace log keeps its own line.

### 3.3 The page

- A Diagnostics page in the main window, as its other pages.
- Extensions: a table per kind (name, file, fresh and warm times, items), slowest first, with Windows' total above
  it; a Measure button runs the measuring process; the result is kept until measured again.
- Right-clicks: a table per program: the last entries, and per program the middle value of the time to show and of
  Dexmenu's own time. A first menu in a process is marked, as it is slower.

### 3.4 The timing already built

The log's times carry milliseconds. With tracing on, Dexmenu logs how long reading the layout took and, once the menu
shows, each step (`menu shown, ms: init .. read .. files .. submenus .. place .. window .. measure .. draw .. show ..`).
The test host prints how long binding the items and Windows' QueryContextMenu took.

### 3.5 Tests

- Measuring process: run on the sample of each kind; every registered handler in the result, with its times or why
  not (blocked, failed to load, hanging); Dexmenu's own handler among them.
- Right-click timings: the test host's right-click writes an entry with every step; the file kept to its limit.
- The page: shown with a measured result and with none; with a timings file and with none.
- Switching off: a test extension (or a harmless one) blocked for the user, then the test host's menu built: the
  handler not loaded and its items not there; switched on again: back. This is also the check that Windows honours
  the user's list.
- Hang setting: a handler that does not return within the setting is stopped and shown as hanging; Stop ends the
  current one by hand.

### 3.6 Switching an extension off

- Each handler in the Extensions table has a switch. Off: its CLSID is added to Windows' blocked list for the user,
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked` (a value named by the CLSID); on:
  the value removed. No admin rights needed.
- The page says that this changes every program's right-click, not only Dexmenu's, and that a program already
  running (Explorer) may keep the extension until it restarts.
- Only extensions the user switched off from the page are listed as such and can be switched on there; one on the
  blocked list by other means (the machine's list in HKLM, a policy) is shown as blocked, without a switch.
- Dexmenu's own handler has no switch.
- Whether Windows honours the user's list is [not yet checked]: the first part built checks it (3.5). If it does not,
  the page shows the blocked state and no switch.

## 4. Open questions

None.
