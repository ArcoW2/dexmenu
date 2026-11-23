# Plan 14: A note that shows a file

Status: executed; see Status.

- 2026-11-23: draft.
- 2026-11-23: executed.

Builds on plan 02 3.3 (a note: text in the menu, no button) and plan 03 3.6 (a note's style and font, and its
`{date}` and `{time}` placeholders, `FillNote`).

## 1. What this is about

A note's text is what the layout says, with at most the date and the time filled in. A note that shows what a file
holds would make it a reminder or a status line: a reminder the user or another program writes, a timer's state,
today's to-do. The menu must stay as crisp and fast as it is: no markup, no waiting.

## 2. The solution, in brief

A note's text may hold `{file:<path>}`, filled in each time the menu opens with what the file holds, as plain text,
at most 320 characters (a small paragraph). A file is read only from a local fixed drive, within half a second,
through a small cache that reads it again only when it changed; a file that cannot be read in time shows nothing. A
note says whether it shows when it ends up empty. The editor's note gets a button to pick a file and the empty
choice; the preview shows the note filled in.

## Status

### Built

| Part | What | Reference |
|---|---|---|
| File | `{file:<path>}` in `FillNote`: environment variables in the path, a relative path from the layouts folder, a local fixed drive only, at most 320 characters, decoded as UTF-8 or UTF-16 by its BOM, cut at a whole line or character, `...` when cut | 3.1; 6.1 |
| Cache | each file's text kept by its path, time written and size; read again only when those changed; a read that takes over 0.5 s gives nothing | 3.2; 6.1 |
| Empty note | `"empty": "hide"` on a note: left out when its filled text is empty; shown (a space) by default | 3.1; 6.1 |
| Editor | a "File..." button inserting `{file:<path>}` at the cursor (AppData and the profile written as variables); the "When empty" choice; the Text field's hint and tooltip | 3.3; 6.1 |
| Tests | unit tests, the editor's self-test, the preview captured | 3.5; 6.1 |

### Not yet built

## 3. Details

### 3.1 A file

- `{file:<path>}` in a note's text: the file's text in its place, filled by `FillNote` beside `{date}` and `{time}`
  (the same braces, `{{` and `}}`, as typed when unknown). The path may hold environment variables
  (`%APPDATA%\Reminders\today.txt`); a relative path is taken from the layouts folder.
- At most 320 characters are shown: a small paragraph, about four lines of 80. As bytes that is 320 for plain ASCII
  and up to 1280 (UTF-8 takes 1 to 4 bytes a character, UTF-16 2 or 4), so the first 1280 bytes are read and counted
  out in characters; no setting per note. Decoded as UTF-16 when it starts with a UTF-16 BOM, else as UTF-8 (with or without BOM); bytes that are not UTF-8
  show as the replacement character. When the file holds more, the text is cut at the last whole line
  within it (or the last whole character when the first line is longer), followed by `...`.
- Plain text: line breaks are kept, tabs become spaces, other control characters are left out. No markup.
- Not read, the placeholder shows nothing: a file that is not there, cannot be opened (locked, no access), or is not
  on a local fixed drive (a network path, a UNC path, a mapped network drive, a removable or optical drive), or takes
  longer than half a second to read.
- **When empty:** a note whose filled text is empty (no text, or a file giving nothing) is shown as an empty note is
  now (a space), or, with `"empty": "hide"`, left out of the menu.

### 3.2 Speed

- A right-click must not wait on a file. Only local fixed drives are read, and only the first bytes; the read runs on
  a thread of its own and is waited for half a second at most (then the note shows nothing, and the read's result,
  when it comes, is dropped). A cache in the
  DLL keeps each file's text by its path, its time written and its size; a menu opening reads the file's attributes
  (one call) and the file only when those changed.
- The preview fills its notes the same way, so what the editor shows is what the menu will show.

### 3.3 The editor

- Beside the note's Text: a "File..." button that asks for a file (the settings app's file dialog) and inserts
  `{file:<path>}` at the cursor, the path with `%APPDATA%` or `%USERPROFILE%` in it where it starts with one. The
  Text field's hint names `{file:<path>}` beside the date and time.
- A "When empty" choice: shown (a space), or left out.
- The cards view shows the note's text as typed; the preview shows it filled in.

### 3.4 What does not work, and why

- Running a program or a script to make a note's text: left out; a right-click must never start a process. A program
  that wants its state in the menu writes a file, and the note shows it.
- A note that follows its file while the menu stays open: left out; the file is read when the menu opens.
- A timer or a countdown kept by Dexmenu: left out; the menu is not interactive and runs nothing. A timer another
  program keeps writes its state to a file, and the note shows that file.

### 3.5 Tests

- Unit tests: a file read (UTF-8 with and without BOM, UTF-16); cut at 320 characters on a whole line with `...` (also
  when its characters take 3 or 4 bytes each); a first line longer than that cut on a whole character; environment variables and a relative path; a missing
  file, a locked file and a network path giving nothing; an empty note left out with `"empty": "hide"`, shown
  without it; the cache reading the file again only after it changed; a
  note's size following its filled text.
- Editor self-test: the File... button's insert (a path under `%APPDATA%` written with the variable).
- By hand: a note with a reminder file at a right-click; the file changed and the next right-click showing it.

## 4. Open questions

None.

## 5. Not used

## 6. As built

### 6.1 How it was built and tested

- `NoteFile` (Dexmenu.Layout) reads a file for `{file:<path>}`: UNC paths and drives that `GetDriveType` does not call
  fixed are skipped before any read; the file's attributes give the cache key; a miss starts a thread
  (`TNoteRead`, kept alive by the thread until it ends) that reads the first 1280 bytes, waited for 500 ms. Too slow,
  locked or gone: nothing, not cached, tried again next time.
- Decoding: a UTF-8 character cut by the 1280-byte read is left out before decoding (Delphi's UTF-8 decoder raises on
  it rather than giving a replacement character: caught by the unit test with 3-byte characters); bytes that are
  still not UTF-8 are read in the system's code page rather than fail.
- A note fills its text when it is placed (`PlaceLines`), so an empty one set to hide is left out there; measuring
  and drawing use that text.
- Tested: unit tests (UTF-8 with and without BOM, UTF-16, control characters, the 320 cut at a whole line, one long
  line, 3-byte characters, a missing file, a network path, a locked file, the cache reading a changed file again, an
  empty note hidden and shown), the editor's self-test (a picked path under AppData and the profile written as
  variables), and the preview captured as a picture (the date, the time and a reminder file's three lines in a
  styled note; an empty note set to hide left out). The 0.5 s limit is not tested with a slow drive: none here.
