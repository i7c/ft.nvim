# ft.nvim

Neovim plugin for [ft](https://github.com/i7c/ft) — an Obsidian vault CLI toolkit.

Navigate `[[wikilinks]]` and autocomplete note titles — all inside Neovim, backed by `ft`'s fast vault-aware link resolution.

> **Note:** `![[embeds]]` inline rendering is **no longer supported**. It was removed in the architecture v2 rework; the plugin is not a Markdown renderer (see [ARCHITECTURE.md](ARCHITECTURE.md)).

## Features

- **Follow wikilinks** — `gf` on `[[Target]]`, `[[Target|Alias]]`, `[[Target#Heading]]`, or `[[#Heading]]` opens the linked note (or jumps to the heading) in the current window
- **Autocompletion** — type `[[` and note titles from your vault appear in the completion menu. Integrates natively with **blink.cmp** (LazyVim default); falls back to `'omnifunc'`
- **Task operations** — create, create subtasks, mark done, cancel, and edit the due date of tasks without leaving nvim (`:FtTaskCreate`, `:FtTaskSubtask`, `:FtTaskDone`, `:FtTaskCancel`, `:FtTaskDue`). The create prompt accepts inline due dates (`Buy milk due:+2d`); the due command prompts for a date (`+7d`, `next monday`, or `none` to clear). The buffer is saved before each mutation and reloaded after, undo history intact

## Requirements

- Neovim >= 0.9
- [ft](https://github.com/i7c/ft) CLI tool on `$PATH`

## Install

### lazy.nvim / LazyVim

```lua
{
  dir = '~/path/to/ft.nvim',       -- or a git remote
  lazy = true,
  ft = 'markdown',
  config = function()
    require('ft').setup({
      follow = { keymap = 'gf' },
      completion = { enable = true },
    })
  end,
}
```

### packer

```lua
use({
  '~/path/to/ft.nvim',
  config = function()
    require('ft').setup()
  end,
})
```

## Configuration

All options with their defaults:

```lua
require('ft').setup({
  vault = nil,               -- explicit vault path, or nil for auto-discover
  follow = {
    keymap = 'gf',           -- normal-mode key to follow wikilinks
  },
  completion = {
    enable = true,           -- autocomplete note titles on [[
  },
  tasks = {
    keymaps = {
      create = '<leader>tt', -- create a task at the cursor line
      subtask = '<leader>ts',-- create a subtask under the cursor task
      done = '<leader>td',   -- mark the task under the cursor done
      cancel = '<leader>tc', -- cancel the task under the cursor
      due = '<leader>te',    -- set/clear the due date under the cursor
      -- set any to false to disable the keymap (command still works)
    },
  },
  picker = {
    backend = 'auto',        -- 'auto' | 'select' | 'telescope' | 'fzf-lua'
  },
})
```

### Vault discovery

ft.nvim discovers your Obsidian vault in this order:

1. `FT_VAULT` environment variable
2. `vault` option in `setup()`
3. Walking up from the current buffer's directory for `.obsidian/`
4. Walking up from the current working directory

## Commands

- `:FtFollow` — follow the `[[wikilink]]` under the cursor (same as `gf`)
- `:FtTaskCreate` — create a task at the cursor line (prompt supports `due:+2d` inline dates)
- `:FtTaskSubtask` — create a subtask under the task at the cursor line (repeat to add siblings; the cursor stays put)
- `:FtTaskDone` — mark the task under the cursor done (`<leader>td`)
- `:FtTaskCancel` — cancel the task under the cursor (`<leader>tc`)
- `:FtTaskDue` — set/clear the due date of the task under the cursor (`<leader>te`; enter `none` to clear)

Task operations save the buffer before running `ft` and reload it after
(undo preserved). Marking an already-done/cancelled task is a no-op.
See `:help ft-tasks` for details.

## Architecture

The plugin is **editor glue plus a transport**: every byte of domain logic
(task lines, queries, dates, synth callouts) lives in the `ft` CLI, which
is driven through the single `ft.rpc` seam — nothing else spawns the `ft`
process. Caches are derived and invalidated on vault events; pickers go
through the `ft.picker` seam. The full model — including the ft CLI
protocol contract, the freshness model, and the concurrency contract with
the ft TUI — is documented in
**[ARCHITECTURE.md](ARCHITECTURE.md)**.

```
lua/ft/
  init.lua      — setup(), FileType autocmd, user commands, version check
  vault.lua     — vault discovery (FT_VAULT → config → walk-up)
  rpc.lua       — the ONLY module that talks to the ft binary (sync + async)
  wikilink.lua  — [[Target]], [[Target|Alias]], [[#Heading]] parser
  follow.lua    — follow wikilink under cursor
  tasks.lua     — task create/subtask/done/cancel/due (save, mutate, reload)
  cache.lua     — note list cache from ft graph query (async, invalidated)
  complete.lua  — blink.cmp registration or omnifunc fallback
  blink.lua     — blink.cmp source for wikilink completion
  picker.lua    — picker seam (vim.ui.select default, telescope/fzf-lua opt-in)
```

All CLI communication goes through `ft.rpc`: synchronous `call()` for
quick ops, asynchronous `job()` (single-flight per kind) for slow ones.
The note cache is rebuilt once per session via `ft graph query` and
after every vault write event. Embed content rendering was removed in
the architecture v2 rework.

## License

MIT
