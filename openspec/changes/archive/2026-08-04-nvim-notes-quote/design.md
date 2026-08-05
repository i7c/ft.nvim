# nvim-notes-quote — Design

## Context

The plugin is editor glue over the ft CLI (see ARCHITECTURE.md): all
communication flows through `ft.rpc` (argv tables, `--vault` injected
when the root is known, stderr merged into the sync return), and no
module other than `rpc.lua` may spawn the ft process (source-scan
guard in `tests/run.lua`). The consumed surface is `ft notes quote
<FILE> -l A-B` (next ft release): read-only, emits the canonical
`[!ft-source]` callout to stdout, exits 1 with a human message on
stderr when the file is dirty vs HEAD, not in a git repo, missing, or
the range is out of bounds. `tasks.lua` establishes the save-before /
reload / classify-error patterns this change reuses.

See proposal.md for motivation; the specs define the required
behavior.

## Goals / Non-Goals

**Goals:**

- A true operator (`gz`) plus visual and command entry points that all
  funnel into one `quote_range(a, b)` core.
- Register placement that makes plain `p` work and survives nvim
  sessions for `clipboard=unnamedplus` users, degrading silently.
- Honest failures: the user always learns why a quote failed, and the
  registers never lie (a failed quote writes nothing).

**Non-Goals:**

- Any parsing/serialization of the callout (domain logic stays in ft —
  pillar 1.1).
- Git interaction of any kind (no commit/stash prompts, no git
  spawning — would violate the source-scan guard and the plugin's
  editor-glue role).
- Paste-side helpers (frontmatter marker insertion into the
  destination note — deferred to a follow-up change; documented in
  README/`doc/ft.txt`).
- Auto-append/preview UIs, counts on the operator, multi-select.

## Decisions

### D1. One core function, three entry points

`quote_range(a, b)` is the only code path that runs ft; the operator
callback, the visual keymap, and `:FtQuote` all resolve to it. This
mirrors `tasks.lua`'s single-preflight shape and keeps the stub tests
able to drive every entry point by calling the same core.

**Alternative rejected**: separate flows per entry point — three
copies of preflight/argv/classification.

### D2. `gz` is a real operator via `g@` + `operatorfunc`

Normal mode: `vim.keymap.set('n', 'gz', function() … return 'g@' end,
{ expr = true })` — an expr mapping that sets
`vim.o.operatorfunc = 'v:lua.require("ft.quote").operatorfunc'` and
returns `g@`; the motion that follows is applied, `'[`/`']` mark the
covered range, and the callback runs `quote_range(line("'["),
line("']"))`. Visual mode maps `gz` directly and reads `'<`/`'>`.

Verified headless against a 5-line buffer: `gz` + `ap`/`ip`/`j`/`k`/
`w`/`e`/`b`/`3j`/`gg`/`G`/`{` all produce correct ranges, and the
cursor lands on the range's first line after the op (standard operator
behavior — lets users grow a quote with repeated `gz`+motion).

**Rejected**: `gzgz` double-tap for "current line" — it requires an
operator-pending mapping of `gz` to a no-op motion, and no-op motions
(`0`, `l`) produce unreliable or inverted `'[`/`']` marks under `g@`.
Current line is covered by `:FtQuote` in normal mode (and `V` + `gz`).

**Known limitation**: screen-line motions `gj`/`gk` don't produce a
usable range under `g@` (observed headless with `wrap` on). In
unwrapped markdown notes they are equivalent to `j`/`k`, which work;
documented in `doc/ft.txt`, not worked around.

### D3. Registers: `"` + `f` + `"+`, linewise, configurable, silent degradation

`setreg(reg, content, 'l')` for each enabled target. `"` makes plain
`p` paste (consistent with yank-like operator semantics — quoting
clobbers the unnamed register exactly like `yap` does); `f` is the
stable home the plugin owns, untouched by other yanks; `"+` covers
cross-session paste. With `clipboard=unnamedplus` (assumed for the
cross-session story) `"` and `"+` are the same register, so writing
both is idempotent; without it, `"+` still works where supported and
otherwise degrades.

