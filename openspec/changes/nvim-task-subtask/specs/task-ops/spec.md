## ADDED Requirements

### Requirement: Create subtask under the task at the cursor

The plugin SHALL create a new task as an indented subtask of the task under
the cursor by running `ft tasks create` with `--parent <relpath>:<line>`,
where the selector is built from the current buffer's vault-relative path and
the cursor line captured when the operation is invoked. The plugin SHALL NOT
pass `--file`, `--under-heading`, `--at-line`, or `--append` (they conflict
with `--parent` at the ft CLI). Creating a duplicate subtask SHALL succeed
(`--force`). After a successful create the buffer SHALL reload from disk and
the cursor SHALL remain on the parent's line.

#### Scenario: Subtask under a childless parent

- **WHEN** the cursor is on a task with no children and the user invokes
  subtask with description "Buy milk"
- **THEN** a task line indented two spaces past the parent is inserted after
  it, the buffer reloads, and the cursor stays on the parent's line

#### Scenario: Subtask under a parent with children

- **WHEN** the cursor is on a task that already has indented children
- **THEN** the new subtask is indented to match the first child's leading
  whitespace verbatim (spaces or tabs) and appended after the parent's whole
  indented block

#### Scenario: Nested subtask goes one level deeper

- **WHEN** the cursor is on a subtask and the user invokes subtask
- **THEN** the new task becomes a child of that subtask (one level deeper),
  not a sibling of it

#### Scenario: Repeated invocation adds siblings

- **WHEN** the user creates a subtask and, without moving the cursor, invokes
  subtask again
- **THEN** a second subtask is added under the same parent, since the cursor
  stayed on the parent's line

#### Scenario: Duplicate subtask is allowed

- **WHEN** the new subtask's description and dates duplicate an existing task
  in the same file
- **THEN** the create still succeeds and a second identical subtask line is
  inserted

#### Scenario: Parent is captured at invocation

- **WHEN** the user moves the cursor to a different line while the description
  prompt is open, then confirms
- **THEN** the subtask is still created under the task that was under the
  cursor when the operation was invoked

### Requirement: Subtask prompt and inline due

The subtask description SHALL be prompted via `vim.ui.input` with an empty
default (no pre-fill). The prompt SHALL accept the same inline `due:<value>`
token as task create: the token is removed from the description and its value
passed verbatim to `--due`; `\due:...` escapes to a literal token; a repeated
or empty `due:` SHALL abort with an error notification.

#### Scenario: Prompt has no pre-fill

- **WHEN** the user invokes subtask on a task
- **THEN** the description prompt is shown empty

#### Scenario: Relative due date on a subtask

- **WHEN** the user enters "Write report due:+2d"
- **THEN** the subtask description is "Write report" and its line carries a
  due date exactly two days from today in ISO form

#### Scenario: Escaped due token

- **WHEN** the user enters "Send mail \due:tomorrow"
- **THEN** the whole string "Send mail due:tomorrow" becomes the subtask
  description and no due date is set

#### Scenario: Repeated due token aborts

- **WHEN** the user enters "Foo due:today due:friday"
- **THEN** the subtask create aborts with an error notification and no task
  is inserted

### Requirement: Subtask command and keymap

The plugin SHALL expose `:FtTaskSubtask` and SHALL configure a per-buffer
keymap under `tasks.keymaps.subtask` with default `<leader>ts`; setting it to
`false` SHALL disable the keymap while the command still works.

#### Scenario: Default subtask keymap is set

- **WHEN** a markdown buffer inside a vault is opened with default config
- **THEN** `<leader>ts` is mapped to the subtask operation

#### Scenario: Subtask keymap is disabled

- **WHEN** the user sets `tasks.keymaps.subtask = false` and opens a markdown
  buffer inside a vault
- **THEN** `<leader>ts` is not mapped while `:FtTaskSubtask` still works

### Requirement: Subtask failure modes are surfaced

When the cursor is not on a task, the plugin SHALL surface ft's `no tasks
match selector` error as a warning and SHALL leave the file untouched. When
no vault is discovered, the operation SHALL abort with an error notification
before running any ft command. When no ft binary is available, the plugin
SHALL surface the rpc error without crashing.

#### Scenario: Cursor on a non-task line

- **WHEN** the cursor is on a line that is not a task and the user invokes
  subtask
- **THEN** the user sees a warning notification with ft's own message and the
  file is left untouched

#### Scenario: Outside a vault

- **WHEN** the current buffer is not inside a discovered vault and the user
  invokes subtask
- **THEN** the operation aborts with an error notification and no ft command
  runs

#### Scenario: Missing binary

- **WHEN** no ft binary is available and the user invokes subtask
- **THEN** an error notification explains the missing CLI tool and no buffer
  change occurs
