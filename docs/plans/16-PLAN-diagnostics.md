# Plan 16: Diagnostics: where the time of a right-click goes

Status: partly executed; see Status.

- 2026-11-26: draft.
- 2026-11-26: partly executed: everything but the check in a real right-click.
- 2026-11-26: partly executed: the profile of Windows' whole menu; packaged apps' extensions.

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
be switched off there, and on again. Windows' whole menu is also profiled: sampled while it is built, so its time
shows per call path and per DLL, with the processes Windows starts for it; packaged apps' extensions (Windows 11's,
each run in a process of its own) are listed and timed with the others. Right-clicks: the last ten right-clicks Dexmenu showed per program (Explorer,
Foldex, a dialog), with the time from Dexmenu's handler being asked to the menu shown, and Dexmenu's own steps. The
DLL writes these timings to a small file; the page reads it.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| Timing in the log | ms in the log; Dexmenu's steps logged with tracing on; the test host's timings | 3.4 |
| Measuring process | each handler of a kind timed (create, Initialize, QueryContextMenu), fresh and warm | 3.1; 6.1 |
| Right-click timings | the DLL keeps the last right-clicks' timings per program in a file | 3.2; 6.2 |
| Diagnostics page | the main window's page with both tables and a Measure button | 3.3; 6.3 |
| Switching off | a handler switched off and on from the page (Windows' blocked list for the user) | 3.6; 6.4 |
| Hang setting | how long one handler may take before it is stopped, a setting | 3.1; 6.1 |
| Tests | all but the real right-click | 3.5; 6.5 |
| Profile | Windows' whole menu sampled: call paths, other threads, DLLs on the stack; on or off on the page | 3.7; 6.6 |
| Packaged extensions | packaged apps' menu extensions listed, timed and switched; the processes started for the menu | 3.8; 6.7 |

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Real right-click check | a right-click in Explorer and Foldex writes its entry, shown on the page | the new DLL installed in C:\Win32App\Dexmenu | 3.5; 6.5 |

## 3. Details

### 3.1 The extensions

- The handlers come from the registry, as Windows finds them for the kind: `*`, `AllFilesystemObjects` and the
  sample file's type for a file; `Directory`, `Folder` and `AllFilesystemObjects` for a folder;
  `Directory\Background` for a background; `Drive`, `Folder` and `AllFilesystemObjects` for a drive. For a file also
  its extension's key, its ProgID, and `SystemFileAssociations` for the extension and for its perceived type. A
  handler on the blocked list is shown as blocked, not timed.
- The sample: a file and a folder the measuring process makes in a temp folder (a `.txt` file), the temp folder's
  background, the system drive. A handler that acts on a file's type only (Foxit on PDFs) is timed only with a file of
  that type; the page can be given a file of the user's choice to measure with.
- Each handler is timed in its own measuring process (the settings app started with an argument), so a handler that
  crashes or hangs does not take the app with it. How long one handler may take before it is stopped and shown as
  hanging is a setting on the page; its default is 10 s, far above the slowest one measured (6.1). While a measurement runs, the page shows how long the current handler has taken, with a Stop
  button that stops it by hand. Per handler: create (loading its DLL), Initialize, QueryContextMenu, fresh (first in the process) and
  warm (a second time in the same process), and the number of items it added.
- Windows' own total for the kind: the menu built the way Explorer builds it (the test host's way), fresh and warm.
- Packaged apps' extensions are timed too (3.8). Not covered one by one: the static verbs from `shell` keys and
  Windows' own parts; the profile (3.7) shows where their time goes.

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
- Written always, not only with tracing on: one small write once the menu has closed, so it costs the user nothing.
  The trace log keeps its own line.

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
- Windows honours the user's list: checked (6.4).

### 3.7 The profile of Windows' whole menu

