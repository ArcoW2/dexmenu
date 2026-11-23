# Plan 14: A note that shows a file

Status: not started; see Status.

- 2026-11-23: draft.

Builds on plan 02 3.3 (a note: text in the menu, no button) and plan 03 3.6 (a note's style and font, and its
`{date}` and `{time}` placeholders, `FillNote`).

## 1. What this is about

A note's text is what the layout says, with at most the date and the time filled in. A note that shows what a file
holds would make it a reminder or a status line: a reminder the user or another program writes, a timer's state,
today's to-do. The menu must stay as crisp and fast as it is: no markup, no waiting.

## 2. The solution, in brief

A note's text may hold `{file:<path>}`, filled in each time the menu opens with what the file holds, as plain text,
at most a set number of bytes. A file is read only from a local drive, through a small cache that reads it again
only when it changed; a file that cannot be read shows nothing. The editor's note gets a button to pick a file and a
field for the byte limit; the preview shows the note filled in.

## Status

### Built

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| File | `{file:<path>}` in `FillNote`: environment variables in the path, a local drive only, at most the note's byte limit, decoded as UTF-8 or UTF-16 by its BOM, cut at a whole line or character, `...` when cut | -- | 3.1 |
| Cache | each file's text kept by its path, time written and size; read again only when those changed | File | 3.2 |
| Editor | a "File..." button inserting `{file:<path>}`; a "File bytes" field | File | 3.3 |
| Tests | 3.5 | -- | 3.5 |

## 3. Details

### 3.1 A file

- `{file:<path>}` in a note's text: the file's text in its place, filled by `FillNote` beside `{date}` and `{time}`
  (the same braces, `{{` and `}}`, as typed when unknown). The path may hold environment variables
  (`%APPDATA%\Reminders\today.txt`); a relative path is taken from the layouts folder.
- At most the note's byte limit is read (`"fileBytes"` on the note; its default and maximum are an open question).
  Decoded as UTF-16 when it starts with a UTF-16 BOM, else as UTF-8 (with or without BOM); bytes that are not UTF-8
  show as the replacement character. When the file is longer than the limit, the text is cut at the last whole line
  within it (or the last whole character when the first line is longer), followed by `...`.
- Plain text: line breaks are kept, tabs become spaces, other control characters are left out. No markup.
- Not read, the placeholder shows nothing: a file that is not there, cannot be opened (locked, no access), or is not
  on a local fixed drive (a network path, a UNC path, a removable or optical drive). A note that ends up empty is
  shown as an empty note is now (a space).

### 3.2 Speed

- A right-click must not wait on a file. Only local fixed drives are read, and only the first bytes. A cache in the
  DLL keeps each file's text by its path, its time written and its size; a menu opening reads the file's attributes
  (one call) and the file only when those changed.
- The preview fills its notes the same way, so what the editor shows is what the menu will show.

### 3.3 The editor

- Beside the note's Text: a "File..." button that asks for a file (the settings app's file dialog) and inserts
  `{file:<path>}` at the cursor, the path with `%APPDATA%` or `%USERPROFILE%` in it where it starts with one. The
  Text field's hint names `{file:<path>}` beside the date and time.
- A "File bytes" field: the byte limit, empty the default.
- The cards view shows the note's text as typed; the preview shows it filled in.

### 3.4 What does not work, and why

- Running a program or a script to make a note's text: left out; a right-click must never start a process. A program
  that wants its state in the menu writes a file, and the note shows it.
- A note that follows its file while the menu stays open: left out; the file is read when the menu opens.

### 3.5 Tests

- Unit tests: a file read (UTF-8 with and without BOM, UTF-16); cut at the byte limit on a whole line with `...`; a
  first line longer than the limit cut on a whole character; environment variables and a relative path; a missing
  file, a locked file and a network path giving nothing; the cache reading the file again only after it changed; a
  note's size following its filled text.
- Editor self-test: the File... button's insert (a path under `%APPDATA%` written with the variable); the byte limit
  field written and cleared.
- By hand: a note with a reminder file at a right-click; the file changed and the next right-click showing it.

## 4. Open questions

1. A "timer" in a note: is that a file another program keeps up to date (the note just shows it, as planned), or
   should Dexmenu count down itself (a placeholder showing the time left until a moment)?
2. The byte limit: what default and what maximum for `"fileBytes"`?
3. A file on a network drive: always skipped (as planned, so a slow or lost connection never holds up a right-click),
   or allowed per note with a short time limit?

## 5. Not used

## 6. As built
