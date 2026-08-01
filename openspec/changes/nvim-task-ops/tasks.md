## 1. Foundation

- [ ] 1.1 Add `vault.relativize(path)` helper (strip vault root prefix, return nil outside vault) with Tier 1 tests
- [ ] 1.2 Implement `tasks.parse_due(description)` pure function: whitespace tokens, case-insensitive `due:` prefix, `\due:` escape, repeated/empty → error, description with token removed (word order preserved)

## 2. Core module

- [ ] 2.1 Implement `lua/ft/tasks.lua` with shared helpers: `_save_buffer` (silent write + `modified` check, abort on failure), `_reload_from_disk` (set_lines + `nomodified`, mark cache dirty), `_notify_ft_error` (decode `--json-errors` output, classify already-done/already-cancelled as idempotent info)
- [ ] 2.2 Implement `tasks.create()`: prompt via `vim.ui.input` (pre-filled from trimmed current line when non-empty), build `tasks create <desc> --file <rel> --at-line <N> --force [--due <v>] --json-errors`, reload + cursor `{N, 0}` on success
- [ ] 2.3 Implement `tasks.done()` / `tasks.cancel()`: selector `<rel>:<cursorline>`, `complete|cancel <sel> --yes --json-errors`, reload on success, idempotent info for already-done/cancelled, warn for not-a-task, error otherwise

## 3. Wiring

- [ ] 3.1 Register `:FtTaskCreate` / `:FtTaskDone` / `:FtTaskCancel` user commands in `init.lua` (global, vault-checked at invocation)
- [ ] 3.2 Add `tasks.keymaps` config defaults (`<leader>tt`/`<leader>td`/`<leader>tc`, `false` disables) and buffer-local keymaps in `_setup_buffer`
- [ ] 3.3 Update `doc/ft.txt` and README: three commands, keymaps, inline `due:` syntax, idempotency notes

## 4. Tests

- [ ] 4.1 Tier 1 (`tests/run.lua`): `parse_due` cases, `vault.relativize`, source-scan guard still green (no spawns outside rpc.lua)
- [ ] 4.2 Tier 2 stub-binary tests (new `tests/tasks_stub.lua`): stub ft echoes argv + canned output/exit codes; assert argv shape (`--file`, `--at-line`, `--force`, selector `rel:line`), save-before-spawn ordering, idempotent classification (already-done/cancelled → info), reload keeps undo history, cursor on new task after create, missing-binary path
- [ ] 4.3 Tier 3 (`tests/smoke.lua`): real ft binary + fixture vault — create at cursor line (disk, reload, cursor), done, cancel, `due:+2d` → ISO date on line, duplicate create allowed, already-done idempotent, not-a-task warning
- [ ] 4.4 Wire Tier 2 into the Makefile (`make test` runs Tier 1 + Tier 2)

## 5. Docs & architecture sync

- [ ] 5.1 Update ARCHITECTURE.md: protocol table gains `ft tasks create` / `complete` / `cancel` rows; roadmap row for create/subtask updated; note the deferred `--subtask-of` CLI gap
- [ ] 5.2 `make test` green; `make smoke` green with the built ft binary
