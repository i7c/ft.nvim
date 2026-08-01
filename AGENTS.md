# AGENTS.md

`ft.nvim` is the Neovim plugin for **`ft`** — a Rust CLI + TUI over an
Obsidian vault (tasks, wikilinks, queries, synthesis). This file is the
quick map for agents working in this repository. The durable design
record — and the foundation for all development here — is
**[ARCHITECTURE.md](ARCHITECTURE.md)**: read it fully before changing
code, and keep it in sync when behavior changes. This file only
summarizes what it assumes and adds the workflow and test rules.

## The two repositories

| Repo | Hosted at | Role |
|---|---|---|
| `ft` | https://github.com/i7c/ft | The CLI + TUI. ALL domain logic lives here: task lines, emoji format, query DSL, dates, synth callouts, link graph. |
| `ft.nvim` | https://github.com/i7c/ft.nvim | **This plugin.** Neovim glue: shells out to the `ft` binary, parses machine-readable output, wires it to the editor. No domain logic. |

The one-sentence contract, from ARCHITECTURE.md:

> **The plugin is editor glue plus a transport. Every byte of domain
> logic lives in the `ft` CLI; Lua only wires ft's outputs to the editor.**

Consequences that shape every change:

- **The CLI is the contract.** The plugin depends on a specific ft CLI
  surface, enumerated in ARCHITECTURE.md §2 ("The ft CLI protocol
  contract"). When ft's side of that table changes, the table and the
  plugin's `MIN_FT_VERSION` floor change together.
- **Cross-repo coordination lives in `ft`.** An openspec change in the
  ft repo is the coordination artifact for work touching both sides;
  tasks that land in this repo are tagged `[ft.nvim]` there. This repo's
  openspec covers plugin-local changes only.
- **ft stays editor-agnostic.** New plugin needs become general CLI
  features (machine-readable output, `--json-errors`, stable `--format`),
  never editor-specific hooks. This plugin is the primary poweruser path,
  but ft must work for any editor.

## Load-bearing patterns

The architecture rests on four pillars (ARCHITECTURE.md §1); the patterns
below are the ones agents must not break.

- **Domain logic lives in ft, never in Lua (pillar 1.1).** The plugin
  SHALL NOT parse/serialize task lines, evaluate the query DSL, compute
  dates, or serialize callouts. If a planned Lua feature finds itself
  doing any of that, stop and add an ft command instead (ARCHITECTURE.md
  §5 draws the line). The source-scan test in `tests/run.lua` enforces
  this mechanically: no module other than `ft.rpc` may spawn the ft
  process.
- **The transport seam (`ft.rpc`, pillar 1.2).** All plugin↔ft traffic
  flows through `lua/ft/rpc.lua`: `rpc.call(args)` (sync, quick ops) and
  `rpc.job(args, kind, on_done)` (async, single-flight per kind with
  dirty-flag coalescing — the newest request wins, at most one
  follow-up job). `rpc.build_cmd` produces direct argv tables (no shell,
  no quoting), injects `--vault <root>` when the vault root is known,
  and resolves the bin as `$FT_BIN` before `ft` on PATH.
- **Derived caches, event-driven invalidation (pillar 1.3).** Caches
  (the `ft.cache` note index) are derived from disk, never
  authoritative. Vault events (`BufWritePost`/`BufDelete`/`BufNewFile`
  on `.md` inside the vault) mark them dirty; rebuilds are lazy and
  single-flight; every rebuild bumps a monotonic **generation counter**
  and consumers that captured an older generation re-derive at use time.
- **The picker seam (`ft.picker`, pillar 1.4).** `ft.picker.select`
  defaults to `vim.ui.select`, which delegates to whatever picker the
  user configured globally. Telescope/fzf-lua are feature-detected,
  opt-in backends. `ft.picker.multi` is declared but not implemented —
  it raises a clear error until a real multi-select backend exists.
- **No embeds.** Inline `![[embed]]` rendering was removed in the
  architecture v2 rework; the plugin is not a Markdown renderer. Do not
  resurrect it. Legacy config keys are silently ignored (a smoke test
  pins this).
- **Concurrency contract with the ft TUI (ARCHITECTURE.md §3).** nvim
  is most often launched from inside the ft TUI as `$EDITOR`. The plugin
  inherits `FT_VAULT` (checked first), **never notifies the TUI** (in
  the suspend strategy the TUI is blocked and cannot respond — any such
  design deadlocks), and every ft operation spawns a **fresh child
  process**. Consistency is ft's expected-task guard, not locking.
- **Soft version floor.** `MIN_FT_VERSION` (currently `0.1.0`) is
  checked at setup: an older binary warns, never fails. Hard version
  enforcement is the integration suite's job, not setup's.

## Build invariants

Three make targets; the split is deliberate:

```sh
make test    # Hermetic unit tests — no ft binary needed (nvim --headless -l tests/run.lua)
make smoke   # Integration tests — REQUIRES a real ft binary ($FT_BIN or PATH)
make check   # = make test (safe everywhere)
```

Every change must keep `make test` green. When you have a built binary
(`FT_BIN=../ft/target/release/ft`), also run `make smoke` — CI does both.

## Testing strategy

The architecture — a thin client over a domain-logic binary — gives the
testing story a natural shape: **three tiers, all runnable with plain
`nvim --headless -l`**, the pattern `tests/run.lua` and `tests/smoke.lua`
already establish. Keep the `ok()` / failure-count / `cquit` summary
convention of those suites in any new test file.

### Tier 1 — hermetic unit tests (no ft binary)

Fast, deterministic, run on every change and in every environment.
Covers pure Lua: parsing, argv construction, precedence, comparisons.
Because all domain logic lives in ft, the pure surface here is small —
that is a feature, not a gap.

Must cover (add cases as these modules grow):

- `ft.rpc`: `resolve_bin` precedence (`$FT_BIN` → PATH → nil),
  `build_cmd` argv shape (bin, `--vault` injection when the root is
  known, verbatim passthrough otherwise), `parse_version` (suffix,
  newline, garbage, nil), `version_lt` (equal, older patch, major wins).
- `ft.vault`: discovery precedence (`FT_VAULT` → explicit config →
  walk-up), cache/reset behavior.
- `ft.wikilink`: `parse_wikilinks`/`parse_body`/`wikilink_at_cursor` for
  every form — `[[Target]]`, `[[Target|Alias]]`, `[[Target#Heading]]`,
  `[[Target#Heading|Alias]]`, `[[#Heading]]`, `[[#Heading|Alias]]`,
  `![[Embed]]`, unclosed `[[`, empty body — plus byte-offset/col mapping
  for cursor hit-testing. This parser is currently the largest untested
  pure surface; any change to it must bring its own tests.
- `ft.picker`: backend resolution (`auto`/`select`/`telescope`/
  `fzf-lua`, feature detection).
- The **source-scan guard**: no spawn terms (`vim.fn.system`,
  `io.popen`, `jobstart`) outside `rpc.lua`, no removed-helper remnants.

### Tier 2 — editor-glue tests with a *stub* ft binary

The plugin's editor behavior — follow opens/jumps, completion triggering,
cache invalidation and generation bumps, version warnings — does not need
real ft semantics; it needs **deterministic output**. A stub `ft` (a
small shell/Lua script emitting canned ndjson / `--version` lines) makes
these hermetic too (the smoke test's old-version stub is the seed of
this pattern).

Must cover:

- `follow.follow_wikilink` for each wikilink form against a stubbed
  `ft find`: opens the target buffer, jumps to the heading line,
  same-buffer `[[#Heading]]` anchor jump.
- `ft.cache`: a stubbed `ft graph query` populates the index; a
  dirty-marking vault event triggers a lazy rebuild; `generation()`
  bumps on rebuild and stays stable without one; `search` honors
  case-insensitivity and limits.
- `ft.rpc.job` single-flight: with a slow stub (or a stubbed
  `vim.fn.jobstart`), a request while in flight coalesces to at most one
  follow-up, newest wins, `User ft:rpc-done` fires with
  `kind/stdout/exit_code`.
- The version gate: an old-version stub fires the soft warning; a
  current stub does not.
- Missing-binary behavior: with no `ft` on PATH and no `$FT_BIN`,
  `rpc.call` notifies and returns `nil, -1` instead of crashing.

### Tier 3 — contract tests with a *real* ft binary

The tier that makes ARCHITECTURE.md §2 executable. For every row of the
protocol contract table, run the command against a fixture vault and
assert the output parses through the plugin's own code paths. A real
nvim + a real ft binary + a fixture vault exercises the whole stack:
Lua → argv → ft → disk → parsed output → editor state.

- **Fixtures:** checked-in fixture vaults under `tests/fixtures/`,
  mirroring ft's own `tiny/` / `realistic/` / `pathological/` split
  (e.g. ghost links to not-yet-created notes belong in `pathological/`).
  Tests **copy** fixtures into `vim.fn.tempname()` dirs and set
  `FT_VAULT`; never mutate fixtures in place, never touch a real vault.
  The current `smoke.lua` builds its vault ad hoc — fixture files are
  the upgrade path.
- **Binary availability is explicit, not implicit.** `make smoke` fails
  fast with a clear message when no binary is found. Locally, run the
  **newest** binary you have (`$FT_BIN` for dev builds of ft, else
  PATH): the plugin's features track the latest protocol surface, so
  newest is correct. In CI, pin a known-good ft release (or build ft
  from source) — don't silently rely on whatever the runner has.
- **Assert the floor.** The suite hard-asserts the available binary's
  version is `>= MIN_FT_VERSION`. The soft warn covers runtime; the
  suite catches a stale PATH binary loudly instead of letting features
  misbehave silently.
- **Async delivery:** use `vim.wait(timeout, predicate)` and assert on
  `cache.is_ready()`/generation, never on wall-clock sleeps.
- If date-dependent behavior ever lands in the plugin, drive it with
  `FT_TODAY` (ft's deterministic-date seam).

### What this stack guarantees

- Tier 1 catches parser/argv/precedence regressions in seconds, anywhere.
- Tier 2 catches editor-behavior regressions deterministically, without
  a binary — CI stays green even when ft isn't installed.
- Tier 3 catches contract drift — the exact failure mode that makes a
  thin client lie (the plugin expects one shape, ft emits another) —
  with the real binary the plugin will run against.

A change that touches only Lua needs Tier 1 (+ Tier 2 for editor glue).
A change that touches the CLI surface needs Tier 3, and must also update
ARCHITECTURE.md §2 and `MIN_FT_VERSION` if the floor moves.

## Where to add things

- **New Lua module:** `lua/ft/<name>.lua` + wiring in `init.lua`. If it
  parses, serializes, or computes domain data, stop — add an ft command
  instead (ARCHITECTURE.md §5).
- **New ft surface consumed by the plugin:** update the protocol
  contract table in ARCHITECTURE.md §2, adjust `MIN_FT_VERSION` if the
  floor moves, add a Tier 3 contract test, and keep README + `doc/ft.txt`
  in sync.
- **New feature:** one Tier 1 test per pure function, one Tier 2 test
  per editor behavior, one Tier 3 test per protocol-table row touched.
- **New test file:** `tests/<name>.lua`, runnable standalone with
  `nvim --headless -l tests/<name>.lua`, wired into the Makefile.

## Conventions to keep

- No ft process spawns outside `rpc.lua` (source-scan enforced).
- argv **tables**, never shell strings; no shell interpolation, no
  `:!ft` commands; `--vault <root>` prefixed whenever the root is known.
- `$FT_BIN` (dev builds) before `ft` on PATH.
- Vault-relative paths in user-facing output and errors.
- Don't add backwards-compat shims for removed surfaces (e.g. embeds) —
  delete; legacy config keys are ignored silently, pinned by a test.
- Comments only when the *why* is non-obvious; don't narrate the *what*.
- Keep README, `doc/ft.txt`, and ARCHITECTURE.md honest when behavior
  changes (note: `doc/ft.txt` currently still documents embeds — fix it
  next time that file is touched).

## Change workflow (openspec)

Plugin-local non-trivial changes follow the same openspec discipline as
ft: propose → apply → archive under `openspec/` with the `.pi/skills`
(`openspec-propose`, `openspec-apply-change`, `openspec-archive-change`,
`openspec-explore`, `openspec-update-change`). Work that touches both
repositories is coordinated by an openspec change in the **ft** repo
with `[ft.nvim]`-tagged tasks; this repo's openspec covers the plugin
side alone.

- **Explore first, build on confirmation.** In a fresh session, assume
  the task is exploration and design until the user explicitly asks for
  implementation.
- **Commit the spec before applying.** An openspec change is its own
  commit; the implementation lands as a follow-up commit. Do this
  without being asked.
