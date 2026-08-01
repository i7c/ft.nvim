## 1. Implementation

- [ ] 1.1 Add `M.set_due()` to `lua/ft/tasks.lua`: shared preflight → prompt via `vim.ui.input` → empty input cancels → `ft tasks edit <rel>:<line> --due <value> --json-errors` → reload on success, warn on "no tasks match selector", error otherwise
- [ ] 1.2 Wire `:FtTaskDue` command and `tasks.keymaps.due = '<leader>te'` default (per-buffer keymap, `false` disables) in `init.lua`
- [ ] 1.3 Update `doc/ft.txt` and README: `:FtTaskDue`, `<leader>te`, `none`-to-clear

## 2. Tests

- [ ] 2.1 Tier 2 (`tests/tasks_stub.lua`): stub gains an `edit` branch; assert argv shape (`edit <rel>:<line> --due +2d` / `--due none`), empty-prompt cancel runs nothing, warn on `no_match`, error on `hard_error`, reload on success
- [ ] 2.2 Tier 3 (`tests/smoke.lua`): real binary — set due via `+2d` (ISO date on line), clear via `none` (date gone), non-task line warns

## 3. Docs & architecture sync

- [ ] 3.1 Update ARCHITECTURE.md: protocol table gains the `ft tasks edit` row; `MIN_FT_VERSION` unchanged
- [ ] 3.2 `make test` green; `make smoke` green with the built ft binary
