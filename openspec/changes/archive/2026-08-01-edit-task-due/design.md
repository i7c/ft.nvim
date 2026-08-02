## Context

The plugin's `ft.tasks` module already owns the shared mechanics for
in-editor task ops (see proposal.md): save-before-mutate (`_save_buffer`),
undo-preserving `:edit` reload (`_reload_from_disk`), `--json-errors`
classification, and the `<file>:<line>` selector flow used by done/cancel
(`_update`). The `ft tasks edit <selector> --due <DATE|none>` CLI
primitive exists in 0.1.0 and is single-task (requires a selector). This
design adds a due-date edit operation that reuses all of that.

## Goals / Non-Goals

**Goals:**
- A `set_due()` entry point that mirrors done/cancel: exact
  `<file>:<line>` selector, prompt → argv → classification.
- The prompt value passes through verbatim — ft resolves the date, Lua
  never computes one.

**Non-Goals:**
- Editing other task fields (scheduled, priority, tags, description) —
  `ft tasks edit` supports them, but scope is due-only per the request;
  the same helper generalizes later.
- Pre-filling the prompt with the task's current due date — that would
  require reading it back from ft (a second `ft tasks list` call + output
  parsing) for marginal gain; a blank prompt with `none` to clear is the
  established create-style pattern.
- Bulk / `--query` edit (ft's own v1 limitation).

## Decisions

### D1. `set_due()` reuses the done/cancel selector-op shape

A shared `_update(op)`-style flow, specialized for edit: preflight
(save) → read cursor line → prompt → re-validate → `ft tasks edit
<rel>:<line> --due <value> --json-errors` → reload on exit 0 →
classify on failure. Empty prompt input cancels before any argv is
built (no `--due` with an empty value, no accidental clearing — `none`
is the explicit clear).

- *Alternative rejected:* a generic `:FtTaskEdit` prompting for a field
  selector — more surface than the request; due-only keeps the prompt
  single-purpose and the tests tight.

### D2. Classification is a subset of done/cancel's

`ft tasks edit` fails with the same selector errors as complete/cancel:
"no tasks match selector" → warn, everything else (invalid date, line
changed on disk, unreadable file) → error. There is no idempotent
already-state case: re-setting the same due date is a plain success
(exit 0), so no marker classification is needed.

### D3. Command/keymap naming

`:FtTaskDue` and `tasks.keymaps.due = '<leader>te'` — the `t`-prefix
family (tt/td/tc/te) stays uniform; `false` disables the keymap but not
the command, matching the existing pattern.

### D4. Test strategy

- **Tier 1** (`tests/run.lua`): nothing new is pure — the prompt
  handling and argv building are covered at Tier 2. The source-scan
  guard already covers `tasks.lua`.
- **Tier 2** (`tests/tasks_stub.lua`): the stub gains an `edit` branch
  (rewrite the `📅`-bearing due date on the selector line, canned
  `no_match` / `hard_error` modes); assert argv shape
  (`edit <rel>:<line> --due <value>`), empty-prompt cancel (no argv),
  `none` passthrough, warn/error classification, reload.
- **Tier 3** (`tests/smoke.lua`): real binary — set `+2d` (line shows
  the ISO date), clear with `none` (date gone), non-task line warns.

## Risks / Trade-offs

- **[ft edit semantics drift]** `ft tasks edit`'s `--due` accepts
  `none` as a magic clear value; if ft changes that form, the plugin's
  passthrough breaks → Mitigation: Tier 3 smoke pins `none` behavior
  against the real binary.
- **[Prompt is blank, not pre-filled]** Users can't see the current due
  date in the prompt; they must know the task already has one. Accepted
  for v1 (mirrors create); a pre-filled prompt is a documented follow-up
  if it proves annoying.

## Migration Plan

Pure additive: new command + config key + keymap; no behavior changes
to existing ops. Rollback = revert the change commit.

## Open Questions

None that affect the spec, approach, or task breakdown.
