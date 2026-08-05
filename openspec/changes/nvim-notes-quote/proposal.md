# nvim-notes-quote — quote a note section as a protected section from nvim

## Why

The ft synth flow pins source paragraphs into protected sections
(`[!ft-source]` callouts) so `ft notes synth verify` can later confirm
they still match the git blob they came from. The TUI owns that flow,
but nvim — the primary poweruser path, launched from the TUI as
`$EDITOR` — has no way to pin an editor selection. The next ft release
carries `ft notes quote`, the read-only plumbing command that emits the
canonical callout for a line range to stdout; this change wires it into
nvim as a true operator so any selection or motion can be quoted into
the registers and pasted into any other note.

## What Changes

- New `lua/ft/quote.lua` — editor glue over `ft notes quote` (no domain
  logic: the callout text passes through unparsed):
  - **True operator `gz`**: normal-mode operator taking motions
    (`gzap`, `gz3j`, `gzgG`, …) via `g@` + `operatorfunc`; in visual
    mode `gz` quotes the current selection. `:FtQuote` command quotes
    the current line (normal mode) or the selection (visual mode).
  - **Registers**: the callout is placed **linewise** into the unnamed
    register `"` (plain `p` pastes), a named register `"f` (stable home
    for repeated paste), and the system clipboard `"+` (survives closing
    nvim and opening it elsewhere). `quote.registers` config trims any
    of the three; clipboard failure degrades silently.
  - **Save-before-quote**: the buffer is written first so disk == what
    the user sees (same pattern as the task ops). A source file with
    uncommitted changes surfaces ft's error as a WARN with a "commit or
    stash" hint — the plugin never touches git. A failed quote leaves
    the registers untouched.
- `init.lua`: `:FtQuote` user command, `quote` config section
  (`keymaps.operator`, `registers`), and `MIN_FT_VERSION` moves to the
  release carrying `ft notes quote`.
- ARCHITECTURE.md: protocol contract table gains the `ft notes quote`
  row; the roadmap "synth notes" row drops its "future render-only
  `--print`" note (quote is that plumbing, now consumed).
- README + `doc/ft.txt`: quote usage and the paste/verify note (a
  pasted section is only checked by `synth verify` in a note carrying
  `ft.synth.enabled: true` frontmatter).
- Tests: Tier 1 pure helpers, Tier 2 stub-binary suite (new
  `tests/quote_stub.lua`), Tier 3 smoke against a real ft binary + git
  fixture vault, including the hard version-floor assert the suite
  mandates but does not yet implement.

## Capabilities

### New Capabilities

- `notes-quote`: quoting a line range of the current note as a
  protected section via `ft notes quote` — operator/command/visual
  entry points, linewise register placement (unnamed + named +
  clipboard), save-before-quote, classified error surfacing, and the
  config surface.

### Modified Capabilities

- None. `task-ops` is untouched; the callout grammar, pin semantics,
  and verify behavior are all ft-side and unchanged.

## Impact

- **This repo**: new `lua/ft/quote.lua`; `init.lua` (command, keymaps,
  config defaults, `MIN_FT_VERSION` bump); ARCHITECTURE.md (protocol
  table + roadmap); README + `doc/ft.txt`; `tests/run.lua`,
  `tests/quote_stub.lua` (new), `tests/smoke.lua`, Makefile.
- **ft CLI (consumed, unchanged)**: `ft notes quote <FILE> --lines A-B`
  (short `-l A-B`), global `--vault` and `--json-errors` — in the next
  ft release. `MIN_FT_VERSION` moves to that release; the exact number
  is ft's release call (≥ 0.1.5).
- **Explicitly out of scope**: the ft-side version-reporting fix (being
  fixed independently in ft); any paste-side helper (e.g. inserting
  `ft.synth.enabled: true` frontmatter into the destination note —
  deferred to a follow-up change); auto-commit or any git mutation from
  the plugin.
