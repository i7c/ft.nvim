# nvim-notes-quote — Tasks

## 1. Foundation

- [ ] 1.1 Add `quote` defaults to `init.lua`: `quote = { keymaps = { operator = 'gz' }, registers = { unnamed = true, named = true, clipboard = true } }`
- [ ] 1.2 Implement `quote.range_spec(a, b)` pure helper: formats the `A-B` string, validates `A >= 1` and `A <= B` (defensive — editor-derived ranges should never violate; Tier 1 testable)
- [ ] 1.3 Implement `quote.register_targets(registers_cfg)` pure helper: resolves the enabled register set from config (unnamed `"`, named `f`, clipboard `+`) into an ordered list for setreg

## 2. Core module

- [ ] 2.1 Implement `quote_range(a, b)` in `lua/ft/quote.lua`: preflight (vault discovered, named buffer inside vault), save-before-quote (`_save_buffer` pattern; abort on failed write), `rpc.call({ 'notes', 'quote', rel, '-l', range_spec, '--json-errors' })`, on success setreg linewise into each target (clipboard silently skipped when `has('clipboard')` is 0 or `setreg` returns 0) + notify `ft: quoted LA-B → "`, `f`, `+` (only registers that landed); on failure classify + notify, write no registers
- [ ] 2.2 Implement error classification: `has uncommitted changes` → WARN with ft's message + "commit or stash, then quote again" hint; `line range … outside file` → WARN; `not inside a git repository`, `cannot read source file`, and everything else → ERROR (decode via the `--json-errors` object, reusing the `_ft_message` pattern)
- [ ] 2.3 Implement `operatorfunc()` (reads `'[`/`']` → `quote_range`) and the normal-mode operator keymap builder (expr mapping that sets `operatorfunc = 'v:lua.require("ft.quote").operatorfunc'` and returns `g@`)
- [ ] 2.4 Implement `quote_selection()` (reads `'<`/`'>`) and `quote_current_line()`; the `:FtQuote`-backing dispatcher picks selection in visual mode, current line otherwise

## 3. Wiring

- [ ] 3.1 Register `:FtQuote` user command in `init.lua` (mode-aware: visual → selection, else current line; desc; guarded against duplicate registration)
- [ ] 3.2 In `_setup_buffer`, bind `quote.keymaps.operator` (default `gz`) in normal mode (operator) and visual mode (selection); `false` disables both; `:FtQuote` works regardless
- [ ] 3.3 Bump `MIN_FT_VERSION` to the ft release carrying `ft notes quote` (≥ 0.1.5; exact number per ft's release) and update its comment

## 4. Tier 1 + Tier 2 tests

- [ ] 4.1 Tier 1 (`tests/run.lua`): `range_spec` cases (single line, multi-line, validation rejects A<1 / A>B), `register_targets` trim per config, source-scan guard still green (no spawns outside rpc.lua, no `ft_run`/`ft_cmd` remnants)
- [ ] 4.2 Tier 2 stub suite (new `tests/quote_stub.lua`): stub ft logs argv and emits canned callout / `--json-errors` per mode; assert argv shape (`notes quote <rel> -l A-B --json-errors`, `--vault` injected), save-before ordering (unsaved buffer written before ft runs), register contents (linewise) in `"` / `f` / `+` incl. config-disabled variants and clipboard-unavailable path, operator range extraction (`setpos` `'[`/`']` then `operatorfunc`), visual range extraction (`setpos` `'<`/`'>` then `quote_selection`), classification (uncommitted → WARN + hint, out-of-bounds → WARN, other → ERROR), failed quote leaves registers untouched, outside-vault abort, missing-binary path
- [ ] 4.3 Wire `tests/quote_stub.lua` into the Makefile `test` target

## 5. Tier 3 smoke

- [ ] 5.1 Make the smoke fixture vault a git repo (git init + add + commit) so the clean check passes; quote a committed range with the real binary and assert the `"` register holds the exact callout (`> [!ft-source] "Notes/Apple.md" L… @<7-hex> #<6-hex>` header + quoted body lines)
- [ ] 5.2 Dirty-file path: modify + save a note without committing → quote surfaces the WARN with the commit/stash hint and leaves registers untouched
- [ ] 5.3 Hard floor assert: parse the real binary's `--version` and fail loudly when it is older than `MIN_FT_VERSION`
- [ ] 5.4 `make test` and `make smoke` (with a built ft binary) green

## 6. Docs & architecture sync

- [ ] 6.1 ARCHITECTURE.md: protocol contract table gains the `ft notes quote` row (flags, used-by, notes); roadmap "synth notes" row updated (plumbing now consumed — drop the future `--print` note); `MIN_FT_VERSION` mention updated
- [ ] 6.2 README + `doc/ft.txt`: quote feature (operator + motions, `:FtQuote`, register behavior incl. clipboard/unnamedplus note, dirty-file limitation, and the paste/verify note: a pasted section is only checked by `synth verify` in a note with `ft.synth.enabled: true`)
