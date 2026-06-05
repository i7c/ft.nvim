--- Embed rendering — display `![[linked note]]` content inline.
---
--- Renders all embeds visible in the current viewport. Updated on scroll
--- and cursor movement (debounced). Each embed shows the target note's
--- content with a coloured vertical gutter and indentation.
---
--- @module ft.embed

local vault = require('ft.vault')
local wikilink = require('ft.wikilink')

local M = {}

-- Highlight namespace for embed virtual text.
local ns = vim.api.nvim_create_namespace('ft_embeds')

-- Cache: resolved file path → { lines, mtime }
local content_cache = {}

-- Cached visible line range to avoid redundant re-renders.
local last_top = -1
local last_bot = -1

-- Debounce timer handle.
local debounce_timer = nil

-- Autocommand group.
local augroup = vim.api.nvim_create_augroup('ft_embed', { clear = true })

-- Separator character repeated across the width.
local SEP_CHAR = '─'
-- Gutter character drawn before each content line.
local GUTTER_CHAR = '│'
-- Amount to indent the gutter + content from the left edge.
local INDENT = '  '

--- Separator width fitting the window.
local function sep_width()
    return math.max(10, math.min(72, vim.api.nvim_win_get_width(0) - 2))
end

--- Build a single horizontal separator row.
--- @return table[]  virt_text array
local function sep_row()
    local w = sep_width()
    return { { string.rep(SEP_CHAR, w), 'Comment' } }
end

--- Build a content line with gutter + indentation.
--- @param text string  The line text from the embedded note
--- @return table[]  virt_text array
local function content_row(text)
    local display = text:gsub('%s+$', '')
    return {
        { INDENT, 'NonText' },
        { GUTTER_CHAR .. ' ', 'NonText' },
        { display, '' },
    }
end

--- Read and cache note content.
--- @param abs_path string  Absolute path to the note
--- @param max_lines integer  Max lines to keep
--- @return string[]|nil  Array of content lines, or nil
local function read_note(abs_path, max_lines)
    local stat = vim.loop.fs_stat(abs_path)
    if not stat then
        return nil
    end

    local cached = content_cache[abs_path]
    if cached and cached.mtime == stat.mtime.sec then
        return cached.lines
    end

    local fd = vim.loop.fs_open(abs_path, 'r', 438)
    if not fd then
        return nil
    end
    local raw = vim.loop.fs_read(fd, stat.size, 0)
    vim.loop.fs_close(fd)
    if not raw then
        return nil
    end

    local lines = vim.split(raw, '\n')
    if #lines > max_lines then
        local trimmed = {}
        for i = 1, max_lines do
            trimmed[i] = lines[i]
        end
        trimmed[max_lines + 1] = string.rep('⋯', 5)
        lines = trimmed
    end

    content_cache[abs_path] = { lines = lines, mtime = stat.mtime.sec }
    return lines
end

--- Resolve an embed target to an absolute file path.
--- Uses `ft find` for fuzzy resolution, falls back to exact path.
--- @param target string  The wikilink target (text between [[ and ]])
--- @return string|nil  Absolute path, or nil if not resolvable
local function resolve_embed(target)
    local vault_path = vault.get_vault()
    if not vault_path then
        return nil
    end

    local stdout, code = vault.ft_run({
        'find', target,
        '--format', 'ndjson',
        '--limit', '1',
    })
    if code ~= 0 or not stdout then
        return nil
    end

    local result = vim.json.decode(stdout:match('[^\n]+'))
    if not result or not result.path then
        return nil
    end

    return vault_path .. '/' .. result.path
end

