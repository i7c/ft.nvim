## Why

`gy` / `:FtExport` hardcode the default export target: clean CommonMark.
ft 0.1.7 added a second target, `ft notes export --format slack` (Slack
mrkdwn — headings to bold, `**bold**` → `*bold*`, `[text](url)` →
`<url|text>`, checkboxes dropped, code fences converted), which is
exactly what users pasting into Slack need — raw CommonMark renders as
literal `**text**` and `[label](url)` in Slack. The archived export
change deferred this explicitly: *"No `--format` plumbing yet — a
`export.format` config lands when ft gains a second target."* ft has
now gained that second target.

## What Changes

- New `export.format` config key: `'commonmark'` (default) or `'slack'`.
  It is the format `gy` (operator, visual) and `:FtExport` use. The
  argv builder passes `--format <name>` only when the effective format
  differs from the CLI default (`commonmark`) — the default path stays
  byte-identical to today (no flag), and the `:FtExport slack` /
  `:FtExport commonmark` override on a `'slack'`-configured setup passes
  `--format commonmark` explicitly, since the *plugin* default is no
  longer the CLI default.
- `:FtExport [format]` — optional 0-or-1 args (`-nargs=?`). No arg
  uses the configured format; an arg overrides it for that invocation
  (range and visual-selection behavior unchanged). Completion offers
  the known formats; validation of unknown values is ft's job (the CLI
  is the contract — its value-enum error surfaces, classified ERROR).
- Version floor moves: `MIN_FT_VERSION` 0.1.5 → **0.1.7**, the first
  release carrying `--format slack` (verified in the ft repo: v0.1.7
  contains `SlackExport`, v0.1.6 does not). The soft-check semantics are
  unchanged: older binaries warn at setup; if such a binary is then
  asked for `--format`, ft's clap error surfaces through the existing
  error classifier.
- Success notification carries the format when it is not the CLI
  default: `ft: exported L1-2 (slack) → ", f, +`.
- Docs: `ARCHITECTURE.md` §2 protocol-table row (add `--format <name>`,
  amend the "not passed" note, floor 0.1.7), README export section,
  `doc/ft.txt` export section (the stale embeds doc is fixed while the
  file is touched, per AGENTS.md).

Explicitly rejected (see design.md):
- **Count-prefix format selection** (`1gy`/`2gy`) — the count belongs to
  the motion (`gy3j` is documented); hijacking it breaks motion counts.
- **Per-format operators** — keymap bloat; the operator key is already
  configurable.
- **Lua-side format validation** — the format list is ft's domain; the
  plugin only offers completion from a static protocol-surface list.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `notes-export`: format selection — `export.format` config, `:FtExport
  [format]` per-invocation override, `--format` argv pass-through,
  version floor 0.1.7.

## Impact

- `lua/ft/export.lua`: pure argv-builder helper (effective format
  resolution + `--format` insertion), format threaded into the
  rangeop `cmd` closures and success notifications.
- `lua/ft/init.lua`: `export.format` default, `:FtExport` `-nargs=?`
  + completion, `MIN_FT_VERSION` bump.
- Tests: `tests/run.lua` (Tier 1 argv cases), `tests/export_stub.lua`
  (Tier 2 — configured format, per-invocation override, version gate),
  `tests/smoke.lua` (Tier 3 contract row with a real binary: same range
  exported in both formats).
- Docs: `ARCHITECTURE.md`, `README.md`, `doc/ft.txt`.
- No ft-repo changes (the CLI surface already exists).
