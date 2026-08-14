# notes-export Specification

## Purpose

Lets users export a line range (or the whole note) of the current
buffer as clean CommonMark — frontmatter, `[!ft-source]` callout
headers, and wikilinks stripped by `ft notes export` — placed into
registers for pasting outside the vault.

## Requirements

### Requirement: Export a line range

The plugin SHALL export a 1-indexed inclusive line range of the current
buffer by running `ft notes export <vault-relative-path> -l A-B
--format <name>` through the rpc seam (which injects `--vault <root>`),
passing the exported text through unparsed. On success the text SHALL
be placed linewise into the configured registers and a notification
SHALL show the exported range and the format used. On failure no
register SHALL be written and the notification SHALL classify the
error. When no vault is discovered, the operation SHALL abort with an
error notification before any ft command runs.

#### Scenario: Export a line range

- **WHEN** the current buffer is a vault note, the user chooses the
  `commonmark` format, and exports lines 3–5
- **THEN** `ft notes export <rel> -l 3-5 --format commonmark` runs, the
  returned clean CommonMark is placed linewise into the configured
  registers, and a notification reports the exported range and format

#### Scenario: Export a line range in slack format

- **WHEN** the current buffer is a vault note, the user chooses the
  `slack` format, and exports lines 3–5
- **THEN** `ft notes export <rel> -l 3-5 --format slack` runs and the
  returned Slack mrkdwn text is placed linewise into the configured
  registers

#### Scenario: Failed export leaves registers untouched

