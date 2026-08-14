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
--- - Task operations — `:FtTaskCreate` / `:FtTaskSubtask` / `:FtTaskDone` /
---   `:FtTaskCancel` / `:FtTaskDue` (create at cursor with inline
---   `due:+2d` syntax, create a subtask under the task at the cursor, mark
---   done/cancelled, set/clear the due date)
--- - Quote — `gz` operator / `:FtQuote`: quote a line range of the current
---   note as a protected section (`ft notes quote`) into the registers
--- - Export — `gy` operator / `:FtExport`: export a line range (or the
---   whole note) as clean CommonMark (`ft notes export`) into the registers
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
---     tasks = {
---         keymaps = {        -- set any to false to disable
---             create = '<leader>tt',
---             subtask = '<leader>ts',
---             done = '<leader>td',
---             cancel = '<leader>tc',
---             due = '<leader>te',
---         },
---     },
---     export = {
---         format = 'prompt', -- 'commonmark'|'slack' skips the format prompt; 'prompt' always asks
---     },
--- })
--- ```
---
--- @module ft

local export = require('ft.export')
local follow = require('ft.follow')
local picker = require('ft.picker')
local quote = require('ft.quote')
local rpc = require('ft.rpc')
local tasks = require('ft.tasks')
local vault = require('ft.vault')

local M = {}

-- Autocommand group for buffer-level setup.
local setup_augroup = vim.api.nvim_create_augroup('ft_setup', { clear = true })

-- Minimum `ft` binary version the plugin's protocol contract assumes.
-- See ARCHITECTURE.md, "Protocol contract". 0.1.7 is the first
-- release carrying the full consumed surface: `ft notes quote`,
-- `ft notes export`, and both `--format` values (export ships in
-- 0.1.6 with `commonmark` only; the `slack` target lands in 0.1.7).
local MIN_FT_VERSION = { 0, 1, 7 }

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
    tasks = {
        keymaps = {
            create = '<leader>tt',
            subtask = '<leader>ts',
            done = '<leader>td',
            cancel = '<leader>tc',
            due = '<leader>te',
        },
    },
    quote = {
        keymaps = {
            operator = 'gz', -- operator + visual key; false disables
        },
        registers = {
            unnamed = true, -- plain `p` pastes the section
            named = true, -- register `f`: stable home for repeated paste
            clipboard = true, -- `"+`: survives closing nvim and reopening
        },
    },
    export = {
        keymaps = {
            operator = 'gy', -- operator + visual key; false disables
        },
        format = 'prompt', -- export format: 'commonmark'|'slack' skips the prompt; 'prompt' always asks
        registers = {
            unnamed = true, -- plain `p` pastes the section
            named = true, -- register `f`: stable home, shared with quote
            clipboard = true, -- `"+`: survives closing nvim and reopening
        },
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

    -- Apply the quote/export config (register targets).
    quote.setup(config.quote)
    export.setup(config.export)

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
    -- files, will show an appropriate error). Guarded so setup() can be
    -- re-called (lazy reload, config changes) without duplicate commands.
    local function register_command(name, fn, desc, opts)
        if vim.fn.exists(':' .. name) == 0 then
            vim.api.nvim_create_user_command(
                name,
                fn,
                vim.tbl_extend('force', { desc = desc }, opts or {})
            )
        end
    end

    register_command('FtFollow', function()
        follow.follow_wikilink()
    end, 'Follow [[wikilink]] under cursor')

    -- Range command: normal mode defaults to the current line; invoked
    -- from visual mode nvim supplies the selection as the range.
    register_command('FtQuote', function(args)
        quote.quote_range(args.line1, args.line2)
    end, 'Quote the line range as a protected section', { range = true })

    -- No range given (args.range == 0) exports the whole buffer — the
    -- CLI's whole-file default and the flagship "clean copy of this
    -- note" use; an explicit range or a visual selection passes -l A-B.
    register_command('FtExport', function(args)
        if args.range == 0 then
            export.export_whole_file()
        else
            export.export_range(args.line1, args.line2)
        end
    end, 'Export the line range (or the whole buffer) as clean CommonMark', { range = true })

    register_command('FtTaskCreate', function()
        tasks.create()
    end, 'Create a task at the cursor line')
    register_command('FtTaskSubtask', function()
        tasks.create_subtask()
    end, 'Create a subtask under the task at the cursor line')
    register_command('FtTaskDone', function()
        tasks.done()
    end, 'Mark the task under the cursor done')
    register_command('FtTaskCancel', function()
        tasks.cancel()
    end, 'Cancel the task under the cursor')
    register_command('FtTaskDue', function()
        tasks.set_due()
    end, 'Set or clear the due date of the task under the cursor')
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

    -- ── Task operations ─────────────────────────────────────────────
    local task_keymaps = (config.tasks or {}).keymaps or {}
    for action, fn in pairs({
        create = tasks.create,
        subtask = tasks.create_subtask,
        done = tasks.done,
        cancel = tasks.cancel,
        due = tasks.set_due,
    }) do
        local key = task_keymaps[action]
        if key then
            vim.keymap.set('n', key, fn, {
                desc = 'ft: task ' .. action,
                buffer = bufnr,
            })
        end
    end

    -- ── Quote (protected section) ───────────────────────────────────
    local quote_cfg = config.quote or {}
    local quote_key = (quote_cfg.keymaps or {}).operator
    if quote_key then
        -- Both modes use the same operator: `gz` arms operatorfunc and
        -- returns `g@`. In normal mode `g@` takes the following motion;
        -- in visual mode `g@` applies the operator to the selection.
        -- (A direct visual callback cannot read `'<`/`'>` — nvim commits
        -- those marks only when visual mode exits, after the callback.)
        vim.keymap.set('n', quote_key, quote.operator_rhs(), {
            expr = true, -- the callback returns `g@` to take the motion
            desc = 'ft: quote motion range as protected section',
            buffer = bufnr,
        })
        vim.keymap.set('v', quote_key, quote.operator_rhs(), {
            expr = true, -- `g@` applies the operator to the selection
            desc = 'ft: quote selection as protected section',
            buffer = bufnr,
        })
    end

    -- ── Export (clean CommonMark) ───────────────────────────────────
    local export_cfg = config.export or {}
    local export_key = (export_cfg.keymaps or {}).operator
    if export_key then
        -- Same operator pattern as quote: `gy` arms operatorfunc and
        -- returns `g@` for the following motion (normal) or the
        -- selection (visual).
        vim.keymap.set('n', export_key, export.operator_rhs(), {
            expr = true, -- the callback returns `g@` to take the motion
            desc = 'ft: export motion range as clean CommonMark',
            buffer = bufnr,
        })
        vim.keymap.set('v', export_key, export.operator_rhs(), {
            expr = true, -- `g@` applies the operator to the selection
            desc = 'ft: export selection as clean CommonMark',
            buffer = bufnr,
        })
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
