## Context

The plugin is editor glue over the ft CLI (see ARCHITECTURE.md). `tasks.lua`
already implements create-at-cursor / done / cancel / due on shared
`_preflight` (vault discovery + save-to-disk) and `_reload_from_disk`
(`:edit` reload + cache-dirty) mechanics, plus `parse_due` for inline `due:`
tokens. The new op slots into that machinery — see proposal.md for the "why".

ft's `--parent` flag (merged as ft change `tasks-create-parent`, shipping in
ft 0.1.4):
- resolves the selector against a vault-wide scan and requires exactly one
  match; `<file>:<line>` is an **exact** selector, so the plugin can never
  hit the multi-match ambiguity error
- places the child via `Position::Subtask`: it matches the first existing
  child's leading whitespace verbatim (tabs included), or falls back to
  `parent indent + 2 spaces` when the parent has no children, and splices the
  line after the parent's entire indented block
- conflicts at the clap layer with `--file` / `--under-heading` / `--at-line`
  / `--append`; composes with `--force`, `--due`, `--json-errors`

The plugin already classifies ft's stable `no tasks match selector` error as
a WARN for the done/cancel/edit ops (spec: task-ops).

## Goals / Non-Goals

**Goals:**
- create a subtask of the task under the cursor with an empty prompt
- keep the cursor on the parent line after success so repeated invocations
  add siblings
- full parity with existing ops: save-before-mutate, reload + cache
  invalidation, error classification
- protocol table row and `MIN_FT_VERSION` 0.1.4 moving together

**Non-Goals:**
- no id / fuzzy parent selectors in the plugin (CLI/TUI surface only; the
  plugin uses the exact `<rel>:<line>` selector)
- no Lua-side task-line detection (pillar 1.1: the ft round trip plus WARN
  classification is the established pattern)
- no cursor jump to the new subtask (see decision 3)
- no changes to ft itself — the CLI surface already landed

## Decisions

1. **Separate `:FtTaskSubtask` command + `tasks.keymaps.subtask`** default
   `<leader>ts` (`false` disables the keymap; the command always works).
   Mirrors the roadmap note already in ARCHITECTURE.md. Alternative rejected:
   a flag on `:FtTaskCreate` — the two placement modes carry conflicting arg
   sets (`--parent` vs `--file`/`--at-line`), and the prompt semantics differ
   (empty vs pre-fill), so one command would need two branches.

2. **Parent captured at invocation, not at prompt confirm.** The line is read
   once before the input prompt; the selector is fixed even if the cursor
   moves while the user types. Rationale: "subtask of the task I pointed at".
   This is a deliberate divergence from `create`, which re-reads the cursor
   at confirm time. Alternatives: re-read at confirm (retargets on cursor
   move — surprising), re-read only when the line changed (complexity for a
   rare case).

3. **Cursor stays on the parent line after success.** `_reload_from_disk`
   then explicitly `nvim_win_set_cursor({parent_line, 0})`. Because
   `Position::Subtask` always splices below the parent's block, the parent's
   line number never shifts, so the position is stable across repeated
   invocations — the multi-subtask flow is "`ts`, type, Enter, `ts`, type,
   Enter". Alternatives: (a) parse `Created task at <path>:<line>` from ft's
   stdout and jump to the child — rejected: brittle prose parsing with no
   machine-readable output today, and it breaks the repeated-siblings flow;
   (b) leave the cursor wherever `:edit` lands it — rejected: not
   deterministic; the explicit set matches `create`'s pattern.

4. **Empty prompt default.** The current line is the parent (already a task),
   not a draft to convert; pre-filling would suggest the parent's own text as
   the child's description. `parse_due` is reused so inline `due:` behaves
   exactly like create.

5. **`--force` passed unconditionally** (parity with create): ft's file-wide
   duplicate check and `--force` bypass are unchanged for `--parent` creates.

6. **`MIN_FT_VERSION` → 0.1.4** together with the protocol-table row
   (AGENTS.md: the table and the floor change together). Pre-0.1.4 binaries —
   including current dev builds, which still report `ft 0.1.0` from
   Cargo.toml — will trigger the soft setup warning, which is honest: a
   released 0.1.0 / 0.1.3 binary cannot create subtasks.

7. **Non-task line → WARN** via the existing `no tasks match selector`
   marker, with no Lua-side pre-check (pillar 1.1).

## Risks / Trade-offs

- [User expects the cursor to land on the new subtask] → deliberate; the
  repeated-siblings flow is the primary use case, documented in README and
  `doc/ft.txt`.
- [Floor bump warns against dev builds reporting 0.1.0] → soft warning only,
  never a failure; the smoke version test uses a stub, so no suite breakage.
- [No machine-readable "created at" output is consumed] → we avoid a brittle
  prose parse; if a future feature needs the new line, the right move is a
  `--json` / machine-readable mode in ft, not Lua-side parsing.
- [Tier 2 stub must emulate `--parent`] → the stub's `create` branch gains a
  `--parent` path (mutate the fixture file, emit success / canned `no tasks
  match selector`); keeps Tier 2 hermetic.
