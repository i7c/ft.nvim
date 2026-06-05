--- ft.nvim — Neovim integration for `ft` (Obsidian vault toolkit).
---
--- Provides:
--- - `:FtFollow` or `gf` — follow [[Wikilinks]] to the target note or heading
---
--- Setup:
--- ```lua
--- require('ft').setup({
---     vault = nil,       -- explicit vault path, or nil for auto-discover
---     follow = {
---         keymap = 'gf', -- keymap to follow wikilinks (set to false to disable)
---     },
--- })
--- ```
---
--- @module ft

local follow = require('ft.follow')
local vault = require('ft.vault')

local M = {}

local defaults = {
    vault = nil,
    follow = {
        keymap = 'gf',
    },
}

-- Merged config
local config = {}

--- Setup ft.nvim.
--- Should be called from your Neovim config (init.lua / lazy.nvim spec).
---
--- @param opts table|nil  Configuration options
function M.setup(opts)
    config = vim.tbl_deep_extend('keep', opts or {}, defaults)

    -- Discover vault (best-effort; discovery state is cached so follow
    -- can check it at invocation time).
    vault.discover(config.vault)

    -- Register user commands
    vim.api.nvim_create_user_command('FtFollow', function()
        follow.follow_wikilink()
    end, { desc = 'Follow [[wikilink]] under cursor' })

    -- Set up keymap for following wikilinks
    --
    -- When the default `gf` key is used, the mapping deliberately
    -- does NOT fall through: if the cursor isn't on a wikilink, we
    -- show a brief info message rather than attempting built-in gf.
    -- This avoids the complexity of trying to invoke the original
    -- mapping while keeping the behaviour predictable. Users who
    -- want full gf compatibility can use :FtFollow as a command or
    -- bind a different key like <leader>wf.
    if config.follow.keymap then
        vim.keymap.set('n', config.follow.keymap, function()
            follow.follow_wikilink()
        end, { desc = 'ft: follow [[wikilink]] under cursor' })
    end
end

--- Explicitly check that the vault is reachable.
--- Useful for statusline integrations.
--- @return boolean
function M.vault_ready()
    return vault.get_vault() ~= nil
end

return M
