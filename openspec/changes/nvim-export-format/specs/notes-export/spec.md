## ADDED Requirements

### Requirement: Format selection

The plugin SHALL support multiple export targets by passing
`--format <name>` to `ft notes export`. The effective format SHALL come
from the `export.format` config (`'commonmark'` default, `'slack'`
accepted) unless overridden per invocation. The operator (`gy`), the
visual key, and `:FtExport` without an argument SHALL use the
configured format. The plugin SHALL pass `--format <name>` only when
the effective format is not the CLI's default (`commonmark`); the
default path SHALL pass no format flag, keeping the existing argv
contract. `:FtExport` SHALL accept an optional format argument
(`:FtExport slack`, `:FtExport commonmark`) that overrides the
configured format for that invocation only, with the range/whole-file
defaults unchanged, and SHALL offer the known format names as command
completion. On success the notification SHALL include the format in
parentheses when it is not the CLI default (e.g.
`ft: exported L1-2 (slack) → ", f, +`). The version floor for format
selection is `MIN_FT_VERSION` 0.1.7: an older binary SHALL warn at
setup (existing soft check), and if a format flag is still requested of
it, the CLI's own error SHALL surface through the existing error
classifier — the plugin SHALL NOT validate format names itself, since
the accepted set is defined by the ft CLI's value enum.

#### Scenario: Default config passes no format flag

- **WHEN** the user configures no `export.format` (default
  `'commonmark'`) and exports a line range via `gy`
- **THEN** `ft notes export <rel> -l A-B --json-errors` runs with no
  `--format` flag, byte-identical to today's argv

#### Scenario: Configured slack format is passed

- **WHEN** the user sets `export.format = 'slack'` and exports a range
  via `gy`
- **THEN** `ft notes export <rel> --format slack -l A-B --json-errors`
  runs and the Slack mrkdwn text lands in the configured registers
  unmodified

#### Scenario: Per-invocation override on the command

- **WHEN** `export.format = 'commonmark'` and the user runs
  `:FtExport slack` (or `:3,6FtExport slack`)
- **THEN** that invocation passes `--format slack` while the configured
  default and the `gy` operator continue to pass no format flag

#### Scenario: Override back to the CLI default

- **WHEN** `export.format = 'slack'` and the user runs `:FtExport
  commonmark`
- **THEN** the invocation passes `--format commonmark` explicitly
  (the plugin default is no longer the CLI default)

#### Scenario: Completion offers the known formats

- **WHEN** the user types `:FtExport ` and requests command completion
- **THEN** the known format names (`commonmark`, `slack`) are offered

#### Scenario: Unknown format surfaces the CLI error

- **WHEN** the user runs `:FtExport bogus`
- **THEN** the value passes through to ft, ft's invalid-value error is
  classified as an error notification, and no register is written

#### Scenario: Non-default format in the success notification

- **WHEN** an export succeeds with effective format `slack`
- **THEN** the notification reads
  `ft: exported L1-2 (slack) → ", f, +` (format in parentheses;
  whole-file exports similarly)
