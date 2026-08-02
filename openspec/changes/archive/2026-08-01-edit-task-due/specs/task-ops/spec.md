## ADDED Requirements

### Requirement: Edit task due date

The plugin SHALL edit the due date of the task under the cursor by
running `ft tasks edit` with a `<file>:<line>` selector for the current
buffer and cursor line and the prompted value passed verbatim as
`--due`. The prompt SHALL be shown via `vim.ui.input` and accept ft's
date syntax (relative `+2d`, keyword `today`, ISO, natural language) and
`none` to clear the due date; an empty input SHALL cancel without
running any command. Date resolution and line serialization SHALL stay
in ft (Lua never computes dates). After success the buffer SHALL reload
from disk. A line that matches no task SHALL surface a warning, and
other ft failures SHALL surface as errors, without changing the file.

#### Scenario: Set a relative due date

- **WHEN** the cursor is on a task and the user invokes due with the
  input "+2d"
- **THEN** `ft tasks edit <relpath>:<line> --due +2d` runs, the buffer
  reloads, and the task line shows a due date exactly two days from
  today in ISO form

#### Scenario: Clear the due date

- **WHEN** the cursor is on a task with a due date and the user invokes
  due with the input "none"
- **THEN** `ft tasks edit <relpath>:<line> --due none` runs, the buffer
  reloads, and the task line no longer shows a due date

#### Scenario: Empty input cancels

- **WHEN** the user dismisses the due prompt without entering a value
- **THEN** no ft command runs and the file is left untouched

#### Scenario: Cursor on a non-task line

- **WHEN** the cursor is on a line that is not a task and the user
  invokes due
- **THEN** the user sees a warning notification from ft's own error and
  the file is left untouched

#### Scenario: Invalid date is surfaced

- **WHEN** the user enters a value ft cannot parse as a date
- **THEN** the user sees an error notification with ft's message and the
  file is left untouched

### Requirement: Due command and keymap

The plugin SHALL expose `:FtTaskDue` and configure a per-buffer keymap
under `tasks.keymaps.due` with default `<leader>te`; setting it to
`false` SHALL disable the keymap while the command still works.

#### Scenario: Default due keymap is set

- **WHEN** a markdown buffer inside a vault is opened with default config
- **THEN** `<leader>te` is mapped to the due-date edit operation

#### Scenario: Due keymap is disabled

- **WHEN** the user sets `tasks.keymaps.due = false` and opens a
  markdown buffer inside a vault
- **THEN** `<leader>te` is not mapped while the command `:FtTaskDue`
  still works
