# Design — nvim-notes-export

## Context

See proposal.md — Why. The plugin is editor glue over the `ft` CLI
(pillar 1.1: no domain logic in Lua). `gz`/`quote.lua` is the existing
template: a `g@`-based operator (the only way to read a visual
selection — nvim commits `'<`/`'>` only after visual mode exits), a
range command, and register placement. `ft notes export` (verified in
the ft repo and the built binary) is the inverse of `ft notes quote`:
read-only, **no git dependency**, whole-file when `-l` is omitted, range
start clamped past frontmatter, empty output legal (exit 0), and
`--json-errors` honored via the top-level flag in `ft/src/main.rs`.
The built binary reports `ft 0.1.5` and ships export — the version floor
does not move.

## Goals / Non-Goals

**Goals:**
- `gy` operator + `:FtExport` with the same ergonomics as `gz`/`:FtQuote`.
- Extract the editor-glue mechanics quote and export share into one
  module so register semantics have a single source of truth.
- Cover the new behavior differences (whole-file default, no git path,
  legal empty output) with tests at every tier.

**Non-Goals:**
- No ft-repo changes; no `MIN_FT_VERSION` change.
- No in-place transformation (replacing the selected range with its
  exported form) — export's stated purpose is external/paste output;
  splicing would mutate vault files and fight line-count drift.
- No `--format` plumbing yet — `commonmark` is the CLI default; a
  `export.format` config lands when ft gains a second target.
- No changes to quote's public API or behavior (refactor only).

## Decisions

**1. Shared core module `lua/ft/rangeop.lua`.**
Quote and export share ~80 lines of pure editor glue: `range_spec`
(the `A-B` token), `register_targets` (config → ordered `{reg, name}`
list), `_preflight` (vault + named buffer + inside-vault + save),
`_save_buffer`, `_ft_message` (JSON-error extraction from the merged
stdout/stderr stream — verified: nvim's `system()` merges stderr, and
with empty stdout the string starts directly at the stderr content), and
`_set_register` (pcall-guarded setreg).
`rangeop.run(op, opts)` takes the argv tail (`{'notes', 'export', rel,
'-l', spec, '--json-errors'}` or nil for whole-file), a classifier, and
notification text, and owns the preflight → rpc.call → classify →
register placement → notify pipeline. `quote.lua` and `export.lua`
become thin wrappers; `quote.range_spec`, `quote.register_targets`, and
every entry point keep their names and signatures, so the existing Tier
1/Tier 2 quote tests pass unchanged.
*Alternative rejected:* duplicate the mechanics in `export.lua`
(option A) — two copies of register semantics that will drift; the
project's no-drift ethos (AGENTS.md) argues against it.

**2. `:FtExport` no-range default = whole buffer.**
nvim range commands report `args.range` (0 = no range). `:FtExport`
with no range passes no `-l` to ft (whole file — matches the CLI's
default and the flagship "clean copy of this note"); an explicit range
or a visual selection passes `-l A-B`. The operator (`gy`) always passes
`-l A-B` — its range is defined by the motion.
*Alternative rejected:* mirror `:FtQuote` (no-range = current line) — a
single-line export is rarely the intent, and the whole-file default is
the CLI's own.

**3. Register `f` shared with quote.**
The named register stays `f`, "only ever written by this plugin — last
op wins". One stable home keeps the mental model ("the ft copy
register") and the `quote.registers`/`export.registers` configs stay
parallel.

**4. Error classification, simplified.**
`rangeop` classifies on message markers: `outside file` → WARN, else
ERROR. Export drops quote's dirty-source marker (no git path exists).
`--json-errors` is still passed for both so the JSON `error` field is
the classified text when present.

**5. Empty output is success-with-nothing.**
Whole-frontmatter range → exit 0, empty stdout. `rangeop` treats
empty output as a legal outcome per-op: export notifies INFO ("export
is empty — range inside frontmatter?") and skips register writes.
Quote's empty-output path is unchanged (error).

**6. Operator key `gy`.** Free in default nvim (`ge`/`gx`/`gq`/`gw`
are builtins, `gz` is quote). Mnemonic: yank-as-exported. Configurable
via `export.keymaps.operator`; `false` disables keymaps while
`:FtExport` still works — the same disable pattern quote pins in tests.

## Risks / Trade-offs

- **Refactor of quote.lua** → the quote Tier 1/2 tests pin its public
  behavior; the refactor keeps public APIs unchanged, so the suite is
  the safety net. Run it before and after.
- **Shared `f` register** → exporting after quoting overwrites the
  quote (and vice versa). Mitigation: documented; users can disable the
  named register in either config.
- **`args.range == 0` heuristic** for whole-file → an explicit
  `:FtExport 5` still passes `-l 5-5` (single line), so no ambiguity
  between "no range" and "one line".
- **Empty-output policy** relies on ft's contract (exit 0 + empty
  stdout for frontmatter-only ranges) → pinned by the Tier 2 stub and
  Tier 3 real-binary tests; if ft ever changes that contract, the suite
  catches it.

## Migration Plan

Backward compatible: quote's behavior and public API are unchanged; the
new `export` config defaults are additive. Rollback = revert the
implementation commit; the openspec change stays as the record.
