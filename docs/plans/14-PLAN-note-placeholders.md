# Plan 14: A note that shows a file, the time or the date

Status: not started; see Status.

- 2026-11-23: draft.

Builds on plan 02 3.3 (a note: text in the menu, no button) and plan 03 3.6 (a note's style and font).

## 1. What this is about

A note's text is fixed: what the layout says. A note that shows something that changes would make it useful as a
reminder or a status line: the current time or date, or what a file holds (a reminder another program or the user
writes, a timer's state, today's to-do). The menu must stay as crisp and fast as it is: no markup, no waiting.

## 2. The solution, in brief

A note's text may hold placeholders in braces, filled in each time the menu opens: `{time}` and `{date}` (in
Windows' own short formats, or a format given after a colon) and `{file:<path>}` (what the file holds, as plain
text, at most a set number of bytes). A file is read only from a local drive, through a small cache that reads it
again only when it changed; a file that cannot be read shows nothing. The editor's note field lists the placeholders
and has a button to pick a file; the preview shows the note filled in.

## Status

### Built

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Placeholders | `{time}`, `{date}`, with an optional format; `{{` and `}}` for a brace; an unknown placeholder shown as typed | -- | 3.1 |
| File | `{file:<path>}`: environment variables in the path, a local drive only, at most the note's byte limit, decoded as UTF-8 or UTF-16 by its BOM, cut at a whole character and line, `...` when cut; a cache by path and time written | -- | 3.2; 3.3 |
| Editor | the note field's hint listing the placeholders; a "File..." button inserting `{file:<path>}`; the byte limit field | Placeholders | 3.4 |
| Tests | 3.6 | -- | 3.6 |

## 3. Details

### 3.1 Placeholders

- In a note's text (`"note"`), a placeholder is `{name}` or `{name:argument}`. `{{` and `}}` are a literal brace.
  An unknown name, or a brace without its closing one, is shown as typed, so a note without placeholders reads as
  before.
- `{time}`: the time the menu opens, in Windows' short time format (the user's regional settings). `{time:<format>}`:
  in that format, as Windows' time pictures (`HH:mm`, `h:mm tt`).
- `{date}`: the date, in Windows' short date format. `{date:<format>}`: as Windows' date pictures (`dddd d MMMM`,
  `yyyy-MM-dd`).
- Filled in when the menu (or a submenu) is built, in the DLL, before it is measured: the filled text decides the
  note's size as any text does. The menu does not change while it is open.

### 3.2 A file

- `{file:<path>}`: the file's text in place of the placeholder. The path may hold environment variables
  (`%APPDATA%\Reminders\today.txt`). A relative path is taken from the layouts folder.
- At most the note's byte limit is read (`"fileBytes"` on the note; the default and the maximum are an open
  question). Decoded as UTF-16 when it starts with a UTF-16 BOM, else as UTF-8 (with or without BOM); bytes that are
  not UTF-8 are shown as the replacement character. When the file is longer than the limit, the text is cut at the
  last whole line within it (or the last whole character when the first line is longer), followed by `...`.
- Plain text: line breaks are kept, tabs become spaces, other control characters are left out. No markup.
- Not read, the placeholder shows nothing: a file that is not there, cannot be opened (locked, no access), or is not
  on a local fixed drive (a network path, a UNC path, a removable or optical drive). A note that ends up empty is
  shown as an empty note is now (a space).

### 3.3 Speed

- A right-click must not wait on a file. Only local fixed drives are read, and only the first bytes. A cache in the
  DLL keeps each file's text by its path, its time written and its size; a menu opening reads the file's attributes
  (one call) and the file only when those changed.
- The preview fills its notes the same way, so what the editor shows is what the menu will show.

### 3.4 The editor

- The note's Text field gets a hint under it listing the placeholders (`{time}`, `{date}`, `{time:HH:mm}`,
  `{date:dddd d MMMM}`, `{file:<path>}`), and a "File..." button that asks for a file (the settings app's file
  dialog) and inserts `{file:<path>}` at the cursor, the path with `%APPDATA%` or `%USERPROFILE%` in it where it
  starts with one.
- A "File bytes" field: the byte limit, empty the default.
- The cards view shows the note's text as typed (with its placeholders); the preview shows it filled in.

### 3.5 What does not work, and why

- A note that updates while the menu stays open (a clock that ticks) needs a timer in the menu window and a new
  measure each tick, as the note's size can change. Left out of this plan unless the open question says otherwise.
- Markup (markdown, bold parts) in a note: left out for speed and crispness (plan 03 3.6); a note's font and style
  apply to the whole note.
- Running a program or a script to make a note's text: left out; a right-click must never start a process. A program
  that wants its state in the menu writes a file, and the note shows it.

### 3.6 Tests

- Unit tests: each placeholder filled; a format; `{{` and `}}`; an unknown placeholder and an unclosed brace shown
  as typed; a file read (UTF-8 with and without BOM, UTF-16), cut at the byte limit on a whole line with `...`, a
  first line longer than the limit cut on a whole character; a missing file, a locked file and a network path giving
  nothing; the cache reading the file again only after it changed; a note's size following its filled text.
- Editor self-test: the File... button's insert (a path under `%APPDATA%` written with the variable); the byte limit
  field written and cleared.
- By hand: a note `{date:dddd d MMMM} {time}` and a note with a reminder file at a right-click; the file changed and
  the next right-click showing it.

## 4. Open questions

1. Should a note with `{time}` tick while the menu is open (a timer redrawing it each minute or second), or is the
   time the menu opened enough?
2. A "timer" in a note: is that a file another program keeps up to date (the note just shows it, as planned), or
   should Dexmenu count down itself (a placeholder such as `{until:17:30}` showing the time left)?
3. The byte limit: what default and what maximum for `"fileBytes"`?
4. A file on a network drive: always skipped (as planned, so a slow or lost connection never holds up a right-click),
   or allowed per note with a short time limit?

## 5. Not used

## 6. As built
