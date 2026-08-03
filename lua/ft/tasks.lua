--- ft.tasks — create and update tasks inside Neovim.
---
--- Thin editor glue over `ft tasks create|complete|cancel`. All task
--- domain logic (line serialization, date resolution, indentation)
--- stays in the ft CLI; this module only turns editor state (cursor,
--- buffer) and user input into argv, then reloads the buffer from disk.
---
--- Operations:
---   M.create()        — :FtTaskCreate    — new task at the cursor line
---   M.create_subtask()— :FtTaskSubtask  — subtask of the task at the cursor line
---   M.done()          — :FtTaskDone      — mark the task under the cursor done
---   M.cancel()        — :FtTaskCancel    — cancel the task under the cursor
---
--- Shared mechanics (see ARCHITECTURE.md / the nvim-task-ops change):
---   - the buffer is written to disk before any mutating ft command
---   - after a success the buffer is reloaded from disk (`:edit`), which
---     keeps undo history and refreshes file-change tracking; the note
---     index cache is marked dirty
---   - updates use the exact `<file>:<line>` selector
---
--- @module ft.tasks

local rpc = require('ft.rpc')
local vault = require('ft.vault')

local M = {}

-- ft error-text markers the plugin classifies instead of surfacing as
-- plain errors. `complete` on an already-done task exits non-zero with
-- this message; `cancel` on an already-cancelled task already exits 0
-- (the CLI treats it as success), so cancel needs no marker.
local DONE_MARKER = 'is already done'
local NO_MATCH_MARKER = 'no tasks match selector'

-- ── Inline `due:` token (mirrors the ft TUI quickline grammar) ─────────────

