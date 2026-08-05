# notes-quote Specification

## Purpose

Lets users turn a line range of the current note into a protected
section — the pinned `[!ft-source]` callout emitted by `ft notes
quote` — placed into registers for pasting into any other note.

## Requirements

### Requirement: Quote a line range

The plugin SHALL quote a 1-indexed inclusive line range of the current
buffer by running `ft notes quote <vault-relative-path> -l A-B` through
the rpc seam (which injects `--vault <root>`), passing the raw callout
through unparsed. On success the callout SHALL be placed linewise into
the configured registers and a notification SHALL show the quoted
range. On failure no register SHALL be written and the notification
SHALL classify the error. When no vault is discovered, the operation
SHALL abort with an error notification before any ft command runs.

#### Scenario: Quote a clean committed range

- **WHEN** the current buffer is a vault note whose file is committed at
  HEAD and unmodified, and the user quotes lines 3–5
- **THEN** `ft notes quote <rel> -l 3-5` runs, the returned
  `> [!ft-source] …` callout is placed linewise into the configured
  registers, and a notification reports the quoted range

#### Scenario: Failed quote leaves registers untouched

- **WHEN** the quote command exits non-zero (e.g. the source has
  uncommitted changes)
- **THEN** no register is written and the previous register contents are
  preserved

#### Scenario: Outside a vault

- **WHEN** the current buffer is not inside a discovered vault and the
  user invokes quote
- **THEN** the operation aborts with an error notification and no ft
  command runs

### Requirement: Operator, visual, and command entry points

The plugin SHALL expose a normal-mode operator bound to
`quote.keymaps.operator` (default `gz`) that takes a motion or text
object and quotes the covered line range; in visual mode the same key
SHALL quote the current selection's line span; the `:FtQuote` command
SHALL quote the current line in normal mode and the selection in visual
mode. The operator SHALL leave the cursor at the start of the quoted
range. Setting `quote.keymaps.operator` to `false` SHALL disable the
keymaps while the command still works.

#### Scenario: Operator with a paragraph motion

- **WHEN** the cursor is on a paragraph and the user presses `gz` then
  `ap`
- **THEN** the paragraph's line range is quoted and the cursor lands on
  the range's first line

#### Scenario: Operator with a count motion

- **WHEN** the cursor is on line N and the user presses `gz` then `3j`
- **THEN** the range N–(N+3) is quoted

#### Scenario: Visual selection

- **WHEN** the user visually selects lines 7–9 and presses `gz`
- **THEN** lines 7–9 are quoted

#### Scenario: Command quotes the current line

- **WHEN** the user runs `:FtQuote` in normal mode with the cursor on
  line 12
- **THEN** line 12 is quoted

#### Scenario: Operator keymap disabled

- **WHEN** the user sets `quote.keymaps.operator = false` and opens a
  markdown buffer inside a vault
- **THEN** no quote keymap is mapped while `:FtQuote` still works

### Requirement: Register placement

On success the callout SHALL be placed into the unnamed register `"`,
the named register `f`, and the system clipboard `"+`, all linewise,
so plain `p` pastes the section as a block. The `quote.registers`
config SHALL allow disabling any of the three (default all enabled).
When the clipboard is unavailable (nvim without `+clipboard` or a
failing provider) the clipboard write SHALL be skipped silently while
the in-session registers are still set; the success notification SHALL
reflect which registers actually received the section.

#### Scenario: Default register set

- **WHEN** a quote succeeds with default config
- **THEN** the callout is in `"`, `f`, and `"+` (linewise) and the
  notification lists all three

#### Scenario: Named register disabled

- **WHEN** the user sets `quote.registers.named = false` and quotes
  successfully
- **THEN** the callout is in `"` and `"+` but not in `f`

#### Scenario: Clipboard unavailable

- **WHEN** nvim has no clipboard support and the user quotes
  successfully
- **THEN** the callout is in `"` and `f`, no clipboard error is raised,
  and the notification reflects the reduced register set

### Requirement: Save before quoting

Before the quote command SHALL run, the current buffer SHALL be written
to disk when it has unsaved changes, so the pinned lines match what the
user sees. If the write fails (read-only buffer), the operation SHALL
abort with an error notification and no ft command SHALL run.

#### Scenario: Modified buffer is saved first

- **WHEN** the buffer has unsaved changes and the user quotes a range
- **THEN** the buffer is written to disk before the ft command runs and
  the callout reflects the on-screen content

#### Scenario: Failed write aborts

- **WHEN** the buffer cannot be written (read-only) and the user quotes
- **THEN** the operation aborts with an error notification and no ft
  command runs

### Requirement: Errors are classified and git is never touched

The plugin SHALL classify ft's errors: a source file with uncommitted
changes SHALL surface as a warning including ft's message and a
"commit or stash" hint; a line range outside the file SHALL surface as
a warning; a vault outside a git repository, a missing source file, and
all other failures SHALL surface as errors. The plugin SHALL NOT run
any git command or offer to commit — the ft error text is the remedy.

#### Scenario: Uncommitted source warns with a hint

- **WHEN** the source file has uncommitted changes and the user quotes
- **THEN** a warning notification shows ft's error naming the file with
  a commit-or-stash hint, and no git command is run

#### Scenario: Range outside the file warns

- **WHEN** the quoted range exceeds the file's line count
- **THEN** a warning notification shows ft's out-of-bounds message

#### Scenario: Missing ft binary

- **WHEN** no ft binary is available and the user quotes
- **THEN** the rpc missing-binary error surfaces and no buffer or
  register change occurs

### Requirement: Version floor moves with the CLI surface

`MIN_FT_VERSION` SHALL move to the ft release that carries
`ft notes quote`; the setup soft-warning logic is unchanged (an older
binary warns, never fails), and the smoke suite SHALL hard-assert that
the available binary's reported version is at least that floor.

#### Scenario: Setup warns on an older binary

- **WHEN** the installed ft reports a version older than the floor
- **THEN** setup shows the soft version warning

#### Scenario: Smoke asserts the floor

- **WHEN** the smoke suite runs against a real ft binary
- **THEN** it fails loudly unless the binary's version is at least the
  floor
