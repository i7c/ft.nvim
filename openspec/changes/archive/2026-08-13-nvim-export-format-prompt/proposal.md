# nvim-export-format-prompt — Proposal

## Why

`gy`/`:FtExport` always export `commonmark` — the `--format` flag of
`ft notes export` is never passed, so the second format (slack) is
unreachable from the editor. Users who want a Slack-ready copy have no
way to get one, and the upcoming plain-text format would suffer the
same gap.

## What Changes

- The export command prompts for the export format before copying to
  the registers, on every entry point: `gy` operator, visual `gy`, and
  `:FtExport` (whole-file and ranged).
- The prompt lists the hardcoded available formats (`commonmark`,
  `slack`) with the CLI's one-line descriptions, via the existing
  `ft.picker` seam (defaults to `vim.ui.select`, so the user's
  configured picker). Cancelling the prompt aborts silently — no ft
  call runs, no register is touched.
- New config `export.format`: `'commonmark'` or `'slack'` skips the
  prompt and exports that format directly; `'prompt'` (the default)
  always asks. Invalid values fall back to `'prompt'` silently
  (consistent with the plugin's ignore-legacy-config posture).
- The chosen format is passed as `--format <name>` on the argv and
  named in the success notification (`ft: exported L1-2 (slack) → …`).
- ARCHITECTURE.md §2 protocol table updated: `--format <FORMAT>` is now
  passed (no longer "CLI default, not passed").

## Capabilities

### New Capabilities

- none

### Modified Capabilities

- `notes-export`: the export flow gains a format-selection step
  (prompt or configured default) that feeds `--format` into the argv,
  with a config switch to skip the prompt; the success notification
  names the format.

## Impact

- `lua/ft/export.lua` — the format list (hardcoded), the
  resolve/prompt step, `--format` argv injection, notification text.
- `lua/ft/init.lua` — `export.format` config default (`'prompt'`) and
  merge.
- `lua/ft/picker.lua` — consumed via the existing `select` seam; no
  change (the seam is the contract, `vim.ui.select` delegates to the
  user's picker).
- `lua/ft/rangeop.lua` — unchanged (argv tail stays operation-owned;
  the format prompt lives in `export.lua`).
- `ARCHITECTURE.md` §2 — protocol contract table row for
  `ft notes export`.
- README / `doc/ft.txt` — document the new `export.format` config and
  the prompt.
- `openspec/specs/notes-export/spec.md` — main spec gains the
  format-selection requirement (via sync after archive).
- Tests: `tests/export_stub.lua` (prompt/cancel/config-skip argv
  shapes), possibly a headless picker-driving test.
