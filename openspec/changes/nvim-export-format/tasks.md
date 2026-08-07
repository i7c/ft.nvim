## 1. Core — argv builder and format resolution (`lua/ft/export.lua`)

- [ ] 1.1 Extract the argv construction into a pure helper
      `export.cmd_args(rel, spec, format)` returning the argv tail
      (`{'notes', 'export', rel, ...}`), inserting
      `--format <name>` right after `rel` only when `format` is
      non-nil and not `'commonmark'`. Range shape keeps `-l A-B`;
      whole-file shape (spec nil) keeps no `-l`. Both keep
      `--json-errors` last.
- [ ] 1.2 `export.setup(cfg)` stores the configured format
      (`cfg.format`, default `'commonmark'`) next to `registers`; add
      `export.formats = { 'commonmark', 'slack' }` (static
      protocol-surface list, used for completion only).
- [ ] 1.3 `export_range(a, b, format)` / `export_whole_file(format)`
      accept an optional per-invocation override (nil → configured
      format); resolve the effective format once, before
      `rangeop.run`, and have the `cmd` closures build their argv via
      `cmd_args` with it. Operator (`operatorfunc`),
      `export_selection`, and the no-arg command path pass nothing.
- [ ] 1.4 Success notifications append `(<format>)` after the range
      label when the effective format is not `'commonmark'`
      (`ft: exported L1-2 (slack) → ", f, +`; whole-file similarly);
      the commonmark path keeps today's exact text.

## 2. Wiring (`lua/ft/init.lua`)

- [ ] 2.1 Add `format = 'commonmark'` to the `export` defaults table.
- [ ] 2.2 `:FtExport` gains `nargs = '?'` (0 or 1) and
      `complete` returning `export.formats`; pass `args.args`
      (empty → nil) through to `export_whole_file` / `export_range`,
      keeping the `args.range == 0` whole-file heuristic and the
      visual-selection behavior unchanged.
- [ ] 2.3 Bump `MIN_FT_VERSION` from `{ 0, 1, 5 }` to `{ 0, 1, 7 }`
      (first release carrying `--format slack`), updating the comment
      that names the carried surfaces.

## 3. Tier 1 tests (`tests/run.lua`)

- [ ] 3.1 Add `export.cmd_args` cases: format `'commonmark'`/nil →
      no `--format` in either shape; `'slack'` → `--format slack`
      after `rel`, before `-l A-B` (range) and before `--json-errors`
      (whole-file); `'commonmark'` explicitly requested still omits the
      flag (≠ CLI-default rule).
- [ ] 3.2 Re-run the existing argv/source-scan assertions unchanged
      (default path must stay byte-identical).

## 4. Tier 2 tests (`tests/export_stub.lua`)

- [ ] 4.1 Bump the stub's `--version` echo from `ft 0.1.5` to
      `ft 0.1.7` so setup's soft check stays quiet mid-suite.
- [ ] 4.2 Configured format: `export.setup({ format = 'slack' })`,
      export a range — argv log contains `--format slack` between
      `notes export <rel>` and `-l A-B`, registers hold the canned
      text, notification reads `ft: exported L1-2 (slack) → ", f, +`.
- [ ] 4.3 Per-invocation override: default config + `:FtExport slack`
      passes `--format slack`; `export.setup({ format = 'slack' })` +
      `:FtExport commonmark` passes `--format commonmark` explicitly;
      whole-file override (`:FtExport slack` no range) keeps no `-l`.
- [ ] 4.4 Version gate (new section): a second stub echoing
      `ft 0.1.6` fires the soft warning on `_check_ft_version`; the
      `ft 0.1.7` stub does not.

## 5. Tier 3 tests (`tests/smoke.lua`)

- [ ] 5.1 Update the version-warning assertion string
      `older than the required 0.1.5` → `0.1.7`.
- [ ] 5.2 Contract row: against the real binary, export the same
      fixture range twice through the plugin path — once default
      (no flag), once via `export_range(a, b, 'slack')` — and assert
      the outputs differ in the documented way: the fixture body
      contains a bold span (`**word**`) and a markdown link
      (`[label](url)`); commonmark output keeps both verbatim, slack
      output contains `*word*` and `<url|label>` and neither raw
      `**` nor `[label](` forms.

## 6. Docs

- [ ] 6.1 `ARCHITECTURE.md` §2: `ft notes export` row — flags column
      gains `--format <name>`; amend the closing note to
      "`--format commonmark` is the CLI default and is not passed;
      the plugin passes `--format` only when a non-default format is
      configured or requested (`export.format`, `:FtExport <fmt>`)";
      bump the §2 floor text `0.1.5` → `0.1.7`.
- [ ] 6.2 `README.md`: export section — `export.format` key
      (`'commonmark'` | `'slack'`), `:FtExport [format]` with
      completion, the version-floor note (ft ≥ 0.1.7 for formats).
- [ ] 6.3 `doc/ft.txt`: export section — document the format config
      and command arg; while the file is touched, fix the stale
      embeds documentation (AGENTS.md convention).

## 7. Verification

- [ ] 7.1 `make test` green (Tier 1 + Tier 2).
- [ ] 7.2 `FT_BIN=../ft/target/release/ft make smoke` green (Tier 3).
