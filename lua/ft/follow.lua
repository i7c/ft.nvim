--- Follow wikilinks: navigate to linked notes and headings.
---
--- Given a cursor on [[Target]], [[Target|Display]], [[Target#Anchor]],
--- or [[#Anchor]], resolves the target and opens it inside the current
--- Neovim instance.
---
--- Resolution order:
--- 1. Same-file anchor  [[#heading]]  →  search current buffer
--- 2. External target   [[Target]]    →  ft find → open file
--- 3. Anchor on target  [[Target#H]]  →  ft find → open file + jump line
---
--- @module ft.follow

local wikilink = require('ft.wikilink')
local vault = require('ft.vault')
local rpc = require('ft.rpc')

local M = {}

--- Try to follow a wikilink under the cursor.
--- Returns true if a wikilink was found and handled, false otherwise.
--- @return boolean
function M.follow_wikilink()
    -- 1. Ensure vault is discovered
    local vault_path = vault.get_vault()
    if not vault_path then
        vim.notify(
            'ft: no Obsidian vault found. Set FT_VAULT or open a file inside a vault.',
            vim.log.levels.ERROR
        )
        return false
    end

    -- 2. Parse the current line for wikilinks
    local line = vim.api.nvim_get_current_line()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local col = cursor[2] -- 0-indexed byte column
    local line_num = cursor[1] -- 1-indexed line number

    local wl = wikilink.wikilink_at_cursor(line, col, line_num)
    if not wl then
        vim.notify('ft: no wikilink under cursor', vim.log.levels.INFO)
        return false
    end

    -- 3. Handle same-file anchor: [[#Heading]]
    if wl.target == '' and wl.anchor then
        M._follow_anchor_in_buffer(wl.anchor)
        return true
    end

    -- 4. Resolve the target with ft find.
    local query = wl.target
    if wl.anchor then
        query = query .. '#' .. wl.anchor
    end

    local stdout, exit_code = rpc.call({
        'find',
        query,
        '--format',
        'ndjson',
        '--limit',
        '1',
        '--include-headings',
    })

    if exit_code ~= 0 or not stdout or #stdout == 0 then
        vim.notify(
            "ft: no note found for '" .. wl.target .. "'",
            vim.log.levels.WARN
        )
        return true
    end

    -- 5. Parse the ndjson result
    local result = vim.json.decode(stdout:match('[^\n]+'))
    if not result or not result.path then
        vim.notify("ft: unexpected response from 'ft find'", vim.log.levels.ERROR)
        return true
    end

    -- 6. Open the file
    local abs_path = vault_path .. '/' .. result.path
    vim.cmd('edit ' .. vim.fn.fnameescape(abs_path))

    -- 7. Jump to heading line if we found one
    if result.line then
        vim.api.nvim_win_set_cursor(0, { result.line, 0 })
        vim.cmd('normal! zz') -- center the screen
    end

    return true
end

--- Jump to the first heading matching `anchor` in the current buffer.
--- Searches for an ATX heading whose text equals the anchor (case-insensitive).
--- @param anchor string  e.g. "Goals" from [[#Goals]]
function M._follow_anchor_in_buffer(anchor)
    local esc = vim.pesc(anchor)
    local pattern = '^#+%s*' .. esc .. '%s*$'

    -- searchpos with 'w' wraps around the file
    local pos = vim.fn.searchpos(pattern, 'wc')

    if pos[1] ~= 0 then
        vim.api.nvim_win_set_cursor(0, pos)
        vim.cmd('normal! zz') -- center
    else
        vim.notify(
            "ft: heading '" .. anchor .. "' not found in this note",
            vim.log.levels.WARN
        )
    end
end

return M