Degradation path: if `vim.fn.has('clipboard')` is 0, or `setreg('+')`
returns 0 (provider failure), skip the clipboard silently and continue
with `"`/`f`. The success notification lists the registers that
actually landed, so a missing clipboard is visible but never an error.
"Silent failure" means no error notification — the accurate success
message is the only signal.

**Rejected**: clipboard-only (breaks plain `p`); failing loudly when
the clipboard is unavailable (punishes users who only paste in-session).

### D4. Save-before-quote, then let ft's own errors speak

Same `_save_buffer` preflight as `tasks.lua`: write only when
`modified`, abort if the write fails. This makes disk == screen, so a
successful quote pins exactly what the user sees, and a dirty file's
error is true. Error classification matches the exact anyhow messages
from `ft/src/cmd/quote.rs`, decoded from the `--json-errors` object
(reusing the `_ft_message` decode pattern):

| stderr marker | level | surfaced as |
|---|---|---|
| `has uncommitted changes` | WARN | ft's message + "commit or stash, then quote again" |
| `line range L… outside file` | WARN | ft's message |
| `not inside a git repository` | ERROR | ft's message |
| `cannot read source file` | ERROR | ft's message |
| anything else | ERROR | ft's message |

The plugin never maps these to actions — the WARN/ERROR split plus the
hint text is the whole UX (matches how `tasks.lua` classifies
already-done vs not-a-task).

**Rejected**: auto-commit or a commit prompt (git is a vault-domain
mutation and outside the ft protocol surface); "quote without saving"
(produces callouts that don't match the screen).

### D5. Failure leaves the registers alone

Registers are written only after exit 0. A blocked quote preserves the
previous quote — a failed op is not a quote. (Confirmed with the user.)

### D6. Floor moves; no per-op version guard

`MIN_FT_VERSION` moves to the release carrying `ft notes quote`
(≥ 0.1.5 — exact number is ft's release call). No per-invocation
version check: the setup soft-warning covers old binaries, and the
error classification turns an old binary's `unrecognized subcommand`
into a plain error. The smoke suite gains the hard floor assert
(AGENTS.md mandates it; `tests/smoke.lua` currently lacks it) — made
meaningful by the ft-side version-reporting fix, which is being done
independently and is out of scope here.

**Rejected**: a feature-level version guard in `quote.lua` — it would
duplicate the setup warning and add cached-version plumbing for a case
(installed binary older than the feature) the soft floor already
covers.

## Risks / Trade-offs

- [`gz` prefix collides with built-in `gz` scroll] → `gz` in normal
  mode is currently unmapped-by-us and the built-in scroll is rarely
  the second key of a deliberate sequence; configurable and disable-able
  (`quote.keymaps.operator = false`), and `:FtQuote` always works.
- [Uncommitted files block quoting — whole-file check, not per-range]
  → inherent to the pinning contract (the file's blob at HEAD is the
  pin target); the WARN hint tells the user the remedy (commit/stash).
  Documented in `doc/ft.txt`.
- [Quoting clobbers the unnamed register] → expected yank-like
  operator semantics; `"f` preserves the section, and disabling the
  unnamed register is one config line.
- [Headless `gj`/`gk` unreliability under `g@`] → equivalent to
  `j`/`k` in unwrapped notes; documented, not mitigated.
- [Dirty files block the common "write freely then quote" flow] →
  the honest error + hint is the design; the alternative (silent
  mismatch between screen and pin) is worse.

## Migration Plan

No migration: additive feature, new module + config section with
defaults. Rollback = remove the `quote` config and keymaps; the
`MIN_FT_VERSION` bump warns only (soft floor). The protocol table and
README revert with the code.

## Open Questions

None — the decisions above are the resolved ones (operator model,
register set + degradation, save-first, error classification, floor
mechanism, paste-side scope) confirmed with the user. The exact floor
version number is a release-timing detail filled at implementation.
