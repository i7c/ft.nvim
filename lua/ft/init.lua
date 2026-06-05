--- ft.nvim — Neovim integration for `ft` (Obsidian vault toolkit).
---
--- Features:
--- - `:FtFollow` or `gf` — follow [[Wikilinks]] to the target note or heading
--- - Wikilink autocompletion — auto-triggers on `[[`, completes note titles
--- - Embed rendering — shows `![[linked note]]` content inline in normal mode
---
--- Setup:
--- ```lua
--- require('ft').setup({
---     vault = nil,        -- explicit vault path, or nil for auto-discover
---     follow = {
---         keymap = 'gf',  -- keymap to follow wikilinks (false to disable)
---     },
---     completion = {
---         enable = true,  -- enable wikilink autocompletion
---     },
---     embeds = {
---         enable = true,  -- enable embed rendering in normal mode
---     },
--- })
--- ```
---
--- @module ft

local follow = require('ft.follow')
local vault = require('ft.vault')

local M = {}

-- Autocommand group for buffer-level setup.
local setup_augroup = vim.api.nvim_create_augroup('ft_setup', { clear = true })

local defaults = {
    vault = nil,
    follow = {
        keymap = 'gf',
    },
    completion = {
        enable = true,
    },
    embeds = {
        enable = true,
        max_lines = 20,  -- max content lines per embedded note
    },
}

-- Merged config.
local config = {}

--- Setup ft.nvim.
--- Should be called from your Neovim config (init.lua / lazy.nvim spec).
---
--- @param opts table|nil  Configuration options
function M.setup(user_opts)
    -- Accept both `embed` and `embeds` config keys (user-friendly alias).
    local opts = vim.deepcopy(user_opts or {})
    if opts.embed ~= nil and opts.embeds == nil then
        opts.embeds = opts.embed
    end
    opts.embed = nil

    config = vim.tbl_deep_extend('keep', opts or {}, defaults)

    -- Discover vault (best-effort; discovery state is cached so follow
    -- can check it at invocation time). Do this early so submodules
    -- that need the vault path can rely on it during setup.
    vault.discover(config.vault)

    -- Defer per-buffer setup until a markdown file is opened inside the vault.
    vim.api.nvim_create_autocmd('FileType', {
        group = setup_augroup,
        pattern = 'markdown',
        callback = function(ev)
            -- Re-discover vault from the new buffer's perspective.
            vault.discover(config.vault)
            if not vault.get_vault() then
                return -- not inside a vault yet
            end

            M._setup_buffer(ev.buf)
        end,
    })

    -- Register user commands (available globally even outside markdown
    -- files, will show an appropriate error).
    vim.api.nvim_create_user_command('FtFollow', function()
        follow.follow_wikilink()
    end, { desc = 'Follow [[wikilink]] under cursor' })
end

--- Per-buffer setup. Called once per markdown buffer that's inside a vault.
--- @param bufnr integer
function M._setup_buffer(bufnr)
    -- ── Follow wikilinks ──────────────────────────────────────────────
    if config.follow.keymap then
        vim.keymap.set('n', config.follow.keymap, function()
            follow.follow_wikilink()
        end, { desc = 'ft: follow [[wikilink]] under cursor', buffer = bufnr })
    end

    -- ── Autocompletion ───────────────────────────────────────────────
    if config.completion and config.completion.enable then
        local ok, complete = pcall(require, 'ft.complete')
        if ok then
            complete.setup(config.completion)
        end
    end

    -- ── Embed rendering ──────────────────────────────────────────────
    if config.embeds and config.embeds.enable then
        local ok, embed = pcall(require, 'ft.embed')
        if ok then
            embed.setup(config.embeds)
        end
    end
end

--- Explicitly check that the vault is reachable.
--- Useful for statusline integrations.
--- @return boolean
function M.vault_ready()
    return vault.get_vault() ~= nil
end

return M
