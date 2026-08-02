## Why

The plugin can create tasks, mark them done, and cancel them — but the
most common follow-up edit, changing a task's due date, still requires
leaving nvim. `ft tasks edit --due` already exists in the CLI; the
plugin just never exposes it. This change wires it up the same way as
done/cancel: a command that edits the due date of the task under the
cursor.

## What Changes

- New `:FtTaskDue` command (proposed keymap `<leader>te`): prompts via
  `vim.ui.input` for the due date of the task under the cursor and runs
  `ft tasks edit <file>:<line> --due <value>`.
- The prompt accepts ft's date syntax (`+2d`, `today`, `next monday`,
  ISO) and `none` to clear the due date. An empty input cancels — no
  accidental clearing.
- Reuses the existing shared mechanics from `tasks.lua`: save-before-
  mutate, `:edit` reload preserving undo, `--json-errors` classification
  (non-task line → warn, hard failures → error). `ft tasks edit` is
  single-task and idempotent for a same-value edit, so no special
  already-set handling is needed.
- Config: `tasks.keymaps.due` (default `<leader>te`, `false` disables),
  consistent with create/done/cancel.
- Tests: Tier 1/2 stub coverage (argv shape `edit <rel>:<line> --due`,
  prompt cancel path, classification), Tier 3 smoke against the real
  binary (set via `+2d`, clear via `none`).

## Capabilities

### New Capabilities

<!-- None — this extends the existing task-ops capability. -->

### Modified Capabilities

- `task-ops`: adds an "Edit task due date" requirement — a new
  `:FtTaskDue` operation for the task under the cursor, and the
  `tasks.keymaps.due` config key.

## Impact

- **This repo**: `lua/ft/tasks.lua` (new `M.set_due()` + a shared
  selector-op helper), `init.lua` (command + keymap wiring, config
  default), `doc/ft.txt` + README, `tests/run.lua`, `tests/tasks_stub.lua`
  (Tier 2), `tests/smoke.lua` (Tier 3). ARCHITECTURE.md protocol table
  gains the `ft tasks edit` row.
- **ft CLI (consumed, unchanged)**: `ft tasks edit <selector> --due
  <DATE|none> --json-errors` — exists in 0.1.0; `MIN_FT_VERSION` stays
  `0.1.0`.
- **No domain logic in Lua**: the prompt value is passed through
  verbatim; ft resolves dates and serializes the line.
