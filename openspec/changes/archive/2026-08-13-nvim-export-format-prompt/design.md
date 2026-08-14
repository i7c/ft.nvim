# nvim-export-format-prompt — Design

## Context

See proposal.md — Why. Current state: `gy`/`:FtExport` always export
`commonmark`; the plugin's `export.lua` builds the argv tail
(`notes export <rel> [-l A-B] --json-errors`) and delegates the
preflight/save/classify/register pipeline to the shared
`ft.rangeop.run`. The consumed CLI surface (`ft notes export`) accepts
`--format commonmark|slack` (plain text planned but not yet accepted);
`commonmark` is the CLI default. The picker seam (`ft.picker.select`)
defaults to `vim.ui.select`, which delegates to the user's configured
picker. Confirmed with the user: prompt on **all** entry points,
picker seam with descriptions, config `export.format` with `'prompt'`
default, format named in the notification, format list hardcoded.

## Goals / Non-Goals

**Goals:**

- One resolution step (config-format or prompt) feeding a single
  `--format <name>` into every export argv, on every entry point.
- The prompt is skippable via config for scripted/automated use.
- Cancel is a true no-op (no ft call, no register write, no noise).

**Non-Goals:**

- Parsing/serializing exported text (domain logic stays in ft —
  pillar 1.1).
- Dynamic format discovery from `ft --help` — the list is hardcoded
  (Q5), consistent with the protocol-contract approach in
  ARCHITECTURE.md §2.
- Changing `quote` (`gz` has no format).
- Paste-side helpers or format previews.

## Decisions

### D1. Format resolution lives in `export.lua`, before `rangeop.run`

`rangeop.run` stays operation-agnostic: its `cmd` builder already
returns the full argv tail, so the format is just another token the
export module's builder includes. The resolution (config check →
picker → abort on cancel) is export-specific and lives in
`export.lua`, wrapped around the `rangeop.run` call. The flow:

```
export_range(a, b) / export_whole_file()
  → resolve_format(cfg, function(fmt)   -- sync when configured, async when prompting
       rangeop.run(spec, { cmd = function(rel, s)
         return { 'notes', 'export', rel, '-l', s, '--format', fmt, '--json-errors' }
       end, ... })
     end)
```

**Alternative rejected**: putting the prompt inside `rangeop` — would
couple the shared pipeline to picker UI and export's format list.

### D2. Prompt via `ft.picker.select`; cancel is a silent no-op

`ft.picker.select(items, { prompt, format_item }, cb)` — items are
`{ id, desc }` pairs (hardcoded, desc from the CLI help text), the
prompt names the target note/range, and the callback receives the
chosen item (or `nil` on cancel, the `vim.ui.select` convention). On
`nil` the callback returns immediately: no ft call, no register
write, no notification — the picker closing is feedback enough.
The callback may fire synchronously (default `vim.ui.select` /
`inputlist`-based backends) or asynchronously (telescope/fzf-lua);
the code must not assume sync-after-call.

### D3. Config `export.format`: `'prompt'` default, unknown → prompt

`export.format` accepts `'commonmark'` / `'slack'` (skip the prompt,
use directly) or `'prompt'` (always ask). Any unrecognized value is
treated as `'prompt'` silently — no validation error, matching the
plugin's ignore-legacy-config posture. Implemented as a lookup table
`known[format]` in `export.lua`; the default lands in `init.lua`'s
`defaults.export.format = 'prompt'`.

### D4. Success notification names the format

`success` callback becomes
`'ft: exported L' .. s .. ' (' .. fmt .. ') → ' .. table.concat(set, ', ')`
(whole-file variant: `'ft: exported whole note (' .. fmt .. ') → …'`).
The empty-output INFO message is unchanged — "frontmatter and callout
headers" are stripped by both formats.

### D5. Stub-test strategy: the picker seam is stubbed, not the prompt UI

Tier 2 tests override `vim.ui.select` (which `ft.picker.select`
delegates to) with a canned choice, so `export_range` stays directly
callable:

- default stub returns the first item (`commonmark`) — most existing
  assertions survive, only the exact argv strings gain
  `--format commonmark`
- a `slack` stub asserts `--format slack` + notification `(slack)`
- a cancel stub (`cb(nil)`) asserts no ft call (empty log) and
  registers untouched
- a config-skip scenario sets `export.format = 'slack'` and asserts
  **no** picker call happens

The stub binary must consume `--format <value>` in its arg loop
(currently it only knows `--vault` / `-l` / `--json-errors`; `--format`
would otherwise be misread as the file token).

## Risks / Trade-offs

- [Operator flow now pauses on a prompt] → inherent to the requested
  design; cancel is a clean no-op, and config `export.format` skips
  the prompt for automation. The g@ operator resolves the range before
  the prompt, so the motion is never lost.
- [Scripted/`:FtExport`-in-macros usage now blocks on the prompt] →
  documented: set `export.format` for non-interactive use.
- [Format list can go stale if ft adds formats] → the protocol
  contract table in ARCHITECTURE.md §2 is the coordination artifact;
  adding a format updates the table, the hardcoded list, and the spec
  in the same change (same discipline as the CLI surface generally).
- [Headless `vim.ui.select` default (inputlist) would hang tests] →
  Tier 2 stubs the seam; smoke/Tier 3 asserts against the real binary
  with a configured format (no prompt).

## Migration Plan

Additive: new config key with a default, no migration. Rollback =
revert the argv tail and remove `export.format`; the prompt disappears
with them.

**Floor moves 0.1.5 → 0.1.7.** Verified against ft's git history:
`ft notes export` first ships in v0.1.6 (already carrying
`--format`, value enum `commonmark` only), and `--format slack` lands
in v0.1.7. Since the plugin now always passes `--format <name>` and
offers both values, v0.1.7 is the first release carrying the full
consumed surface; the floor moves with the protocol table (AGENTS.md
rule), and the stale init.lua comment claiming export ships in 0.1.5
is corrected while touching the floor.

## Open Questions

None — Q1–Q5 resolved with the user (all entry points, picker seam +
cancel aborts, config `'prompt'` default, notification names format,
hardcoded list).