The extensions timed one by one do not add up to Windows' whole menu: most of a warm right-click is spent elsewhere.
So the measuring process can sample Windows' whole menu while it is built (fresh and warm): about every millisecond
the building thread is paused, its call stack walked and the DLLs on it noted. Shown per build: the call paths (the
function the thread was in, then the DLLs that called it), what the process's other threads did while it waited, and
the DLLs on the stack, each the most first; an extension's own DLL named as that extension. A checkbox on the page
switches the profile on or off (on unless switched off); it adds a little to the times.

### 3.8 Packaged apps' extensions

Windows 11's menu extensions of packaged apps (IExplorerCommand: PowerToys, Notepad, OneDrive, VS Code, TortoiseGit's
newer menu) are not in the `shellex` keys: each app's manifest names them (FileExplorerContextMenus, per item type).
Windows runs each in a process of its own (a COM surrogate), started at a right-click when it does not run. They are
listed with the other extensions for the kinds their item types fit, timed as Windows uses them (started out of
process, then their title and state for the sample), and switched off and on through the same blocked list. Windows'
whole menu also lists the processes Windows started for it.

## 4. Open questions

None.

## 6. As built

### 6.1 The measuring process

- `Diagnostics.cs` in the settings app. `DexmenuSettings.exe --measure-handler <out> <kind> <sample> <clsid> <hang s>`
  times one handler twice in one process (fresh, then warm): CoCreateInstance, IShellExtInit.Initialize (with a data
  object of the sample; for a background the folder and no items), IContextMenu.QueryContextMenu, and the items it
  added. `--measure-menu <out> <kind> <sample> <hang s>` builds Windows' whole menu as the preview does
  (ShellMenu.Time: bind and QueryContextMenu), fresh and warm. Each writes JSON to the file.
- The hang limit is a watchdog in the measuring process: when the handler has not returned in time, it writes
  `"hanging": true` and ends the process (exit 3). The app also stops a process that runs 15 s past the limit
  (one that never gets to the handler). The limit is `settings.json` `"diagnostics"."hangSeconds"`, default 10 s.
- Measured on this machine (the page, 2026-11-26): for a file, the slowest handler loaded fresh took 109 ms (EPP,
  Defender) and Windows' whole menu 1354 ms fresh and 1301 ms warm; for a folder's empty part the whole menu took
  716 ms fresh and 258 ms warm. 10 s is a hang, not a slow extension. Starting a measuring process costs about
  0.2 s, so a file's handlers took 10 s in all.
- Warm, the handlers of a file together take little, while Windows' whole menu still takes over a second: most of a
  warm right-click is in what is not timed one by one (3.1: the static verbs and Windows 11's newer extensions).

### 6.2 The right-clicks' timings

- `Dexmenu.Timings` in the DLL. The hook notes when Dexmenu's handler was asked (NoteMenu) and, at the show call, the
  wait since then; the session keeps its steps (`init`, `read`, `files`, `submenus`, `place`, `window`, `measure`,
  `draw`, `show`) after the hook's `layout`. A right-click Dexmenu passes to Windows' menu gets an entry with why
  (Shift held, set to None, the layout not usable), no steps but the layout's.
- Written to `%LOCALAPPDATA%\Dexmenu\timings.json` (DEXMENU_TIMINGS_FILE: the tests) under a named mutex, as several
  programs write it; the last 10 per program kept, a program's path compared without case.

### 6.3 The page

- The main window's fourth tab, Diagnostics. Extensions: the kind, File... (a file of the user's own, for a file's
  right-click), Measure, Stop (while measuring; it stops the extension being measured, the others are measured
  still), "Stop an extension after ... s". While measuring: which one and how long it has taken, every 0.1 s. Then
  the kept result (`%LOCALAPPDATA%\Dexmenu\measured.json`, per kind): when and on what, Windows' whole menu fresh
  and warm, and per extension its DLL's name (its path on hover), fresh and warm (load, initialize and build on
  hover), items and the switch, slowest first. The blocked state is read again whenever the page is shown.
