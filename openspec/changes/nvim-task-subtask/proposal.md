## Why

`ft tasks create` now supports `--parent <selector>` (ft `tasks-create-parent`,
shipping in ft 0.1.4): creating a task as an indented subtask of an existing
task. The plugin already creates, completes, cancels, and edits tasks under the
cursor; this change adds the missing operation — creating a subtask of the task
under the cursor — so task hierarchies can be built without leaving the editor.

## What Changes

- New `:FtTaskSubtask` user command and `tasks.keymaps.subtask` config key,
  default `<leader>ts` (`false` disables the keymap; the command still works).
- `tasks.create_subtask()`: runs `ft tasks create <desc> --parent <rel>:<line>
  --force --json-errors [--due <v>]` — the parent selector is the current
  buffer's vault-relative path plus the cursor line captured at invocation.
  `--file`/`--at-line` are deliberately NOT passed (clap-level conflicts with
  `--parent`).
- Subtask prompt has an **empty default** (the current line is the parent, not
  a draft); the inline `due:<value>` token works exactly as in `:FtTaskCreate`.
- After a successful create the buffer reloads from disk and the **cursor
  stays on the parent's line**, so repeated invocations add sibling subtasks.
- A non-task line under the cursor surfaces ft's `no tasks match selector` as
  a warning (parity with done/cancel).
- `MIN_FT_VERSION` raised to 0.1.4 (the release carrying `--parent`).
- Docs: README, `doc/ft.txt`, ARCHITECTURE.md protocol table + roadmap.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `task-ops`: adds create-subtask-under-cursor behavior, its prompt + inline
  due handling, the subtask command + keymap, and subtask failure
  classification.

## Impact

- `lua/ft/tasks.lua` — new `create_subtask()` reusing the shared
  `_preflight`/`_reload_from_disk`/`parse_due` mechanics.
- `lua/ft/init.lua` — command registration, keymap default, `MIN_FT_VERSION`.
- `openspec/specs/task-ops/spec.md` — synced at archive.
- ARCHITECTURE.md, README, `doc/ft.txt`.
- Tests: `tests/tasks_stub.lua` (Tier 2), `tests/smoke.lua` (Tier 3).
- ft CLI contract: `ft tasks create --parent` (already landed in ft; plugin
  floor becomes 0.1.4).
