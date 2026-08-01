## Context

The plugin is editor glue over the `ft` CLI (ARCHITECTURE.md): all task
domain logic lives in ft, Lua only wires outputs to the editor. The
plugin already owns `ft.rpc` (argv-building transport), `ft.vault`
(discovery, `is_inside_vault`), and the note-index cache with
dirty-marking. The `ft tasks` CLI (0.1.0) already supports everything
this change consumes: `create --file/--at-line/--force/--due`, `complete
|cancel <file>:<line> --yes`, global `--vault` and `--json-errors`. See
proposal.md for motivation.

The one unavailable piece — CLI subtask creation — is explicitly
deferred (user adds the ft flag later); this design does not touch ft.

## Goals / Non-Goals

**Goals:**
- A `ft.tasks` module whose three entry points (`create`, `done`,
  `cancel`) map 1:1 onto `ft tasks` invocations, with save-before-mutate
  and undo-preserving reload as shared pre/post steps.
- Inline `due:` extraction that mirrors the TUI quickline grammar for the
  `due:` token only, passing raw values through to `--due` (no date
  computation in Lua).
- Deterministic, idempotent update semantics driven by ft's own errors.

**Non-Goals:**
- Subtask creation (deferred; documented in ARCHITECTURE.md as the known
  CLI gap).
- Other quickline tokens (`sched:`, `start:`, `pri:`, `in:`, `id:`,
  `every`, `#tag` handling) — tags already flow through the description
  text; the rest are follow-ups that extend the same extractor.
- Vault-wide task pickers / `ft tasks list` integration.
- Machine-readable success output from ft (`--format` on mutations) —
  not needed: after create the new line is known (`--at-line N`),
  after done/cancel the cursor simply stays put.

## Decisions

### D1. `due:` extraction lives in Lua; date resolution stays in ft

The CLI does not parse quickline syntax (`ft tasks create` takes a plain
description), and the user is deferring ft changes. Lua therefore walks
the whitespace tokens of the description, pulls out `due:<value>`
(case-insensitive prefix, `\due:` escape), and passes `<value>` verbatim
as `--due`. ft's `dates::parse` then resolves `+2d` / `today` / ISO /
natural language and serializes the ISO date — the domain logic. This is
argument plumbing, not task-line parsing (allowed under pillar 1.1; the
same split the TUI's own quickline uses, just mirrored in Lua).

- *Alternative rejected:* a second `--due` prompt — forced users to split
  their intent across two dialogs; user explicitly asked for the inline
  form.
- *Alternative rejected:* defer due: to an ft-side quickline parser —
  cross-repo dependency the user wants to make themselves later.
- *Handoff note:* when ft's CLI grows inline parsing, the plugin drops
  its extractor and passes the raw description through; the spec's
  observable behavior (`due:+2d` → ISO date) is unchanged.

### D2. Update flow uses `<file>:<line>` + `--yes` + `--json-errors`

Done/cancel pass the vault-relative path and cursor line as the
selector (`ft tasks complete <rel>:<line> --yes`). `--yes` makes the
multi-candidate path deterministic (error listing candidates) rather
than interactive — under the rpc sync call stdin is never a TTY anyway,
but the flag pins the behavior. `--json-errors` gives structured
stderr; the rpc sync call merges both streams, so on failure the plugin
decodes `{"error": ...}` and classifies:

- complete on already-done: ft exits 1 with `is already done` →
  idempotent: info notify, no reload, no error.
- cancel on already-cancelled: **ft's CLI already exits 0** (the
  `AlreadyCancelled` case is skipped, not errored) → the plugin treats
  it as a plain success: reload, no error, no classification needed.
- "no tasks match selector" (line is not a task) → warn notify, no
  reload.
- everything else (line changed on disk, …) → error notify, no reload.

Substring classification of ft's stable error strings is pinned by
Tier 2 stub tests (see D5).

### D3. Save-before-mutate: unconditional `write` + `modified` check

