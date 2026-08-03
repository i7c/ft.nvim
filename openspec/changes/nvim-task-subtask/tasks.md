## 1. Core module

- [x] 1.1 Implement `M.create_subtask()` in `lua/ft/tasks.lua`, reusing `_preflight`, `_reload_from_disk`, `parse_due`, and `_ft_message`: capture the parent line at invocation, empty-default prompt, argv `tasks create <desc> --parent <rel>:<line> --force [--due v] --json-errors` (no `--file`/`--at-line`), reload + cursor back on the parent line on success, WARN on `no tasks match selector`, ERROR otherwise, missing-binary passthrough

## 2. Wiring

- [x] 2.1 Register `:FtTaskSubtask` in `lua/ft/init.lua`; add `tasks.keymaps.subtask = '<leader>ts'` to the defaults and the `_setup_buffer` keymap loop; update the module docstring
- [x] 2.2 Raise `MIN_FT_VERSION` to `{ 0, 1, 4 }`

## 3. Tests

- [x] 3.1 Tier 2 (`tests/tasks_stub.lua`): stub `create` branch handles `--parent` (mutate file, canned success + `no tasks match selector` modes); assert argv shape (`--parent rel:line`, no `--file`/`--at-line`, `--force`, `--json-errors`, optional `--due`), save-before-spawn ordering, cursor stays on the parent line, WARN classification, missing binary, outside-vault abort
- [x] 3.2 Tier 3 (`tests/smoke.lua`): real binary — childless parent gets a 2-space-indented child; parent with children gets a verbatim-indent child appended after the block; nested invocation goes one level deeper; duplicate allowed (`--force`); cursor stays on the parent line; non-task line → WARN
- [x] 3.3 `make test` green; `make smoke` green with the dev binary (floor warning against dev builds is expected; version test uses the stub)

## 4. Docs & architecture sync

- [x] 4.1 ARCHITECTURE.md: `ft tasks create` protocol row gains `--parent`; roadmap row "Create task / subtask in place" resolved; floor note updated
- [x] 4.2 README + `doc/ft.txt`: `:FtTaskSubtask`, `<leader>ts`, empty-prompt and cursor-stays behavior
