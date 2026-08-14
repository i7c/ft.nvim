# nvim-export-format-prompt — Tasks

## 1. Export core: format resolution + argv

- [x] 1.1 In `lua/ft/export.lua`, add the hardcoded format list
      `{ { id = 'commonmark', desc = <CLI desc> }, { id = 'slack',
      desc = <CLI desc> } }` and a `known[format]` lookup for config
      validation.
- [x] 1.2 Add a `resolve_format(cfg, cb)` step: when `export.format`
      is a known id, call `cb(fmt)` synchronously with no prompt;
      otherwise (including `'prompt'` default and unknown values)
      call `ft.picker.select(items, { prompt = … }, fn)` and invoke
      `cb` with the chosen item — returning silently on `nil` cancel
      (no ft call, no register write, no notification). Handle both
      sync and async picker backends (callback-only, no code after
      the call that assumes it ran).
- [x] 1.3 Thread the resolved format into both `rangeop.run` call
      sites: the range builder gets
      `{ 'notes', 'export', rel, '-l', s, '--format', fmt, '--json-errors' }`
      and the whole-file builder
      `{ 'notes', 'export', rel, '--format', fmt, '--json-errors' }`.
- [x] 1.4 Update the success notifications to name the format:
      `'ft: exported L' .. s .. ' (' .. fmt .. ') → ' …` and
      `'ft: exported whole note (' .. fmt .. ') → ' …`.
- [x] 1.5 Add `format = 'prompt'` to `defaults.export` in
      `lua/ft/init.lua` and update the setup docstring.

## 2. Version floor

- [x] 2.1 Bump `MIN_FT_VERSION` from `{0,1,5}` to `{0,1,7}` in
      `lua/ft/init.lua` (first release with `ft notes export` +
      `--format commonmark|slack`, per ft git history: export ships
      v0.1.6, slack lands v0.1.7) and correct the stale "0.1.5
      carries export" comment.
- [x] 2.2 Update the `ft notes export` row of the protocol contract
      table in `ARCHITECTURE.md` §2: `--format <FORMAT>` is now
      passed (`commonmark` no longer "CLI default, not passed"), and
      note the value set.

## 3. Tests

- [x] 3.1 Update the stub binary in `tests/export_stub.lua` to
      consume `--format <value>` in its arg loop (it currently would
      misread `--format` as the file token).
- [x] 3.2 In `tests/export_stub.lua`, stub `vim.ui.select` with a
      default `cb(items[1], 1)` (sync) and update the exact argv
      assertions to include `--format commonmark`.
- [x] 3.3 Add stub scenarios: picker choice `slack` → argv contains
      `--format slack` and notification contains `(slack)`; cancel
      (`cb(nil)`) → empty stub log + registers untouched; configured
      `export.format = 'slack'` → no picker call, `--format slack`
      passed; unknown config value → prompt shown (treated as
      `'prompt'`).
- [x] 3.4 Check `tests/quote_stub.lua` / `tests/run.lua` need no
      changes (quote untouched; the source-scan guard is unaffected).
- [x] 3.5 Update the Tier 3 smoke suite if it exercises export argv
      shape; with a real binary, use a configured format (no prompt)
      and assert `--format` round-trips.

## 4. Docs

- [x] 4.1 Document `export.format` (values + default `'prompt'` +
      cancel behavior) in README and `doc/ft.txt` (fix the
      still-documented embeds while touching that file, per AGENTS.md
      note).
- [x] 4.2 Run `make test` and `make smoke` (with the newest binary);
      keep all tiers green.