Every operation runs `silent! write` first, then verifies
`vim.bo.modified` is now false; if still modified (read-only, unnamed
buffer, write error) it aborts with a notify before building any argv.
Unconditional write keeps the disk copy fresh even for externally
changed buffers; the check catches every failure mode without parsing
write errors.

### D4. Reload = `:edit`, which preserves undo and file-change state

After a successful mutation the plugin runs `:edit` on the buffer. This
was chosen after verifying empirically that `:edit` does **not** wipe
undo history: the reload lands as a single undoable step, so a later
`u` returns to the pre-mutation buffer state (pinned by a Tier 2 test
using the documented `let &g:undolevels = &g:undolevels` undo-block
break). `:edit` also refreshes nvim's file-change tracking — the
`set_lines` alternative left the buffer's read-timestamp stale, so the
next `:write` prompted a spurious "file has been changed since reading"
confirmation. Buffer is unmodified at reload time (saved in preflight),
so plain `:edit` never hits E37. For create, the cursor is explicitly
set to `{N, 0}` where N was the pre-mutation cursor line —
`Position::AtLine` guarantees the new task occupies line N. For
done/cancel, the cursor is left untouched (the completed line stays at
N; a recurring task's next instance lands at N, which is an acceptable
resting spot).

- *Alternative rejected:* whole-buffer `nvim_buf_set_lines` + `nomodified`
  — leaves b_mtime stale (spurious changed-file prompts), needs manual
  `modified` juggling, and its one-undo-step claim is no better than
  `:edit`'s.

### D5. Test strategy: three tiers, stub binary for editor behavior

- **Tier 1** (`tests/run.lua`, hermetic): `tasks.parse_due` pure
  function (token forms, escape, repeats, empty value, case), a new
  `vault.relativize` helper, and the existing source-scan guard (now
  also covering `tasks.lua`).
- **Tier 2** (new `tests/tasks_stub.lua` or extension of a stub
  harness): a stub `ft` script emitting canned stdout + exit codes;
  asserts the exact argv received (so the stub must echo its argv),
  save-before-spawn ordering, idempotent classification, undo
  preservation, and create-cursor placement — all without a real
  binary.
- **Tier 3** (`tests/smoke.lua`): real ft binary + fixture vault;
  create at cursor (disk + reload + cursor), done, cancel, `due:+2d`
  → ISO date, duplicate create allowed, already-done idempotency.

### D6. Config and wiring

`tasks.keymaps = { create = '<leader>tt', done = '<leader>td', cancel =
'<leader>tc' }` (each `false`-disableable), registered as buffer-local
keymaps in `_setup_buffer` like follow. Commands are global user
commands that check vault membership at invocation (like `:FtFollow`).
`lua/ft/vault.lua` gains `relativize(path)` — strips the vault root
prefix from an absolute path — used for both `--file` and the selector.

## Risks / Trade-offs

- **[`due:` grammar drift]** The Lua extractor mirrors the TUI quickline
  only for `due:`. If the TUI grammar changes (new escape, renamed
  token), the mirror can diverge → Mitigation: the extractor is a tiny
  pure function pinned by Tier 1 tests; the handoff path (ft-side
  parsing) is documented in D1 so the mirror has a retirement plan.
- **[Error-string coupling]** Idempotency classification matches ft's
  English error text ("is already done") → Mitigation: Tier 2 stub tests
  pin the classification; the strings come from `translate_complete_error`
  / `translate_cancel_error`, which are stable protocol surface.
- **[Recurring tasks shift lines]** Completing a recurring task inserts
  the next instance *above* the completed line, moving the completed
  task to N+1; the plugin keeps the cursor at N (on the next instance).
  Documented behavior, not a bug.
- **[`--force` means duplicates are real]** The user chose
  duplicate-allowed; `--force` disables ft's guard wholesale (same
  description+dates). Trade-off accepted per requirement.

## Migration Plan

Pure additive change: new module + commands + config keys; no existing
behavior changes. No data migration. Rollback = revert the change
commit; `tasks` config keys are ignored by older versions (unknown keys
in `vim.tbl_deep_extend('keep', ...)` are harmless).

## Open Questions

None that affect the spec, approach, or task breakdown.
