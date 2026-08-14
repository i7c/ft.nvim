# notes-export Delta Spec — nvim-export-format-prompt

## MODIFIED Requirements

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

## ADDED Requirements

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
