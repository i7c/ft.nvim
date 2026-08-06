## Why

`gz` wraps a line range *into* a pinned `[!ft-source]` callout — but there is no
way to do the inverse: strip vault structure (frontmatter, callout headers,
wikilinks) and get clean CommonMark out of the editor. `ft notes export` is the
inverse plumbing already shipped in the ft CLI (same crate version as quote),
and the plugin has no surface for it — users must shell out manually.

## What Changes

- New `gy` operator (normal + visual) and `:FtExport` command that run
  `ft notes export <rel> [-l A-B] --json-errors` over a line range and land the
  clean CommonMark output linewise in the registers (`"`, `f`, `+`), mirroring
  `gz`'s ergonomics.
- New `export` config section: `keymaps.operator` (default `gy`, `false`
  disables) and `registers` (same defaults as `quote.registers`; the named
  register `f` is shared with quote — last op wins).
- Shared editor-glue core extracted from `quote.lua` (preflight, save-before-op,
  ft message extraction, register placement, `range_spec`/`register_targets`)
  into a new `ft.rangeop` module; `quote.lua` and `export.lua` become thin
  wrappers with unchanged public APIs.
- Deliberate differences from quote, all stemming from export's CLI semantics:
  no git dependency (no dirty-source path), range start clamps to the first body
  line (frontmatter never exported), whole-file when `-l` is omitted
  (`:FtExport` no-range default = whole buffer), and empty output is a legal
  result (frontmatter-only range) — notified, registers untouched.
- Docs: `ARCHITECTURE.md` §2 protocol table row, README, `doc/ft.txt` new
  `ft-export` section (and the pre-existing stale embeds doc fixed while the
  file is touched).
- Version floor unchanged: `ft notes export` ships in the same reported crate
  version (0.1.5) that already carries quote.

## Capabilities

### New Capabilities
- `notes-export`: exporting a line range (or the whole note) of the current
  buffer as clean CommonMark via `ft notes export`, with the operator/visual/
  command entry points, register placement, and error handling.

### Modified Capabilities
<!-- none — quote's spec is unchanged; export is a new capability -->

## Impact

- `lua/ft/rangeop.lua` (new shared module), `lua/ft/export.lua` (new),
  `lua/ft/quote.lua` (refactor onto the shared core, public API unchanged),
  `lua/ft/init.lua` (config defaults, `:FtExport` command, `gy` keymaps).
- Tests: `tests/run.lua` (Tier 1 helpers — relocated, not duplicated),
  `tests/export_stub.lua` (new Tier 2, wired into the Makefile),
  `tests/smoke.lua` (Tier 3 contract row with a real binary).
- Docs: `ARCHITECTURE.md`, `README.md`, `doc/ft.txt`.
- No ft-repo changes; no `MIN_FT_VERSION` change.
