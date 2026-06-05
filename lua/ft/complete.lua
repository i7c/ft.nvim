--- Wikilink autocompletion.
---
--- Provides an omnifunc (`v:lua.require("ft.complete").complete`)
--- that completes note titles inside `[[...]]`. Auto-triggers on `[[`.
--- @module ft.complete

local cache = require('ft.cache')

local M = {}

-- Autocommand group so we can clean up on BufLeave.
local augroup = vim.api.nvim_create_augroup('ft_complete', { clear = true })

--- Setup completion for the current buffer.
--- @param opts table  Plugin config (completion subsection)
function M.setup(opts)
    -- 1. Populate the note cache (no-op if already done or vault not ready).
    cache.refresh()

    -- 2. Set the buffer-local omnifunc.
    vim.bo.omnifunc = 'v:lua.require("ft.complete").complete'

    -- 3. Auto-trigger completion when the user types `[[`.
    vim.api.nvim_create_autocmd('InsertCharPre', {
        group = augroup,
        buffer = 0,
        callback = function()
            local col = vim.fn.col('.')
            -- We need at least 2 chars before cursor to have typed [[
            if col < 2 then
                return
            end
            local line = vim.fn.getline('.')
            local pre = line:sub(col - 1, col)
            if pre == '[[' then
                vim.fn.feedkeys(
                    vim.api.nvim_replace_termcodes('<C-x><C-o>', true, false, true),
                    'n'
                )
            end
        end,
    })

    -- 4. Refresh the cache on BufEnter for the vault (one-shot after setup).
    --    Subsequent file opens within the same session reuse the cache.
    vim.api.nvim_create_autocmd('BufEnter', {
        group = augroup,
        buffer = 0,
        once = true,
        callback = function()
            cache.refresh()
        end,
    })

    -- 5. Auto-close `]]` on completion done when inside an unclosed [[.
    vim.api.nvim_create_autocmd('CompleteDone', {
        group = augroup,
        buffer = 0,
        callback = function()
            local line = vim.fn.getline('.')
            local col = vim.fn.col('.') - 1
            local before = line:sub(1, col)
            -- If the line ends with `[[SomeText` (no `]]` yet), close it.
            if before:match('%[%[[^%[%]]+$') then
                vim.fn.feedkeys(']]', 'n')
            end
        end,
    })
end

--- Omnifunc for wikilink completion.
---
--- Invoked by Neovim when the user presses `<C-x><C-o>` or when
--- auto-triggered by the `[[` InsertCharPre handler.
---
--- @param findstart integer  1 = find start column, 0 = complete
--- @param base     string    Text between start column and cursor
--- @return integer|table  Start column or list of completion items
function M.complete(findstart, base)
    if findstart == 1 then
        -- Scan backwards from cursor to find the opening `[[`.
        local line = vim.fn.getline('.')
        local col = vim.fn.col('.') - 1 -- 0-indexed byte offset

        local before = line:sub(1, col)
        -- Find the last `[[` before the cursor. We look for it at
        -- positions col-1, col-2, ... to handle [[partial where the
        -- second [ may be at col.
        local search_start = math.max(1, col - 50) -- bound search window
        local open_pos = before:find('%[%[', search_start)

        if open_pos then
            -- Return 0-indexed column of the first `[`.
            return open_pos - 1
        end

        return -2 -- not inside a wikilink
    end

    -- Completion phase: find notes matching `base`.
    local results = cache.search(base, 20)
    local items = {}

    for _, info in ipairs(results) do
        -- Primary: insert `Title]]` so the wikilink is auto-closed.
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
