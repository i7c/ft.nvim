## Why

The ft TUI owns task creation/updating today; the Neovim plugin can only
read notes and follow wikilinks. Users who live in nvim (launched from the
TUI as `$EDITOR`) have no way to create or update tasks without leaving
the editor. This change adds in-editor task operations — create, mark
done, cancel — as editor glue over the existing `ft tasks` CLI surface,
so the nvim session becomes a first-class place to manage tasks.

## What Changes

- New `lua/ft/tasks.lua` module wiring three operations to `ft tasks`:
  - **Create** — insert a new task at the cursor line in the current
    buffer (content pushed down). Description is prompted via
    `vim.ui.input`, pre-filled with the current line's text when
    non-empty ("turn the current line into a task"). Always passes
    `--force` (duplicates are allowed, not an error). After success the
    buffer reloads from disk (undo history preserved) and the cursor
    moves onto the new task line.
  - **Done** — `ft tasks complete <file>:<line>` for the task under the
    cursor. Already-done is idempotent (info, not error).
  - **Cancel** — `ft tasks cancel <file>:<line>` for the task under the
    cursor. Already-cancelled is idempotent (info, not error).
- **Inline `due:` support** mirroring the ft TUI quickline: the
  description prompt accepts `Buy milk due:+2d`; the `due:` token is
  extracted and its raw value passed to `--due` (ft resolves relative /
  keyword dates to ISO — Lua never computes dates). `\due:` escapes to a
  literal description token; a repeated or empty `due:` is an error.
- **Save-before-mutate**: every mutating command writes the buffer to
  disk first (ft reads from disk); a failed write aborts the operation.
- **Reload-with-undo**: after a successful mutation the buffer is synced
  to disk in place (`nvim_buf_set_lines` + `nomodified`) instead of
  `:edit`, so undo history survives the reload. The note-index cache is
  marked dirty.
- New commands `:FtTaskCreate`, `:FtTaskDone`, `:FtTaskCancel` and a
  `tasks.keymaps` config section (defaults `<leader>tt` / `<leader>td` /
  `<leader>tc`, each disable-able with `false`).
- Tests: Tier 1 pure-function tests (due-token extraction, vault
  relativize), Tier 2 stub-binary tests (create/done/cancel flows,
  idempotency classification, save-before-spawn ordering, undo
  preservation), Tier 3 smoke tests against the real `ft` binary
  (create at cursor, done/cancel, `due:+2d` → ISO date on the line).

**Explicitly deferred** (user will add the ft CLI flag in a later
session, then a follow-up feature session): subtask creation —
`Position::Subtask` exists in ft-core but `ft tasks create` has no CLI
flag for it, and the plugin must not compute indentation itself.

## Capabilities

### New Capabilities

- `task-ops`: in-editor task creation (at cursor, inline `due:` syntax,
  duplicate-allowed) and status updates (done/cancel via `<file>:<line>`
  selector, idempotent), with save-before-mutate and
  undo-preserving reload.

### Modified Capabilities

<!-- No existing specs in openspec/specs/ yet; this change introduces the first. -->

## Impact

- **This repo**: new `lua/ft/tasks.lua`; `init.lua` (command + keymap
  wiring, `tasks` config defaults); `lua/ft/vault.lua` (add
  `relativize()` helper); `doc/ft.txt` + README (document the three
  commands and keymaps); `tests/run.lua` + `tests/smoke.lua` (+ a stub
  harness for Tier 2). ARCHITECTURE.md: protocol table gains the three
  consumed `ft tasks` rows.
- **ft CLI (consumed, unchanged)**: `ft tasks create --file/--at-line/
  --force/--due`, `ft tasks complete|cancel <file>:<line> --yes`,
  global `--vault` and `--json-errors`. `MIN_FT_VERSION` stays `0.1.0` —
  everything used exists in 0.1.0. The one CLI gap (subtask flag) is
  deferred and documented in ARCHITECTURE.md.
- **No domain logic in Lua**: Lua extracts the `due:` token from user
  input (argument plumbing); date resolution and task-line
  serialization stay in ft.