- Right-clicks: per program (the most recent first) its middle wait and middle Dexmenu time, then its entries,
  newest first: when, the kind, Dexmenu's or Windows' menu (and why), the wait, Dexmenu's time, its steps. Read again
  when the tab is shown and whenever the file changes.

### 6.4 Switching off

- Off: the CLSID as a value in the user's blocked list (its name as the data) and in `settings.json`
  `"diagnostics"."switchedOff"`; on: both removed. Dexmenu's own handler, and one blocked by other means, have no
  switch.
- Checked by hand: 7-Zip on the user's list, then the test host's menu for a .txt file: no 7-Zip item; off the list
  again: back. The test's blocked list key did not exist before and was removed after.

### 6.5 Tests

- Unit (DLL): an entry with its wait, first and steps, no "why" for Dexmenu's menu; the last ones kept per program
  (case ignored), the oldest dropped; Windows' menu with why and no wait.
- The page, run by script on its own data folder (WebView2 driven over its debug port): the right-clicks from a
  sample timings file grouped and ordered per program with their middle values; a background and a file measured,
  every handler listed with its times or why not (one not loaded); 7-Zip switched off from the page (the blocked
  value and the settings list written, its row "switched off") and on again (both removed); Stop during Windows'
  whole menu (it shows "stopped", the extensions after it measured); the hang limit at 0.5 s on Windows' whole menu
  (exit 3, "hanging").
- Not yet: a real right-click in Explorer or Foldex writing its entry. They run the installed DLL, which is older
  than this build.

### 6.6 The profile

- `Profiler.cs`: a sampler thread on a high-resolution waitable timer (Windows 11 ignores timeBeginPeriod for a
  process without a visible window: with Sleep(1) it got a sample every 15 ms or so). While the thread is paused only
  system calls and reads of memory: the stack is walked with RtlVirtualUnwind and the unwind data read from the DLL's
  own headers (no RtlLookupFunctionEntry, no loader lock); the DLL's name and the nearest export are read once it runs
  again. While the building thread waits, the process's other threads are sampled too (their stacks' bounds from
  their TEB; idle pool threads and .NET's own left out).
- `--measure-menu ... profile` samples the fresh and the warm build; settings.json `"diagnostics"."profile"`.
- What it showed here, for a .txt file (the page, 2026-11-26): the fresh build waited about 0.45 s in Windows.Storage
  for a worker thread that was in a COM call to another process; the slow warm builds waited about 0.8 - 1 s in such a
  call themselves (`NtUserMsgWaitForMultipleObjectsEx < combase < RPCRT4 < combase < Windows.Storage < SHELL32`).
  Warm builds right after another one took about 0.25 - 0.45 s.

### 6.7 Packaged apps' extensions

- Found from the user's packages (`AppModel\Repository\Packages` in HKCU): the manifest in the package's root
  folder, or for a sparse package under `Program Files\WindowsApps\<package>`; the item types `*` and the file's
  extension for a file, `Directory` and `Folder` for a folder, `Directory\Background`, `Drive`. Shown as
  "<app> (<verb>) [app]".
- Timed in the measuring process: CoCreateInstance out of process (the start of its surrogate when none runs), then
  IExplorerCommand GetTitle and GetState; "*" when its process ran already.
- The processes started for Windows' whole menu: the COM surrogates (`dllhost /Processid:{clsid}`) running after a
  build and not before, named by their package (PackagedCom ClassIndex) or their AppID.
- What it showed here: for a file, Windows started seven processes for one menu (OneDrive, PowerToys File Locksmith,
  Image Resizer and PowerRename, Notepad, VS Code, TortoiseGit), each taking about 0.1 - 0.2 s to start (104 - 216 ms
  measured); together about the second the slow builds waited. They end soon after their last user, so they start
  again at a later right-click.
- Switching off: Notepad's on the user's blocked list, then Windows' whole menu built: its process was not started
  (it did not run before); off the list again after.
