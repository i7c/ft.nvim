--- Embed rendering — display `![[linked note]]` content inline.
---
--- When the cursor is on a line containing an embed link in normal mode,
--- the target note's content is rendered as virtual lines below the line.
---
--- Trigger: CursorHold (configurable debounced trigger, default 400ms).
---
--- @module ft.embed

local vault = require('ft.vault')
local wikilink = require('ft.wikilink')

local M = {}

-- Highlight namespace for embed virtual text.
local ns = vim.api.nvim_create_namespace('ft_embeds')

-- Cache: resolved file path → { content_lines, mtime, max_lines }
-- Cleared on buffer write or manual refresh.
local content_cache = {}

-- Track the last-rendered line so we avoid redundant redraws.
local last_render_line = -1
local last_render_text = ''

-- Autocommand group.
local augroup = vim.api.nvim_create_augroup('ft_embed', { clear = true })

-- Separator width — caps at 72 chars or window width.
local function sep_width()
    return math.min(72, vim.api.nvim_win_get_width(0) - 2)
end

--- Build separator lines with consistent styling.
--- @return table[]  Array of virt_text tuples
local function build_sep()
    local w = sep_width()
    return { { string.rep('─', w), 'Comment' } }
end

--- Read and cache the content of a note.
--- @param abs_path string  Absolute path to the note file
--- @param max_lines integer  Max number of lines to keep
--- @return string[]|nil  Array of content lines, or nil on error
local function read_note(abs_path, max_lines)
    -- Check cache freshness
    local stat = vim.loop.fs_stat(abs_path)
    if not stat then
        return nil
    end

    local cached = content_cache[abs_path]
    if cached and cached.mtime == stat.mtime.sec and cached.max_lines >= max_lines then
        return cached.lines
    end

    -- Read the file
    local fd = vim.loop.fs_open(abs_path, 'r', 438)
    if not fd then
        return nil
    end

    local content = vim.loop.fs_read(fd, stat.size, 0)
    vim.loop.fs_close(fd)
    if not content then
        return nil
    end

    -- Split into lines and truncate
    local lines = vim.split(content, '\n')
    if #lines > max_lines then
        local truncated = {}
        for i = 1, max_lines do
            truncated[i] = lines[i]
        end
        table.insert(truncated, string.rep('⋯', sep_width()))
        lines = truncated
    end

    -- Cache
    content_cache[abs_path] = {
        lines = lines,
        mtime = stat.mtime.sec,
        max_lines = max_lines,
    }

    return lines
end

--- Render virtual lines for all embeds on the current line.
--- Called from the CursorHold handler.
function M.render()
    local bufnr = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()

    -- Clear previous renders on this buffer.
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    -- Read the current line.
    local line = vim.api.nvim_get_current_line()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_num = cursor[1]

    -- Skip if same line and same text as last render.
    if line_num == last_render_line and line == last_render_text then
        return
    end
    last_render_line = line_num
    last_render_text = line

    -- Parse embeds on this line.
    local embeds = wikilink.parse_wikilinks(line, line_num)
    local found_embed = false

    local vault_path = vault.get_vault()
    if not vault_path then
        return
    end

    local config_max_lines = vim.g.ft_embed_max_lines or 50

    for _, e in ipairs(embeds) do
        if not e.is_embed then
            goto continue
        end
        found_embed = true

        -- Resolve target path via ft find.
        local stdout, code = vault.ft_run({
            'find',
            e.target,
            '--format',
            'ndjson',
            '--limit',
            '1',
        })
        if code ~= 0 or not stdout then
            -- Show unresolved target text as greyed placeholder.
            local virt = {}
            table.insert(virt, build_sep())
            table.insert(virt, { { '│ ![[', 'Comment' }, { e.target, 'Special' }, { ']]', 'Comment' }, { '  (not found)', 'NonText' } })
            table.insert(virt, build_sep())
            vim.api.nvim_buf_set_extmark(bufnr, ns, line_num - 1, 0, {
                virt_lines = virt,
                virt_lines_above = false,
            })
            goto continue
        end

        local result = vim.json.decode(stdout:match('[^\n]+'))
        if not result or not result.path then
            goto continue
        end

        local abs_path = vault_path .. '/' .. result.path

        -- Read the note content.
        local content_lines = read_note(abs_path, config_max_lines)
        if not content_lines then
            goto continue
        end

        -- Build virtual lines.
        local virt = {}
        table.insert(virt, build_sep())

        for _, cl in ipairs(content_lines) do
            -- Strip trailing whitespace for clean display.
            local display = cl:gsub('%s+$', '')
            table.insert(virt, { { display, '' } })
        end

        table.insert(virt, build_sep())

        -- Apply extmark at the embed line.
        vim.api.nvim_buf_set_extmark(bufnr, ns, line_num - 1, 0, {
            virt_lines = virt,
            virt_lines_above = false,
        })

        ::continue::
    end

    -- Clear the last-render markers when no embed was found (so the
    -- handler re-evaluates on next CursorHold after the user edits).
    if not found_embed then
        last_render_line = -1
        last_render_text = ''
    end
end

--- Clear all rendered embeds in the current buffer.
function M.clear()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    content_cache = {}
    last_render_line = -1
    last_render_text = ''
end

--- Setup embed rendering for the current buffer.
--- @param opts table  Plugin config (embeds subsection)
function M.setup(opts)
    -- CursorHold trigger
    vim.api.nvim_create_autocmd('CursorHold', {
        group = augroup,
        buffer = 0,
        callback = function()
            M.render()
        end,
    })

    -- Clear embeds on buffer write (content may have changed).
    vim.api.nvim_create_autocmd('BufWritePost', {
        group = augroup,
        buffer = 0,
        callback = function()
            M.clear()
        end,
    })

    -- Clear embeds on InsertEnter so the user can edit without
    -- virtual lines getting in the way.
    vim.api.nvim_create_autocmd('InsertEnter', {
        group = augroup,
        buffer = 0,
        callback = function()
            vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
        end,
    })

    -- When leaving the buffer, clean up namespaces and cache.
    vim.api.nvim_create_autocmd('BufLeave', {
        group = augroup,
        buffer = 0,
        callback = function()
            M.clear()
        end,
    })
end

return M
