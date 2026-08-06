## 1. Shared core extraction (rangeop)

- [ ] 1.1 Create `lua/ft/rangeop.lua` with the pure helpers `range_spec` and `register_targets` (moved from quote.lua, same semantics) plus the shared mechanics: `_save_buffer`, `_ft_message`, `_preflight`, `_set_register`, and a `run(op, opts)` pipeline that owns preflight → rpc.call → classify → register placement → notify
- [ ] 1.2 Refactor `lua/ft/quote.lua` onto `rangeop`: keep `quote_range`, `operatorfunc`, `operator_rhs`, `quote_selection`, `setup`, and the public helpers `range_spec`/`register_targets` as thin delegations with unchanged signatures; keep the dirty/range classification markers and the empty-output-is-error path in quote
- [ ] 1.3 Run `make test` — all existing Tier 1 and Tier 2 quote tests pass unchanged against the refactor

## 2. Export operator implementation

- [ ] 2.1 Create `lua/ft/export.lua`: `export_range(a, b)` calling `rangeop.run` with argv `{'notes', 'export', rel, '-l', spec, '--json-errors'}`; `export_whole_file()` calling it without `-l`; `operatorfunc`/`operator_rhs` (global `ft_export_operator`) and `export_selection()` mirroring quote; `setup(cfg)` for the `export.registers` config; classifier = `outside file` → WARN, else ERROR; empty stdout → INFO notify + registers untouched
- [ ] 2.2 Wire `lua/ft/init.lua`: `export` config defaults (`keymaps.operator = 'gy'`, registers all true), `export.setup(config.export)`, `:FtExport` range command (no range → whole buffer via `args.range == 0`, explicit range → `-l A-B`), and `gy` normal+visual expr keymaps in `_setup_buffer` (same `g@` pattern as quote)
- [ ] 2.3 Update the `MIN_FT_VERSION` comment to note export ships in the same floor (no version change)

## 3. Tests

- [ ] 3.1 `tests/run.lua`: move/keep the `range_spec`/`register_targets` Tier 1 cases against `rangeop` (quote's delegations covered implicitly)
- [ ] 3.2 New `tests/export_stub.lua` (Tier 2, stub ft mirroring `quote_stub.lua`): argv shape (`notes export <rel> -l A-B --json-errors` + `--vault`), whole-file argv (no `-l`) via `:FtExport` no-range, save-before-export, register placement + config trims, operator/visual/command range extraction, empty-output policy (INFO + registers untouched), error classification (outside-file WARN, missing-file ERROR), outside-vault/missing-binary aborts, `operator = false` disables keymaps while `:FtExport` still works
- [ ] 3.3 Wire `tests/export_stub.lua` into the Makefile `test` target
- [ ] 3.4 `tests/smoke.lua` (Tier 3): fixture vault with frontmatter + wikilinks + a quote callout; export the whole file and a range through the plugin path against the real binary; assert clean CommonMark output and register contents

## 4. Docs

- [ ] 4.1 `ARCHITECTURE.md` §2: add the `ft notes export` row to the protocol contract table (read-only, no git, `-l` optional with frontmatter clamp, empty output legal, floor note)
- [ ] 4.2 `README.md`: feature bullet + config snippet for `export`
- [ ] 4.3 `doc/ft.txt`: new `ft-export` section mirroring `ft-quote` (usage, registers, save-before-export, prerequisites, keymaps); while touching the file, remove the stale embeds documentation (pre-existing debt flagged in AGENTS.md)

## 5. Verification

- [ ] 5.1 `make test` green (Tier 1 + Tier 2 incl. new export suite)
- [ ] 5.2 `FT_BIN=../ft/target/release/ft make smoke` green (Tier 3)
- [ ] 5.3 `openspec validate --change nvim-notes-export` passes
