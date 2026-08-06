--- ft.rangeop — shared editor glue for read-only "copy a line range as X"
--- operations (`ft notes quote`, `ft notes export`).
---
--- Thin editor glue (pillar 1.1): the operation's output text passes
--- through unparsed — Lua never touches the callout or markdown grammars.
--- The pipeline is owned here so the two operations cannot drift:
---   preflight (vault discovered, buffer named + inside vault, saved to
---   disk) → build argv via the operation's command builder → rpc.call
---   → on failure classify and notify (registers untouched) → on success
---   place stdout linewise into the operation's registers and notify.
---
--- @module ft.rangeop

local rpc = require('ft.rpc')
local vault = require('ft.vault')

local M = {}

-- ft error-text marker the plugin classifies (decoded from the
-- `--json-errors` object on failure): a range outside the file is a
-- recoverable user error, so it warns. Operations add their own warn
-- markers (quote's uncommitted-changes) via `classify`.
local RANGE_MARKER = 'outside file'

-- ── Pure helpers (Tier 1 testable) ─────────────────────────────────────────

--- Format a 1-indexed inclusive line range as the `A-B` token
--- `ft notes quote/export -l` expects. Returns nil on invalid ranges
--- (defensive — editor-derived ranges should never violate).
--- @param a integer  first line
--- @param b integer  last line
--- @return string|nil
function M.range_spec(a, b)
    if type(a) ~= 'number' or type(b) ~= 'number' then
        return nil
    end
    if a < 1 or a > b then
        return nil
    end
    return a .. '-' .. b
end

--- Resolve the enabled registers from config into an ordered list of
--- `{ reg, name }` pairs (`"` unnamed, `f` named, `+` clipboard).
--- The clipboard entry is included only when `clipboard_available` is
--- true (nvim built with +clipboard), so a missing clipboard silently
--- drops it without erroring.
--- @param cfg table  registers config (unnamed/named/clipboard booleans)
--- @param clipboard_available boolean
--- @return table[]
function M.register_targets(cfg, clipboard_available)
    local out = {}
    if cfg.unnamed then
        out[#out + 1] = { reg = '"', name = '"' }
    end
    if cfg.named then
        out[#out + 1] = { reg = 'f', name = 'f' }
    end
    if cfg.clipboard and clipboard_available then
        out[#out + 1] = { reg = '+', name = '+' }
    end
    return out
end

--- Classify an ft failure: the shared `outside file` marker and any
--- operation-specific warn markers are warnings (ft's own message
--- already names the remedy), everything else is an error. The plugin
--- never maps these to actions — ft's error text is the remedy.
--- @param msg string
--- @param warn_markers string[]|nil  extra plain-text warn markers
--- @return integer  vim.log.levels.*
function M.classify(msg, warn_markers)
    if msg:find(RANGE_MARKER, 1, true) then
        return vim.log.levels.WARN
    end
    for _, marker in ipairs(warn_markers or {}) do
        if msg:find(marker, 1, true) then
            return vim.log.levels.WARN
        end
    end
    return vim.log.levels.ERROR
end

-- ── Shared mechanics ────────────────────────────────────────────────────────

--- Write the current buffer to disk when it has unsaved changes, so the
--- operation's lines match what the user sees (ft reads from disk). An
--- unmodified buffer is already in sync, so nothing is written.
--- @param buf integer
--- @return boolean
local function _save_buffer(buf)
    if not vim.bo[buf].modified then
        return true
    end
    vim.cmd('silent! write')
    return not vim.bo[buf].modified
end

--- Extract the message from ft's merged stdout/stderr. Failures arrive
--- as a `--json-errors` object on stderr; the rpc sync call merges both
--- streams (with empty stdout the string starts directly at the stderr
--- content), making the whole returned string that document.
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

--- Shared preflight: a vault is discovered, the buffer has a name, the
--- buffer is inside the vault, and the buffer is saved to disk.
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

--- Place the operation's output into one register, linewise. setreg's
--- return value is unreliable in nvim (it reports 0 even on success),
--- so a pcall wrapper is the failure guard; the clipboard is gated
--- upstream by `has('clipboard')`, and a broken provider degrades
--- silently.
--- @param reg string
--- @param content string
--- @return boolean
local function _set_register(reg, content)
    local ok = pcall(vim.fn.setreg, reg, content, 'l')
    return ok
end

-- ── Core ───────────────────────────────────────────────────────────────────

--- Run one read-only range operation end to end. On failure the
--- registers are left untouched (a failed op is not a copy).
---
--- @param spec string|nil  validated `A-B` token, or nil for a
---                         whole-file operation (no `-l`)
--- @param opts table
---   name        string — operation name for default messages
---               (`'<name> failed'`, `'ft ft <name> returned no output'`).
---   cmd         fun(rel: string, spec: string|nil): string[] — argv tail
---               (the `--vault <root>` prefix is injected by rpc).
---   registers   table — the operation's registers config
---               (unnamed/named/clipboard booleans).
---   warn_markers string[]|nil — extra warn markers for `classify`.
---   success     fun(spec: string|nil, set: string[]): string — success
---               notification text; `set` lists the registers actually
---               written. Default: `ft: <name> L<spec> → <regs>`
---               (whole-file ops omit the range).
---   empty       integer|nil — when ft exits 0 with empty output: the
---               notification level at which to report it (a legal
---               result, e.g. export of a frontmatter-only range);
---               register writes are skipped either way. nil treats
---               empty output as an error (quote's contract).
---   empty_msg   string|nil — custom empty-output message (default
---               `'<name> produced no output'`).
function M.run(spec, opts)
    local ctx = _preflight()
    if not ctx then
        return
    end

    local stdout, exit_code = rpc.call(opts.cmd(ctx.rel, spec))

    if exit_code ~= 0 then
        if exit_code == -1 then
            return -- rpc.call already notified the missing-binary case
        end
        local msg = _ft_message(stdout) or (opts.name .. ' failed')
        vim.notify('ft: ' .. msg, M.classify(msg, opts.warn_markers))
        return -- registers untouched
    end

    if not stdout or #stdout == 0 then
        if opts.empty then
            vim.notify(
                'ft: ' .. (opts.empty_msg or (opts.name .. ' produced no output')),
                opts.empty
            )
        else
            vim.notify('ft: ft ' .. opts.name .. ' returned no output', vim.log.levels.ERROR)
        end
        return
    end

    -- The output ends with one newline; a linewise register keeps the
    -- block intact (each line lands on its own line when pasted).
    local targets = M.register_targets(opts.registers, vim.fn.has('clipboard') == 1)
    local set = {}
    for _, t in ipairs(targets) do
        if _set_register(t.reg, stdout) then
            set[#set + 1] = t.name
        end
    end

    local msg = opts.success
        and opts.success(spec, set)
        or ('ft: ' .. opts.name .. (spec and (' L' .. spec) or '') .. ' → '
            .. table.concat(set, ', '))
    vim.notify(msg, vim.log.levels.INFO)
end

return M
