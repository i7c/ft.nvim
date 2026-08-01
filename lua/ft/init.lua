--- ft.nvim — Neovim integration for `ft` (Obsidian vault toolkit).
---
--- The plugin is editor glue plus a transport: all domain logic (task
--- parsing/serialization, queries, dates, synth callouts) lives in the
--- `ft` CLI, driven through the single `ft.rpc` seam. See
--- ARCHITECTURE.md for the full model.
---
--- Features:
--- - `:FtFollow` or `gf` — follow [[Wikilinks]] to the target note or heading
--- - Wikilink autocompletion — auto-triggers on `[[`, completes note titles
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
---     picker = {
---         backend = 'auto', -- 'auto' | 'select' | 'telescope' | 'fzf-lua'
---     },
--- })
--- ```
---
--- @module ft

local follow = require('ft.follow')
local picker = require('ft.picker')
local rpc = require('ft.rpc')
local vault = require('ft.vault')

local M = {}

-- Autocommand group for buffer-level setup.
local setup_augroup = vim.api.nvim_create_augroup('ft_setup', { clear = true })

-- Minimum `ft` binary version the plugin's protocol contract assumes.
-- See ARCHITECTURE.md, "Protocol contract".
local MIN_FT_VERSION = { 0, 1, 0 }

local defaults = {
    vault = nil,
    follow = {
        keymap = 'gf',
    },
    completion = {
        enable = true,
    },
    picker = {
        backend = 'auto',
    },
}

-- Merged config.
local config = {}

--- Setup ft.nvim.
--- Should be called from your Neovim config (init.lua / lazy.nvim spec).
---
--- @param opts table|nil  Configuration options
function M.setup(user_opts)
    config = vim.tbl_deep_extend('keep', user_opts or {}, defaults)

    -- Discover vault (best-effort; discovery state is cached so follow
    -- can check it at invocation time). Do this early so submodules
    -- that need the vault path can rely on it during setup.
    vault.discover(config.vault)

    -- Configure the picker seam.
    picker.setup(config.picker)

    -- Soft-check the ft binary version: warn, never fail.
    M._check_ft_version()

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

--- Soft version check: warn when the installed ft binary is older than
--- MIN_FT_VERSION. Never fails — the protocol contract is a floor, not
--- a gate.
function M._check_ft_version()
    local stdout, exit_code = rpc.call({ '--version' })
    if exit_code ~= 0 or not stdout then
        return -- rpc.call already notified the missing-binary case
    end
    local version = rpc.parse_version(stdout)
    if version and rpc.version_lt(version, MIN_FT_VERSION) then
        vim.notify(
            string.format(
                'ft.nvim: installed ft %s is older than the required %d.%d.%d'
                    .. ' — some features may misbehave. Upgrade ft or set'
                    .. ' $FT_BIN to a newer build.',
                stdout:match('%S+$') or stdout:gsub('%s+$', ''),
                MIN_FT_VERSION[1],
                MIN_FT_VERSION[2],
                MIN_FT_VERSION[3]
            ),
            vim.log.levels.WARN
        )
    end
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
end

--- Explicitly check that the vault is reachable.
--- Useful for statusline integrations.
--- @return boolean
function M.vault_ready()
    return vault.get_vault() ~= nil
end

return M