--- Split an inline `due:<value>` token out of a task description.
---
--- Mirrors the ft TUI quickline rule for the due field only: a
--- whitespace-delimited token whose prefix is `due:` (case-insensitive)
--- is removed from the description and its raw value returned verbatim —
--- ft's `dates::parse` resolves `+2d` / `today` / ISO / natural language
--- into the task line's ISO date. `\due:...` escapes to a literal
--- description token. A repeated or empty `due:` sets `error`; the
--- caller aborts rather than guessing.
---
--- @param input string|nil
--- @return table  { description, due, error }
function M.parse_due(input)
    local desc_parts = {}
    local due = nil
    local err = nil

    for tok in (input or ''):gmatch('%S+') do
        if tok:sub(1, 1) == '\\' then
            -- \due:... is a literal description token.
            desc_parts[#desc_parts + 1] = tok:sub(2)
        elseif tok:lower():sub(1, 4) == 'due:' then
            local value = tok:sub(5)
            if #value == 0 then
                err = err or '`due:` requires a value'
            elseif due then
                err = err or '`due:` specified twice'
            else
                due = value
            end
        else
            desc_parts[#desc_parts + 1] = tok
        end
    end

    return {
        description = table.concat(desc_parts, ' '),
        due = due,
        error = err,
    }
end

-- ── Shared mechanics ────────────────────────────────────────────────────────

--- Extract the message from ft's merged stdout/stderr. Mutating
--- commands run with `--json-errors`, so failures arrive as a JSON
--- object on stderr; the rpc sync call merges both streams, making the
--- whole returned string that document.
--- @param output string|nil
--- @return string|nil
local function _ft_message(output)
    if not output or #output == 0 then
        return nil
    end
    local trimmed = output:gsub('^%s+', ''):gsub('%s+$', '')
    if trimmed:sub(1, 1) == '{' then
        local ok, obj = pcall(vim.json.decode, trimmed)
        if ok and type(obj) == 'table' and obj.error then
            return obj.error
        end
    end
    return trimmed
end

--- Write the current buffer to disk when it has unsaved changes.
--- Returns false when the write did not stick (read-only buffer, unnamed
--- buffer, disk error) — ft reads from disk, so a mutation must never run
--- over unsaved content. An unmodified buffer is already in sync, so
--- nothing is written (avoids the "file changed since reading" prompt).
--- @param buf integer
--- @return boolean
local function _save_buffer(buf)
    if not vim.bo[buf].modified then
        return true
    end
    vim.cmd('silent! write')
    return not vim.bo[buf].modified
end

--- Sync the current buffer to its on-disk content via `:edit`. This
--- preserves the buffer's undo history — the reload lands as a single
--- undoable step, so a later `u` returns to the pre-mutation state — and
--- refreshes nvim's file-change tracking (no spurious "changed since
--- reading" prompts on later writes). ft wrote the file directly, so no
--- BufWritePost fired; the note index must be marked dirty by hand.
--- Callers guarantee the buffer is unmodified here (saved in preflight).
--- @param buf integer
local function _reload_from_disk(buf)
    local ok = pcall(vim.cmd, 'edit')
    if not ok then
        vim.notify('ft: could not reload the buffer from disk', vim.log.levels.ERROR)
        return
    end
    pcall(function()
        require('ft.cache').mark_dirty()
    end)
end

--- Shared preflight for every mutating operation: a vault is
--- discovered, the buffer has a name, the buffer is inside the vault,
--- and the buffer is saved to disk.
--- @return table|nil  { buf, rel } or nil (already notified)
local function _preflight()
    local root = vault.get_vault()
    if not root then
        vim.notify(
            'ft: no Obsidian vault found. Set FT_VAULT or open a file inside a vault.',
            vim.log.levels.ERROR
        )
        return nil
    end
    local buf = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(buf)
    if #path == 0 then
        vim.notify('ft: save the file first, then retry', vim.log.levels.ERROR)
        return nil
    end
    local rel = vault.relativize(path)
    if not rel then
        vim.notify('ft: buffer is not inside the vault', vim.log.levels.ERROR)
        return nil
    end
    if not _save_buffer(buf) then
        vim.notify('ft: could not save the buffer (read-only?)', vim.log.levels.ERROR)
        return nil
    end
    return { buf = buf, rel = rel }
end

-- ── Create ──────────────────────────────────────────────────────────────────

--- Create a subtask under the task at the cursor line
--- (`ft tasks create --parent <rel>:<line>`), nesting one level deeper
--- than the parent. The parent selector is captured at invocation — a
--- cursor move while the prompt is open cannot retarget it. The
--- description is prompted via `vim.ui.input` with an empty default
--- (the current line is the parent, not a draft). Inline `due:<value>`
--- tokens behave exactly as in `create`. After success the buffer
--- reloads and the cursor stays on the parent's line, so repeated
--- invocations add sibling subtasks.
function M.create_subtask()
    local ctx = _preflight()
    if not ctx then
        return
    end

    -- The parent is the line under the cursor at invocation; captured
    -- once so a cursor move while prompting cannot retarget it.
    local parent_line = vim.api.nvim_win_get_cursor(0)[1]

    vim.ui.input({
        prompt = 'ft: new subtask',
        default = '',
    }, function(input)
        if not input then
            return -- prompt cancelled
        end
        if vim.api.nvim_get_current_buf() ~= ctx.buf then
            vim.notify('ft: aborted — buffer changed while prompting', vim.log.levels.ERROR)
            return
        end
        -- Re-save at confirm time so the disk copy ft scans for the
        -- parent is exactly what the user sees now.
        if not _save_buffer(ctx.buf) then
            vim.notify('ft: could not save the buffer (read-only?)', vim.log.levels.ERROR)
            return
        end

        local parsed = M.parse_due(input)
        if parsed.error then
            vim.notify('ft: ' .. parsed.error, vim.log.levels.ERROR)
            return
        end
        if #parsed.description == 0 then
            vim.notify('ft: task description is empty', vim.log.levels.ERROR)
            return
        end

        -- `--parent` determines both the target file (the parent's) and
        -- the position (indented subtask); the placement flags it
        -- conflicts with (--file/--at-line) are deliberately absent.
        local args = {
            'tasks', 'create', parsed.description,
            '--parent', ctx.rel .. ':' .. parent_line,
            '--force',
            '--json-errors',
        }
        if parsed.due then
            args[#args + 1] = '--due'
            args[#args + 1] = parsed.due
        end

        local stdout, exit_code = rpc.call(args)
        if exit_code == 0 then
            _reload_from_disk(ctx.buf)
            -- Position::Subtask splices below the parent's block, so
            -- the parent's line number never shifts; stay on it so
            -- repeated invocations add sibling subtasks.
            vim.api.nvim_win_set_cursor(0, { parent_line, 0 })
        elseif exit_code == -1 then
            -- rpc.call already notified the missing-binary case.
            return
        else
            local msg = _ft_message(stdout) or 'tasks create failed'
            if msg:find(NO_MATCH_MARKER, 1, true) then
                vim.notify('ft: ' .. msg, vim.log.levels.WARN)
            else
                vim.notify('ft: ' .. msg, vim.log.levels.ERROR)
            end
        end
    end)
end

--- Create a task at the cursor line (`ft tasks create --at-line N`),
--- pushing existing content down. The description is prompted via
--- `vim.ui.input`, pre-filled with the current line's text when it has
--- any — confirming then "turns the current line into a task". Inline
--- `due:<value>` tokens are extracted and passed to `--due` verbatim;
--- ft resolves the date. Duplicates are allowed (`--force`). After
--- success the buffer reloads and the cursor lands on the new task.
function M.create()
    local ctx = _preflight()
    if not ctx then
        return
    end

    local cur_line = vim.api.nvim_get_current_line()
    local prefilled = cur_line:match('^%s*(.-)%s*$')
    if prefilled == '' then
        prefilled = nil
    end

    vim.ui.input({
        prompt = 'ft: new task',
        default = prefilled,
    }, function(input)
        if not input then
            return -- prompt cancelled
        end
        if vim.api.nvim_get_current_buf() ~= ctx.buf then
            vim.notify('ft: aborted — buffer changed while prompting', vim.log.levels.ERROR)
            return
        end
        -- Re-read the cursor and re-save at confirm time so the disk
        -- copy ft reads is exactly what the user sees now.
        local line_num = vim.api.nvim_win_get_cursor(0)[1]
        if not _save_buffer(ctx.buf) then
            vim.notify('ft: could not save the buffer (read-only?)', vim.log.levels.ERROR)
            return
        end

        local parsed = M.parse_due(input)
        if parsed.error then
            vim.notify('ft: ' .. parsed.error, vim.log.levels.ERROR)
            return
        end
        if #parsed.description == 0 then
            vim.notify('ft: task description is empty', vim.log.levels.ERROR)
            return
        end

        local args = {
            'tasks', 'create', parsed.description,
            '--file', ctx.rel,
            '--at-line', tostring(line_num),
            '--force',
            '--json-errors',
        }
        if parsed.due then
            args[#args + 1] = '--due'
            args[#args + 1] = parsed.due
        end

        local stdout, exit_code = rpc.call(args)
        if exit_code == 0 then
            _reload_from_disk(ctx.buf)
            -- Position::AtLine puts the new task exactly on the line we
            -- asked for; land the cursor on it.
            vim.api.nvim_win_set_cursor(0, { line_num, 0 })
        elseif exit_code == -1 then
            -- rpc.call already notified the missing-binary case.
            return
        else
            vim.notify(
                'ft: ' .. (_ft_message(stdout) or 'tasks create failed'),
                vim.log.levels.ERROR
            )
        end
    end)
end

-- ── Done / cancel ───────────────────────────────────────────────────────────

local UPDATE_OPS = {
    done = { cmd = 'complete', marker = DONE_MARKER },
    -- `cancel` needs no marker: ft's CLI already treats an
    -- already-cancelled task as success (exit 0, no file change).
    cancel = { cmd = 'cancel', marker = nil },
}

--- Mark the task under the cursor done or cancelled. Uses the exact
--- `<file>:<line>` selector for the current buffer and cursor line.
--- On success the buffer reloads. Failures are classified: an
--- already-done task is an info-level no-op, a line that matches no
--- task is a warning, everything else is an error.
--- @param op string  'done' | 'cancel'
local function _update(op)
    local ctx = _preflight()
    if not ctx then
        return
    end
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local selector = ctx.rel .. ':' .. line_num

    local stdout, exit_code = rpc.call({
        'tasks', UPDATE_OPS[op].cmd, selector, '--yes', '--json-errors',
    })

    if exit_code == 0 then
        _reload_from_disk(ctx.buf)
        return
    end
    if exit_code == -1 then
        return -- rpc.call notified the missing-binary case
    end

    local msg = _ft_message(stdout) or ('tasks ' .. UPDATE_OPS[op].cmd .. ' failed')
    local marker = UPDATE_OPS[op].marker
    if marker and msg:find(marker, 1, true) then
        vim.notify('ft: ' .. msg, vim.log.levels.INFO)
    elseif msg:find(NO_MATCH_MARKER, 1, true) then
        vim.notify('ft: ' .. msg, vim.log.levels.WARN)
    else
        vim.notify('ft: ' .. msg, vim.log.levels.ERROR)
    end
end

function M.done()
    _update('done')
end

function M.cancel()
    _update('cancel')
end

-- ── Edit due date ───────────────────────────────────────────────────────────

--- Set or clear the due date of the task under the cursor
--- (`ft tasks edit --due`). Prompts via `vim.ui.input`; the value is
--- passed verbatim to `--due` so ft resolves `+2d` / `today` / ISO /
--- natural language into the task line's ISO date, and `none` clears
--- it. An empty prompt cancels without running any command.
function M.set_due()
    local ctx = _preflight()
    if not ctx then
        return
    end

    vim.ui.input({
        prompt = 'ft: due date',
        default = '',
    }, function(input)
        if not input or #input == 0 then
            return -- cancelled / empty: no change
        end
        if vim.api.nvim_get_current_buf() ~= ctx.buf then
            vim.notify('ft: aborted — buffer changed while prompting', vim.log.levels.ERROR)
            return
        end
        local line_num = vim.api.nvim_win_get_cursor(0)[1]
        if not _save_buffer(ctx.buf) then
            vim.notify('ft: could not save the buffer (read-only?)', vim.log.levels.ERROR)
            return
        end

        local selector = ctx.rel .. ':' .. line_num
        local stdout, exit_code = rpc.call({
            'tasks', 'edit', selector, '--due', input, '--json-errors',
        })

        if exit_code == 0 then
            _reload_from_disk(ctx.buf)
        elseif exit_code == -1 then
            return -- rpc.call notified the missing-binary case
        else
            local msg = _ft_message(stdout) or 'tasks edit failed'
            if msg:find(NO_MATCH_MARKER, 1, true) then
                vim.notify('ft: ' .. msg, vim.log.levels.WARN)
            else
                vim.notify('ft: ' .. msg, vim.log.levels.ERROR)
            end
        end
    end)
end

return M
