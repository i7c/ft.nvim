## Purpose

Lets users create and update tasks inside Neovim, without leaving the
editor, by driving the `ft` CLI through the plugin's `rpc` seam.

## ADDED Requirements

### Requirement: Create task at cursor line

The plugin SHALL create a new task in the current buffer at the cursor's
line, pushing existing content down. The description SHALL be prompted via
`vim.ui.input`; when the current line has non-whitespace content, the
prompt SHALL be pre-filled with that text (trimmed) so confirming
"turns the current line into a task". Creating a duplicate task SHALL
succeed (no error). After a successful create, the buffer SHALL reload
from disk and the cursor SHALL be placed on the newly created task line.

#### Scenario: Create on an empty line

- **WHEN** the user invokes create with the cursor on an empty line and
  enters "Buy milk" in the prompt
- **THEN** a task line `- [ ] Buy milk` is inserted at the cursor line,
  existing content is pushed down, and the cursor lands on the new task

#### Scenario: Pre-fill from current line

- **WHEN** the cursor is on a non-empty line "Water plants" and the user
  invokes create and confirms the pre-filled prompt
- **THEN** the description prompt is pre-filled with "Water plants" and
  the resulting task line is inserted at the cursor line, pushing the
  original line down

#### Scenario: Duplicate create is allowed

- **WHEN** the user creates a task whose description and dates duplicate
  an existing task in the same file
- **THEN** the create still succeeds and a second identical task line is
  inserted (no error, no prompt)

#### Scenario: Create outside a vault

- **WHEN** the user invokes create while the current buffer is not inside
  a discovered vault
- **THEN** the operation aborts with an error notification and no ft
  command is run

### Requirement: Inline due date syntax

The description prompt SHALL accept an inline `due:<value>` token
mirroring the ft TUI quickline grammar: whitespace-delimited,
case-insensitive prefix, `\due:...` escaped to a literal description
token. The token's value SHALL be passed verbatim to `ft tasks create
--due` so ft resolves relative (`+2d`), keyword (`today`), ISO, and
natural-language dates into the task line's ISO due date; Lua SHALL NOT
compute or resolve dates itself. A repeated `due:` or an empty `due:`
value SHALL abort the create with an error notification.

#### Scenario: Relative due date

- **WHEN** the user creates a task with the description "Write report
  due:+2d"
- **THEN** the task line contains a due date exactly two days from
  today in ISO form and the description on the line is "Write report"

#### Scenario: Keyword due date

- **WHEN** the user creates a task with the description "Call dentist
  due:today"
- **THEN** the task line contains today's date in ISO form

#### Scenario: Escaped due token

- **WHEN** the user creates a task with the description "Send mail
  \due:tomorrow"
- **THEN** the whole string "Send mail due:tomorrow" becomes the task
  description and no due date is set

#### Scenario: Repeated due token

- **WHEN** the user creates a task with the description "Foo due:today
  due:friday"
- **THEN** the create aborts with an error notification and no task is
  inserted

### Requirement: Mark task done

The plugin SHALL mark the task under the cursor done by running
`ft tasks complete` with a `<file>:<line>` selector for the current
buffer and cursor line. Marking an already-done task SHALL do nothing
harmful: an info notification, no error. After success the buffer SHALL
reload from disk.

#### Scenario: Complete the task under the cursor

- **WHEN** the cursor is on an open task line and the user invokes done
- **THEN** `ft tasks complete <relpath>:<line>` runs, the buffer reloads,
  and the line shows the task as done

#### Scenario: Already done is idempotent

- **WHEN** the cursor is on a task already marked done and the user
  invokes done
- **THEN** no error is raised; the user sees an info notification and the
  file is left untouched

#### Scenario: Cursor on a non-task line

- **WHEN** the cursor is on a line that is not a task and the user
  invokes done
- **THEN** the user sees a warning notification from ft's own error and
  the file is left untouched

### Requirement: Cancel task

The plugin SHALL mark the task under the cursor cancelled by running
`ft tasks cancel` with a `<file>:<line>` selector for the current buffer
and cursor line. Cancelling an already-cancelled task SHALL be a no-op:
ft's CLI already treats it as success (exit 0, no file change), so the
plugin reloads and raises no error. After success the buffer SHALL
reload from disk.

#### Scenario: Cancel the task under the cursor

- **WHEN** the cursor is on an open task line and the user invokes cancel
- **THEN** `ft tasks cancel <relpath>:<line>` runs, the buffer reloads,
  and the line shows the task as cancelled

#### Scenario: Already cancelled is a no-op

- **WHEN** the cursor is on a task already cancelled and the user invokes
  cancel
- **THEN** no error is raised; ft's CLI exits 0 and the file is left
  untouched

### Requirement: Save before mutating

Before any mutating ft command (create, done, cancel) SHALL run, the
current buffer SHALL be written to disk. If the write fails (e.g.
read-only buffer, unnamed buffer), the operation SHALL abort with an
error notification and no ft command SHALL run.

#### Scenario: Modified buffer is saved first

- **WHEN** the buffer has unsaved changes and the user invokes create
- **THEN** the buffer is written to disk before the ft command runs, and
  ft operates on the saved content

#### Scenario: Failed write aborts

- **WHEN** the buffer cannot be written (read-only or unnamed) and the
  user invokes a task operation
- **THEN** the operation aborts with an error notification and no ft
  command runs

### Requirement: Reload preserves undo history

After a successful mutation the plugin SHALL reload the buffer to the
on-disk content in a way that preserves the buffer's undo history:
undo must return to the pre-mutation buffer state rather than being
wiped. The reload SHALL mark the note index cache dirty so derived
data is rebuilt.

#### Scenario: Undo survives a task operation

- **WHEN** the user performs an operation with existing undo history in
  the buffer
- **THEN** the undo tree still contains the pre-operation states and the
  buffer's undo history is not wiped

### Requirement: Commands and keymaps

The plugin SHALL expose `:FtTaskCreate`, `:FtTaskDone`, and
`:FtTaskCancel` user commands. It SHALL configure per-buffer keymaps
under `tasks.keymaps` with defaults create `<leader>tt`, done
`<leader>td`, cancel `<leader>tc`; setting any entry to `false` SHALL
disable that keymap. Commands SHALL work regardless of keymap config.

#### Scenario: Default keymaps are set

- **WHEN** a markdown buffer inside a vault is opened with default config
- **THEN** `<leader>tt`, `<leader>td`, and `<leader>tc` are mapped to the
  create, done, and cancel operations

#### Scenario: A keymap is disabled

- **WHEN** the user sets `tasks.keymaps.cancel = false` and opens a
  markdown buffer inside a vault
- **THEN** `<leader>tc` is not mapped while the other two remain

### Requirement: Errors are surfaced without crashing

When an ft task command fails, the plugin SHALL decode the structured
error output and show it via `vim.notify`; a missing ft binary SHALL
show the existing rpc error and never crash the session.

#### Scenario: ft error is notified

- **WHEN** an ft task command exits non-zero (e.g. "line not found",
  "not a task", "line changed on disk")
- **THEN** the plugin shows an error notification with ft's message and
  the buffer is left untouched

#### Scenario: Missing binary

- **WHEN** no ft binary is available and the user invokes a task command
- **THEN** an error notification explains the missing CLI tool and no
  buffer change occurs
