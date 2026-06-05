# ft.nvim

Neovim plugin for [ft](https://github.com/cmw/ft) — an Obsidian vault CLI toolkit.

Navigate `[[wikilinks]]`, autocomplete note titles, and render `![[embeds]]` inline — all inside Neovim, backed by `ft`'s fast vault-aware link resolution.

## Features

- **Follow wikilinks** — `gf` on `[[Target]]`, `[[Target|Alias]]`, `[[Target#Heading]]`, or `[[#Heading]]` opens the linked note (or jumps to the heading) in the current window
- **Autocompletion** — type `[[` and note titles from your vault appear in the completion menu. Integrates natively with **blink.cmp** (LazyVim default); falls back to `'omnifunc'`
- **Embed rendering** — every `![[linked note]]` visible in the viewport is rendered inline with a coloured gutter and indented content. Updates on scroll and cursor move

## Requirements

- Neovim >= 0.9
- [ft](https://github.com/cmw/ft) CLI tool on `$PATH`

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
      embeds = {
        enable = true,
        max_lines = 20,
      },
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
  embeds = {
    enable = true,           -- render ![[embeds]] inline
    max_lines = 20,          -- max content lines per embed
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

## Architecture

```
lua/ft/
  init.lua      — setup(), FileType autocmd, user commands
  vault.lua     — vault discovery, ft CLI wrapper
  wikilink.lua  — [[Target]], [[Target|Alias]], ![[embed]] parser
  follow.lua    — follow wikilink under cursor
  cache.lua     — note list cache from ft graph query
  complete.lua  — blink.cmp registration or omnifunc fallback
  blink.lua     — blink.cmp source for wikilink completion
  embed.lua     — inline embed rendering with gutter + indent
```

All CLI communication goes through `vault.ft_run()` which shells out to the `ft` binary. The note cache is populated once per session via `ft graph query`. Embed content is cached by file mtime and evicted on buffer write.

## License

MIT
