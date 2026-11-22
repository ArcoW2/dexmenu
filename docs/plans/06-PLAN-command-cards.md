# Plan 06: Command cards: a card that runs a command or a task

Status: not started; see Status.

- 2026-11-22: draft.

Builds on plan 02 (`02-PLAN-own-menu.md`: cards, the window, the editor). The details are to be worked out; this draft
holds the idea and the questions.

## 1. What this is about

Every card today shows items of Windows' menu, or holds cards, or is a note. A user also wants items Windows' menu
does not have: open a terminal in this folder, copy the selected paths in a form of their own, run a script on the
selected files, start a task they defined. Today that needs a shell extension or a registry entry per command.

## 2. The solution, in brief

A command card: a card of the layout that, when chosen, runs a command of the user's (a program with arguments, built
from what was right-clicked) or a task (Open questions 1, 2). It is placed, titled and drawn as any card; its command
is set in the editor.

## Status

### Built

| Part | What | Reference |
|---|---|---|

### Not yet built

| Part | What | Waits for | Reference |
|---|---|---|---|
| Command card | a card that runs a command or a task when chosen | Open questions | 3.1 |
| Editor | the command set in the card's panel | Command card | 3.2 |
| Tests | 3.3 | -- | 3.3 |

Moved out: Dexmenu's own items ("Edit menu...", "Windows' menu") as cards a layout places, built in plan 02 (3.6,
3.11) without the commands of this plan.

## 3. Details

### 3.1 The command card

- Chosen, the menu closes and the command runs (the program showing the menu gets no choice, as with Dexmenu's own
  items, plan 02 3.6).
- What it may use of the right-click: the selected paths, the folder, the kind (the handler knows them, as for the
  last right-click, plan 02).
- Shown only where it makes sense: Open question 4.
- Dexmenu's own items, "Windows' menu" and "Edit menu..." (plan 02 3.6, 3.11), are already cards a layout places
  (`"own"`); a command card works the same way with a command of the user's.

### 3.2 The editor

- "+ Command" beside "+ Card", "+ Divider", "+ Note"; its panel holds what it runs.

### 3.3 Tests

- To be set with the details.

## 4. Open questions

1. What can a command be: a program with arguments, a shell command (cmd, PowerShell), a URL, a Windows Terminal
   profile, a script file? Which first?
2. What is a "task": a saved command, several commands in a row, a Windows scheduled task, something else?
3. How are the right-clicked items put into the command: placeholders such as `{paths}`, `{folder}`, `{name}`; one
   run per item or one run for all; quoting?
4. When does a command card show: always, or only for some kinds of right-click, file types, or when its items exist
   (a rule-like condition)?
5. Run as the user only, or also "as administrator" (a UAC prompt) per command?
6. Feedback: a window for the output, a notification when it ends or fails, or nothing?
