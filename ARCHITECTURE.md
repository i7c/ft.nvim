# ft.nvim — Architecture

This file is the durable record of how `ft.nvim` is shaped and why. It is
the plugin counterpart of `docs/architecture.md` in the `ft` repository:
the coordination artifact for cross-repo changes lives in `ft`'s openspec
changes; the knowledge artifact lives here.

The one-sentence summary:

> **The plugin is editor glue plus a transport. Every byte of domain
> logic lives in the `ft` CLI; Lua only wires ft's outputs to the editor.**

---

## 1. The four pillars

### 1.1 Domain logic lives in ft, never in Lua

The plugin SHALL NOT parse or serialize task lines, evaluate query DSL,
compute dates, or serialize synth callouts. Operations that produce or
transform domain data are delegated to `ft` commands; Lua handles only
editor concerns (selection, insertion, cursor movement, viewport
rendering of ft-provided data).

Why: ft's task serializer is canonical (field order, `✅ YYYY-MM-DD`
dates, priority emoji), the ops layer carries an **expected-task guard**
that fails with `LineChanged` on any mismatch, and parent/child task
structure is resolved inside ft. Hand-written task lines in Lua would be
latent round-trip failures. One rule, no judgement calls.

**The test that enforces it:** `tests/run.lua` scans `lua/ft/` and fails
if any module other than `rpc.lua` spawns the ft process.

### 1.2 The transport seam (`ft.rpc`)

All plugin↔ft communication flows through `lua/ft/rpc.lua`. Two tiers:

- `rpc.call(args)` — synchronous, for quick ops (follow, task create at
  cursor, find). `vim.fn.system` with a table argv — no shell.
- `rpc.job(args, kind, on_done)` — `vim.fn.jobstart`, for slow ops
  (gather, pulse, index rebuilds). Result delivered to `on_done` and as
  a `User ft:rpc-done` autocmd (`vim.v.event` = kind/stdout/exit_code).
  **Single-flight per kind** with dirty-flag coalescing: a request while
  one is in flight keeps only the newest and runs at most one follow-up.
  This mirrors the ft TUI's `GraphJob { in_flight, dirty }` pattern.

Bin resolution: `$FT_BIN` (dev builds) before `ft` on PATH. When the
vault root is known, every command is prefixed `--vault <root>` so ft
does not re-walk the filesystem.

**Transport is a deliberate non-decision.** CLI-per-op is the model until
it is measured to be the bottleneck. A future stdio JSON-RPC mode would
implement the same `call`/`job` signatures; nothing else changes. There
is deliberately no `ft server` and no channel to a *running* ft process
(see §3).

### 1.3 State & freshness: derived caches, event-driven invalidation

Caches are **derived**, never authoritative — disk and git are the source
of truth. Today the only caches are the note index (`ft.cache`) and the
vault root (`ft.vault`).

- Invalidation is event-driven, not timer-driven: `BufWritePost` /
  `BufDelete` / `BufNewFile` on `.md` files inside the vault, plus the
  plugin's own mutations, mark the index dirty.
- A dirty cache is rebuilt lazily on next use, single-flight (via
  `rpc.job`), so bursts coalesce.
- Every rebuild bumps a monotonic **generation counter**
  (`cache.generation()`); consumers that captured an older generation
  (e.g. a picker opened before a rebuild) re-derive at use time. This is
  the same invariant as the ft TUI's shared graph snapshot: tabs consume,
  never build.

### 1.4 The picker seam (`ft.picker`)

`ft.picker.select(items, opts)` — single-choice picker. Default backend
is `vim.ui.select`, which **delegates**: most picker setups override it
globally (telescope, dressing, fzf-lua), so the zero-dep default
automatically becomes whatever picker the user configured. Telescope and
fzf-lua backends are feature-detected and used only when the user opts in
(`picker = { backend = 'auto' | 'select' | 'telescope' | 'fzf-lua' }`).

`ft.picker.multi(items, opts)` is **declared but not implemented**:
`vim.ui.select` has no multi-select concept, so multi-select needs a real
backend. The first feature that requires it (Gather's
send-selected-entries-to-synth) forces that decision; until then it
raises a clear error instead of silently degrading to single-select.

---

## 2. The ft CLI protocol contract

The plugin depends on a specific CLI surface of the `ft` binary. This
table is the dependency manifest — when the ft side of the table changes,
this file and the plugin's `min_ft_version` check change with it.

| ft command | Flags / format | Used by | Notes |
|---|---|---|---|
| `ft --version` | — | `init.lua` version check | Soft warn only (see `MIN_FT_VERSION`) |
| `ft graph query` | `node where kind in {Note, Ghost}` `--format ndjson` | `cache.lua` (note index) | Ghost nodes included so links to not-yet-created notes complete |
| `ft find` | `<query>` `--format ndjson --limit 1 --include-headings` | `follow.lua` | Resolves `[[Target]]`, `[[Target#Heading]]` to a vault-relative path + line |
| `ft tasks create` | `<description>` `--file <rel> --at-line <N> --force [--due <date>] --json-errors` | `tasks.lua` (create at cursor) | `--force` makes duplicates allowed; the plugin extracts the inline `due:` token itself (the CLI does not parse quickline syntax) and passes the raw value through — ft resolves relative/keyword dates to ISO |
| `ft tasks complete` | `<file>:<line>` `--yes --json-errors` | `tasks.lua` (done) | Exact selector for the task under the cursor; already-done exits 1 with `is already done` (classified as info, not error); recurring tasks write their next instance |
| `ft tasks cancel` | `<file>:<line>` `--yes --json-errors` | `tasks.lua` (cancel) | Already-cancelled already exits 0 (idempotent at the CLI) |

