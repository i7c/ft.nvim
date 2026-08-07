# Design — nvim-export-format

## Context

See proposal.md — Why. Today `export.lua` builds the argv tail inline
in two `cmd` closures: `{ 'notes', 'export', rel, '-l', s,
'--json-errors' }` (range) and `{ 'notes', 'export', rel,
'--json-errors' }` (whole-file). The format is not plumbed anywhere —
the archived notes-export change deferred it explicitly. `ft notes
export` accepts `--format {commonmark,slack}` since v0.1.7 (verified in
the ft repo: v0.1.7 contains `SlackExport`, v0.1.6 does not; the
changelog's duplicate 0.1.7/0.1.8 entries are a release-script
artifact — the tag check is authoritative). The CLI's value enum is the
single source of truth for valid format names; clap rejects anything
else.

## Goals / Non-Goals

**Goals:**
- `export.format` config + `:FtExport [format]` per-invocation override,
  threaded through the existing rangeop pipeline with the default path
  byte-identical to today.
- `MIN_FT_VERSION` 0.1.5 → 0.1.7.
- Tests at all three tiers, including a version-gate case for the new
  floor.

**Non-Goals:**
- No Lua-side validation or knowledge of what each format *does* (the
  mrkdwn conversion rules are ft's domain — pillar 1.1). The plugin
  passes a name through and completes from a static protocol-surface
  list.
- No per-format operators/keymaps, no count-prefix format selection
  (see Decisions 3).
- No new ft-side surface; no changes to quote or rangeop's public API.

## Decisions

**1. Effective-format rule: pass `--format` iff ≠ CLI default.**
The argv builder resolves the effective format (per-invocation override
→ config → `'commonmark'`) and emits `--format <name>` only when it is
not the CLI's `commonmark`. Consequences:
- Default config produces argv byte-identical to today — the existing
  Tier 2 stub assertions (`notes export inbox.md -l 1-2 --json-errors`)
  keep passing unchanged, and the ARCHITECTURE.md §2 note stays true
  with a small amendment ("the plugin passes `--format` only when a
  non-default format is configured or requested").
- The override back to commonmark (`:FtExport commonmark` under a
  `'slack'` config) still passes `--format commonmark` explicitly —
  the *plugin* default is no longer the CLI default, so "≠ CLI
  default" and "≠ plugin default" differ and the former is correct.
*Alternatives rejected:* always pass the resolved format — more
explicit, but churns every existing invocation's argv, every Tier 2
assertion, and the protocol row for zero user-visible benefit;
"pass iff ≠ plugin default" — breaks the override-back case.

**2. Where the format lives.** `export.setup(cfg)` stores the
configured format next to `registers`. `export.export_range(a, b,
fmt)` / `export.export_whole_file(fmt)` take an optional override arg
(nil → configured format); the operator/visual/selection entry points
pass nothing (configured default); `:FtExport` passes its optional
arg. The rangeop `cmd` closures close over the resolved format and
insert `--format <name>` after the rel path (`{'notes', 'export', rel,
'--format', fmt, '-l', s, '--json-errors'}`); clap accepts any flag
order, this one reads naturally. The argv construction is extracted
into a pure helper (`export.cmd_args(rel, spec, fmt)`) so Tier 1 can
pin it without spawning anything.
*Alternative rejected:* extending `rangeop.run` with a format option —
rangeop is the shared quote/export core; format is export-only surface.

**3. No count-prefix format selection.** `1gy`/`2gy` to pick a format
was considered and rejected: verified empirically in nvim that a count
before the `gy` expr mapping propagates to the motion (`2gyw` = 2-word
export, `vim.v.count == 2` in the operatorfunc), so hijacking it breaks
the documented `gy3j` motion-count ergonomics. The command-arg override
is the idiomatic, discoverable path; the config covers the persistent
case.
*Alternative rejected:* per-format operators (e.g. `gy` + `gys`) —
keymap bloat, and the operator key is already configurable.

**4. `:FtExport [format]`** becomes `-nargs=?` (0 or 1) with
`-complete=customlist` over a static `export.formats = { 'commonmark',
'slack' }` list. The list is editor glue (completion + docs), not
validation: an unknown value passes through and ft's clap error
surfaces through the existing classifier (message ≠ `outside file` →
ERROR, registers untouched). The list lives in export.lua next to the
argv builder, and the ARCHITECTURE.md protocol row records it as part
of the consumed surface so it moves when ft adds a target.
*Alternative rejected:* validating in Lua for a friendlier message —
duplicates ft's enum (pillar 1.1); the CLI is the contract.

**5. Version floor 0.1.5 → 0.1.7.** The floor moves with the first
release carrying the newly-consumed surface, per the protocol-contract
rule. Soft-check semantics unchanged. With an old binary + a slack
config, the user gets the setup warning and, on first use, ft's
"unexpected argument '--format'" classified ERROR — the established
drift behavior, no special-casing.
*Alternative rejected:* keeping 0.1.5 and letting slack silently fail —
the floor exists exactly to prevent silent misbehavior; a format-aware
plugin must not claim 0.1.5 support.

**6. Notification.** The success text gains `(<format>)` when the
effective format is not the CLI default (`ft: exported L1-2 (slack) →
", f, +`). Commonmark-path text unchanged, so existing Tier 2
notification assertions survive.

## Risks / Trade-offs

- **"≠ CLI default" coupling** → if ft ever changes its default format,
  the plugin's "no flag" path silently means the new default. Mitigation:
  the ARCHITECTURE.md protocol row pins the CLI default explicitly, the
  same way it pins everything else in the contract; the Tier 3 smoke
  test asserts commonmark output from the no-flag path, catching a
  default flip loudly.
- **Old binary + slack config** → setup warns; first export surfaces
  ft's clap error. Mitigation: documented in the README/docs; the Tier
  2 version-gate test pins the warning.
- **Completion list drift** (ft adds `plain` later, plugin list stale)
  → completion misses a valid name but the flag still works when typed.
  Mitigation: the protocol table in ARCHITECTURE.md is the single
  registry; updating it is part of any surface change.
- **Rangeop cmd closures now capture format** → the existing quote path
  is untouched (quote builds its own cmd), so no cross-op regression
  risk.

## Migration Plan

No breaking changes: the default path is byte-identical, config keys
are additive, and `:FtExport` remains valid with zero args. Old configs
keep working. Rollback = revert the change; nothing persisted.

## Open Questions

None — the remaining unknowns (exact stub canned output, smoke fixture
content) are implementation details that do not affect specs or design.