- **WHEN** the export command exits non-zero (e.g. the range exceeds the
  file's line count)
- **THEN** no register is written and the previous register contents are
  preserved

#### Scenario: Outside a vault

- **WHEN** the current buffer is not inside a discovered vault and the
  user invokes export
- **THEN** the operation aborts with an error notification and no ft
  command runs

### Requirement: Format selection

Before any export runs, the plugin SHALL resolve the export format:
when `export.format` is a known format (`commonmark` or `slack`) the
plugin SHALL use it directly without prompting; when `export.format` is
`'prompt'` (the default) or any other unrecognized value, the plugin
SHALL prompt the user to choose among the available formats via the
picker seam (which delegates to the user's configured picker), showing
each format's description. The prompt SHALL appear on every export
entry point — operator, visual, and `:FtExport` (whole-file and
ranged). Cancelling the prompt SHALL abort the operation silently: no
ft command runs and no register is written. The resolved format SHALL
be passed to ft as `--format <name>` and SHALL appear in the success
notification. The set of available formats is fixed at `commonmark`
(clean CommonMark) and `slack` (Slack mrkdwn), mirroring the consumed
CLI surface.

#### Scenario: Configured format skips the prompt

- **WHEN** the user sets `export.format = 'slack'` and exports a range
- **THEN** no prompt is shown, `--format slack` is passed, and the
  export completes with the Slack rendering

#### Scenario: Prompt with default format choice

- **WHEN** `export.format` is unset and the user exports a range
- **THEN** a picker prompt lists `commonmark` and `slack` with their
  descriptions, and choosing one exports with `--format <choice>`

#### Scenario: Prompt applies to every entry point

- **WHEN** the user invokes export via the operator (`gy` + motion),
  visual `gy`, or `:FtExport` (with or without a range)
- **THEN** the format prompt is shown in every case before any ft
  command runs

#### Scenario: Cancelling the prompt aborts silently

- **WHEN** the user cancels the format prompt
- **THEN** no ft command runs, no register is written, and no error is
  raised

#### Scenario: Success notification names the format

- **WHEN** an export succeeds with the `slack` format
- **THEN** the success notification shows the format, e.g.
  `ft: exported L1-2 (slack) → ", f, +`

### Requirement: Operator, visual, and command entry points

The plugin SHALL expose a normal-mode operator bound to
`export.keymaps.operator` (default `gy`) that takes a motion or text
object and exports the covered line range; in visual mode the same key
SHALL export the current selection's line span; the `:FtExport` command
SHALL export the whole buffer in normal mode, the selection in visual
mode, and an explicit range when given (`:3,6FtExport`). The operator
SHALL leave the cursor at the start of the exported range. Setting
`export.keymaps.operator` to `false` SHALL disable the keymaps while the
command still works.

#### Scenario: Operator with a paragraph motion

- **WHEN** the cursor is on a paragraph and the user presses `gy` then
  `ap`
- **THEN** the paragraph's line range is exported and the cursor lands
  on the range's first line

#### Scenario: Operator with a count motion

- **WHEN** the cursor is on line N and the user presses `gy` then `3j`
- **THEN** the range N–(N+3) is exported

#### Scenario: Visual selection

- **WHEN** the user visually selects lines 7–9 and presses `gy`
- **THEN** lines 7–9 are exported

#### Scenario: Command defaults to the whole buffer

- **WHEN** the user runs `:FtExport` in normal mode
- **THEN** the whole buffer is exported (no `-l` flag is passed)

#### Scenario: Command with an explicit range

- **WHEN** the user runs `:3,6FtExport`
- **THEN** lines 3–6 are exported

#### Scenario: Operator keymap disabled

- **WHEN** the user sets `export.keymaps.operator = false` and opens a
  markdown buffer inside a vault
- **THEN** no export keymap is mapped while `:FtExport` still works

### Requirement: Register placement

On success the exported text SHALL be placed into the unnamed register
`"`, the named register `f`, and the system clipboard `"+`, all
linewise, so plain `p` pastes the block. The named register `f` is the
same register quote writes — the two operators share it and the last
operation wins. The `export.registers` config SHALL allow disabling any
of the three (default all enabled). When the clipboard is unavailable
(nvim without `+clipboard` or a failing provider) the clipboard write
SHALL be skipped silently while the in-session registers are still set;
the success notification SHALL reflect which registers actually received
the text.

#### Scenario: Default register set

- **WHEN** an export succeeds with default config
- **THEN** the text is in `"`, `f`, and `"+` (linewise) and the
  notification lists all three

#### Scenario: Named register disabled

- **WHEN** the user sets `export.registers.named = false` and exports
  successfully
- **THEN** the text is in `"` and `"+` but not in `f`

#### Scenario: Clipboard unavailable

- **WHEN** nvim has no clipboard support and the user exports
  successfully
- **THEN** the text is in `"` and `f`, no clipboard error is raised,
  and the notification reflects the reduced register set

### Requirement: Save before exporting

Before the export command SHALL run, the current buffer SHALL be written
to disk when it has unsaved changes, so the exported lines match what
the user sees (export reads the working tree). If the write fails
(read-only buffer), the operation SHALL abort with an error notification
and no ft command SHALL run.

#### Scenario: Modified buffer is saved first

- **WHEN** the buffer has unsaved changes and the user exports a range
- **THEN** the buffer is written to disk before the ft command runs and
  the exported text reflects the on-screen content

#### Scenario: Failed write aborts

- **WHEN** the buffer cannot be written (read-only) and the user exports
- **THEN** the operation aborts with an error notification and no ft
  command runs

### Requirement: Errors are classified; empty output is legal

The plugin SHALL classify ft's errors: a line range outside the file
SHALL surface as a warning; a missing source file, an unreadable file,
and all other failures SHALL surface as errors. Export has no git
dependency, so there is no dirty-source path and the plugin SHALL NOT
run any git command. An empty export result (a range fully inside the
frontmatter, which ft strips) SHALL be treated as a successful export
that produced nothing: the plugin SHALL notify with an informational
message and SHALL NOT overwrite the registers.

#### Scenario: Range outside the file warns

- **WHEN** the exported range exceeds the file's line count
- **THEN** a warning notification shows ft's out-of-bounds message and
  no register is written

#### Scenario: Empty export leaves registers untouched

- **WHEN** the user exports a range fully inside the frontmatter
- **THEN** the command exits 0 with empty output, an informational
  notification is shown, and the previous register contents are
  preserved

#### Scenario: Missing ft binary

- **WHEN** no ft binary is available and the user exports
- **THEN** the rpc missing-binary error surfaces and no buffer or
  register change occurs
