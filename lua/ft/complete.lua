--- Wikilink autocompletion.
---
--- Attempts to register with blink.cmp (the likely completion framework
--- for LazyVim users). Falls back to setting 'omnifunc' when blink.cmp
--- is not available.
---
--- @module ft.complete

local cache = require('ft.cache')

local M = {}

-- Autocommand group.
local augroup = vim.api.nvim_create_augroup('ft_complete', { clear = true })

--- Try to register a wikilink completion source with blink.cmp.
--- Returns true if successful.
--- @return boolean
local function try_register_blink()
    local ok, blink_sources = pcall(require, 'blink.cmp.sources.lib')
    if not ok then
        return false
    end

    -- Inject our provider config into blink.cmp's config so
    -- `get_provider_by_id` can lazy-load it on first use.
    local ok2, blink_config = pcall(require, 'blink.cmp.config')
    if not ok2 then
        return false
    end

    blink_config.sources.providers['ft'] = {
        name = 'ft.wiki',
        module = 'ft.blink',
        -- Don't suppress our items on short words (e.g. spaces split
        -- titles with multiple words, making the word boundary reset).
        min_keyword_length = 0,
    }

    -- Register for markdown files specifically.
    blink_sources.add_filetype_provider_id('markdown', 'ft')

    return true
end

--- Setup completion for the current buffer.
--- @param _opts table  Plugin config (completion subsection, unused for now)
function M.setup(_opts)
    -- 1. Populate the note cache.
    cache.refresh()

    -- 2. Refresh cache once on BufEnter (one-shot).
    vim.api.nvim_create_autocmd('BufEnter', {
        group = augroup,
        buffer = 0,
        once = true,
        callback = function()
            cache.refresh()
        end,
    })

    -- 3. Try blink.cmp source registration.
    if try_register_blink() then
        return
    end

    -- 4. Fallback: set omnifunc for non-blink users.
    vim.bo.omnifunc = 'v:lua.require("ft.complete").complete__omnifunc'

    -- Auto-trigger via TextChangedI (handles auto-pair plugins).
    local triggered = false

    vim.api.nvim_create_autocmd('CompleteDone', {
        group = augroup,
        buffer = 0,
        callback = function()
            triggered = false
        end,
    })

    vim.api.nvim_create_autocmd('TextChangedI', {
        group = augroup,
        buffer = 0,
        callback = function()
            local col = vim.fn.col('.') - 1
            if col < 2 then
                triggered = false
                return
            end
            local line = vim.fn.getline('.')
            local before = line:sub(1, col)

            if before:match('%[%[[^%[%]]*$') then
                if not triggered then
                    triggered = true
                    vim.fn.feedkeys(
                        vim.api.nvim_replace_termcodes(
                            '<C-x><C-o>',
                            true,
                            false,
                            true
                        ),
                        'n'
                    )
                end
            else
                triggered = false
            end
        end,
    })
end

--- Omnifunc fallback (used when blink.cmp is not available).
---
--- @param findstart integer  1 = find start, 0 = complete
--- @param base     string    Text between start and cursor
--- @return integer|table
function M.complete__omnifunc(findstart, base)
    if findstart == 1 then
        local line = vim.fn.getline('.')
        local col = vim.fn.col('.') - 1
        local before = line:sub(1, col)

        local search_start = math.max(1, col - 100)
        local open_pos = before:find('%[%[', search_start)
        if open_pos then
            return (open_pos - 1) + 2
        end
        return -2
    end

    local results = cache.search(base, 20)
    local items = {}
    for _, info in ipairs(results) do
        table.insert(items, {
            word = info.title .. ']]',
            abbr = info.title,
            menu = info.path,
            icase = 1,
            dup = 1,
        })
    end
    return items
end

return M