Error classification for the update ops matches ft's stable error
strings (`is already done`, `no tasks match selector`), pinned by the
Tier 2 stub tests.

The plugin's `MIN_FT_VERSION` floor (currently `0.1.0`) is checked at
setup: an older binary produces a warning, never a failure.

### Roadmap surface (not yet consumed)

Features on the roadmap will extend the table. The ft-side additions
needed for them are deferred to the changes that build the features:

| Feature | ft command to add / use | Notes |
|---|---|---|
| Create task / subtask in place | `ft tasks create --at-line N --file <buf>` | Create-at-line is **consumed today** (`tasks.lua`); subtask creation needs a new CLI flag — `Position::Subtask` exists in ft-core but the CLI only exposes `--at-line`/`--under-heading`/`--append`. Deferred: the ft change lands first, then a follow-up plugin session adds `:FtTaskSubtask`. |
| Gather flow | `ft notes gather --link [[X]] --json` | `--json` exists; async tier required (git-blame scale) |
| Pulse | `ft notes pulse --json` | Exists today |
| Synth notes | `ft notes synth scaffold … --no-edit` (+ a future render-only `--print` mode) | `--print` would emit the note body to stdout for in-buffer splicing |

---

## 3. Concurrency contract with the ft TUI

nvim is most often launched **from inside the ft TUI** (as `$EDITOR`).
The ft TUI's editor handoff — all strategies, suspend or tmux — parks the
TUI process for the whole editor session: it blocks waiting for the
editor to exit, then **unconditionally force-refreshes its graph
snapshot** against on-disk state. The plugin's design consequences:

1. **Discovery is free.** The editor child inherits `FT_VAULT`; the
   plugin checks it first (highest precedence).
2. **The plugin never notifies the TUI of anything.** There is no channel
   and must not be one: in the suspend strategy the TUI is blocked in
   `Command::status()` and cannot respond to IPC until nvim exits. Any
   design requiring a live ft response during an editor session
   deadlocks. All plugin ft operations spawn **fresh child processes**.
3. **The consistency mechanism is ft's expected-task guard**, not
   locking. The worst case — two ft processes touching the vault
   concurrently (a parked TUI, a plugin job, a tmux-pane edit) — is the
   normal "external editor + CLI" situation ft already handles.

---

## 4. Decision log

| Decision | Chosen | Alternatives rejected |
|---|---|---|
| Where domain logic lives | In ft; Lua is glue + transport | Reimplementing the emoji format / DSL in Lua (drift, guard trips, round-trip failures) |
| Transport | CLI-per-op through `ft.rpc`; no server until measured | `ft server` / stdio JSON-RPC (solves latency, not freshness); channel to the running TUI (deadlocks in suspend strategy) |
| Slow ops | Async `rpc.job`, single-flight per kind | Blocking `vim.fn.system` for seconds (freezes nvim) |
| Freshness | Derived caches + event invalidation + generation | Always re-run at use time (scan per keystroke); timer-based refresh (stale windows, no correctness at the moment that matters) |
| Picker | Seam; `vim.ui.select` default (delegates); backends opt-in | Telescope now (heaviest dep, nothing needs previews yet); fzf-lua now (another binary, nothing needs it yet); custom mini-picker (~300–600 LOC permanently ours — violates pillar 1.1's spirit) |
| Embeds | **Removed** (breaking) | Keeping them: the one feature that made the plugin a Markdown renderer — a role ft explicitly disclaims — and the highest-maintenance surface (viewport tracking, gutter layout, per-note reads) |
| Repos | ft.nvim standalone; openspec coordination in `ft`; protocol-as-contract | Submodule (second copy of a repo that must stay standalone for lazy.nvim install; couples source layout when the contract is the CLI protocol); monorepo (breaks install URL) |
| Version coupling | `min_ft_version` soft check + protocol table | Hard failure on old binaries (annoying); no check (silent breakage) |

---

## 5. When to add an ft command vs Lua

- **Add to ft** (a command or a CLI flag): any operation that produces or
  transforms domain data — task lines, queries, dates, callouts,
  dedup, provenance. Also: any expensive computation the plugin would
  otherwise reimplement. New ft surfaces must be general CLI features
  (machine-readable output, `--json-errors`, stable `--format`), not
  editor-specific hooks — ft-core and the ft TUI stay compatible with
  *any* editor; neovim + ft.nvim is the primary poweruser path but
  restricts nothing.
- **Add to the plugin (Lua)**: editor integration only — pickers, keymaps,
  buffer text splicing, autocmd invalidation, statusline hints, loading
  states. If a planned Lua feature finds itself parsing, serializing,
  or computing domain data, stop and add an ft command instead.

---

## 6. Development

- **Point the plugin at a dev build:** `FT_BIN=/path/to/ft/target/release/ft`
  nvim — no `cargo install` needed. `rpc.resolve_bin()` honors it first.
- **Unit tests (no ft binary needed):** `make test` →
  `nvim --headless -l tests/run.lua` — source-scan guard (no ft spawns
  outside `rpc.lua`) + pure-function tests (`build_cmd`,
  `parse_version`).
- **Smoke test (real ft + real nvim):**
  `FT_BIN=../ft/target/release/ft make smoke` →
  `nvim --headless -l tests/smoke.lua` — fixture vault, follow,
  completion index, version warning.