--- Render every `![[embed]]` in the current viewport.
function M.render_viewport()
    local bufnr = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()

    local top = vim.fn.line('w0')
    local bot = vim.fn.line('w$')

    -- Skip if the visible range hasn't changed.
    if top == last_top and bot == last_bot then
        return
    end
    last_top = top
    last_bot = bot

    -- Clear previous renders.
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    local vault_path = vault.get_vault()
    if not vault_path then
        return
    end

    local max_lines = vim.g.ft_embed_max_lines or 20

    -- Read lines in the visible range to find embeds.
    local lines = vim.api.nvim_buf_get_lines(bufnr, top - 1, bot, false)
    local renders = {} -- { line_num (1-indexed), virt_lines[] }

    for i, line_text in ipairs(lines) do
        local line_num = top + i - 1
        local embeds = wikilink.parse_wikilinks(line_text, line_num)

        for _, e in ipairs(embeds) do
            if e.is_embed then
                local abs_path = resolve_embed(e.target)
                if not abs_path then
                    -- Unresolved placeholder.
                    local virt = {}
                    table.insert(virt, sep_row())
                    table.insert(virt, content_row('![' .. e.target .. ']  (not found)'))
                    table.insert(virt, sep_row())
                    table.insert(renders, { line = line_num, virt = virt })
                else
                    local content_lines = read_note(abs_path, max_lines)
                    if content_lines then
                        local virt = {}
                        -- No opening separator — the embed text itself
                        -- marks the start. Just show a closing separator.
                        for _, cl in ipairs(content_lines) do
                            table.insert(virt, content_row(cl))
                        end
                        table.insert(virt, sep_row())
                        table.insert(renders, { line = line_num, virt = virt })
                    end
                end
            end
        end
    end

    -- Apply extmarks.
    for _, r in ipairs(renders) do
        vim.api.nvim_buf_set_extmark(bufnr, ns, r.line - 1, 0, {
            virt_lines = r.virt,
            virt_lines_above = false,
        })
    end
end

--- Debounced trigger for viewport render.
local function debounced_render()
    if debounce_timer then
        pcall(debounce_timer.stop, debounce_timer)
        pcall(debounce_timer.close, debounce_timer)
    end
    debounce_timer = vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(0) and vim.bo.filetype == 'markdown' then
            M.render_viewport()
        end
    end, 150)
end

--- Clear all rendered embeds and cancel pending renders.
function M.clear()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    content_cache = {}
    last_top = -1
    last_bot = -1
    if debounce_timer then
        pcall(debounce_timer.stop, debounce_timer)
        pcall(debounce_timer.close, debounce_timer)
        debounce_timer = nil
    end
end

--- Setup embed rendering for the current buffer.
--- @param _opts table  Plugin config (embeds subsection, unused)
function M.setup(_opts)
    -- Initial render on BufEnter (fires when the buffer is first shown).
    vim.api.nvim_create_autocmd('BufEnter', {
        group = augroup,
        buffer = 0,
        callback = function()
            M.render_viewport()
        end,
    })

    -- Re-render on scroll (viewport changes).
    vim.api.nvim_create_autocmd('WinScrolled', {
        group = augroup,
        buffer = 0,
        callback = function()
            debounced_render()
        end,
    })

    -- Re-render on cursor move (in case the viewport didn't scroll
    -- but the cursor entered a zone with new embeds).
    vim.api.nvim_create_autocmd('CursorMoved', {
        group = augroup,
        buffer = 0,
        callback = function()
            debounced_render()
        end,
    })

    -- Re-render after write (content may have changed).
    vim.api.nvim_create_autocmd('BufWritePost', {
        group = augroup,
        buffer = 0,
        callback = function()
            content_cache = {}
            last_top = -1
            last_bot = -1
            M.render_viewport()
        end,
    })

    -- Clear on InsertEnter so the user can edit without distraction.
    vim.api.nvim_create_autocmd('InsertEnter', {
        group = augroup,
        buffer = 0,
        callback = function()
            vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
            last_top = -1
            last_bot = -1
        end,
    })

    -- Full cleanup on BufLeave.
    vim.api.nvim_create_autocmd('BufLeave', {
        group = augroup,
        buffer = 0,
        callback = function()
            M.clear()
        end,
    })
end

return M
