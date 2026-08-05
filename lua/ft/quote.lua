--- ft.quote — quote a line range of the current note as a protected
--- section (`ft notes quote`) into the registers.
---
--- Thin editor glue (pillar 1.1): the callout text from ft passes
--- through unparsed — Lua never touches the `[!ft-source]` grammar.
--- Entry points, all funneling into `quote_range(a, b)`:
---   M.quote_range(a, b)  — the one core path (runs ft, sets registers)
---   M.operatorfunc()     — `g@` callback: quotes the motion's `'[`..`']`
---                         (normal-mode motions AND visual selections —
---                         in visual mode `g@` applies the operator to the
---                         selection, because `'<`/`'>` marks are not yet
---                         committed when a visual keymap callback runs)
---   :FtQuote (range command) — current line in normal mode, selection
---                             in visual mode (`'<,'>` is committed by nvim
---                             for commands, unlike marks in a callback)
---
--- Registers: the callout lands linewise in the unnamed register `"`
--- (plain `p` pastes), a named register `f` (stable home, only ever
--- written by this plugin), and the system clipboard `"+` (cross-session
--- paste for `clipboard=unnamedplus` users). Each is disable-able via
--- the `quote.registers` config; a missing clipboard degrades silently —
--- the success notification lists only the registers that were set, and
--- a failed quote writes nothing (registers are only touched on exit 0).
---
--- @module ft.quote

local rpc = require('ft.rpc')
local vault = require('ft.vault')

local M = {}

-- nvim's `v:lua.` operatorfunc string form resolves only simple global
-- expressions (the `v:lua.require("mod").fn` form is a silent no-op),
-- so the g@ callback is exposed on a uniquely-named global the
-- operatorfunc string can name.
_G.ft_quote_operator = function()
    M.operatorfunc()
end

-- Configured registers (set by quote.setup() from init.lua).
local registers = {
    unnamed = true,
    named = true,
    clipboard = true,
}

-- ft error-text markers the plugin classifies (ft/src/cmd/quote.rs,
-- decoded from the `--json-errors` object on failure).
local DIRTY_MARKER = 'has uncommitted changes'
local RANGE_MARKER = 'outside file'

--- Apply the `quote` config section (called from init.lua setup).
--- @param cfg table  merged quote config
function M.setup(cfg)
    registers = cfg.registers
end

-- ── Pure helpers (Tier 1 testable) ─────────────────────────────────────────

--- Format a 1-indexed inclusive line range as the `A-B` token
--- `ft notes quote -l` expects. Returns nil on invalid ranges
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

-- ── Shared mechanics ────────────────────────────────────────────────────────

--- Write the current buffer to disk when it has unsaved changes, so the
--- pinned lines match what the user sees (ft reads from disk). An
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
--- streams, making the whole returned string that document.
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

--- Classify an `ft notes quote` failure: expected, recoverable
--- conditions are warnings (ft's own message already names the remedy —
--- a dirty source says "commit or stash first"), everything else is an
--- error. The plugin never maps these to actions; it must not touch git.
--- @param msg string
--- @return integer  vim.log.levels.*
local function _classify(msg)
    if msg:find(DIRTY_MARKER, 1, true) or msg:find(RANGE_MARKER, 1, true) then
        return vim.log.levels.WARN
    end
    return vim.log.levels.ERROR
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

--- Place the callout into one register, linewise. setreg's return value
--- is unreliable in nvim (it reports 0 even on success), so a pcall
--- wrapper is the failure guard; the clipboard is gated upstream by
--- `has('clipboard')`, and a broken provider degrades silently.
--- @param reg string
--- @param content string
--- @return boolean
local function _set_register(reg, content)
    local ok = pcall(vim.fn.setreg, reg, content, 'l')
    return ok
end

-- ── Core ───────────────────────────────────────────────────────────────────

--- Quote the inclusive line range [a, b] of the current buffer as a
--- protected section: run `ft notes quote`, place the returned callout
--- linewise into the configured registers, and notify. On failure the
--- registers are left untouched (a failed quote is not a quote).
--- @param a integer  first line (1-indexed)
--- @param b integer  last line (1-indexed)
function M.quote_range(a, b)
    local ctx = _preflight()
    if not ctx then
        return
    end

    local spec = M.range_spec(a, b)
    if not spec then
        vim.notify(
            'ft: invalid line range ' .. tostring(a) .. '-' .. tostring(b),
            vim.log.levels.ERROR
        )
        return
    end

    local stdout, exit_code = rpc.call({
        'notes', 'quote', ctx.rel, '-l', spec, '--json-errors',
    })

    if exit_code ~= 0 then
        if exit_code == -1 then
            return -- rpc.call already notified the missing-binary case
        end
        local msg = _ft_message(stdout) or 'notes quote failed'
        vim.notify('ft: ' .. msg, _classify(msg))
        return -- registers untouched
    end

    if not stdout or #stdout == 0 then
        vim.notify('ft: ft notes quote returned no output', vim.log.levels.ERROR)
        return
    end

    -- ft's callout ends with one newline; a linewise register keeps the
    -- block intact (each `> ` line lands on its own line when pasted).
    local targets = M.register_targets(registers, vim.fn.has('clipboard') == 1)
    local set = {}
    for _, t in ipairs(targets) do
        if _set_register(t.reg, stdout) then
            set[#set + 1] = t.name
        end
    end

    vim.notify(
        'ft: quoted L' .. spec .. ' → ' .. table.concat(set, ', '),
        vim.log.levels.INFO
    )
end

--- The `g@` operator callback: quote the range covered by the motion.
--- g@ sets `'[` and `']` before invoking this; the min/max guards the
--- odd inverted-marks case of no-op motions.
function M.operatorfunc()
    local a = vim.fn.line("'[")
    local b = vim.fn.line("']")
    if a > b then
        a, b = b, a
    end
    M.quote_range(a, b)
end

--- Build the normal-mode operator keymap callback: an expr mapping that
--- arms `operatorfunc` and returns `g@`, so the next motion is applied
--- and `M.operatorfunc` runs with `'[`/`']` set. The caller must pass
--- `{ expr = true }`.
--- @return function
function M.operator_rhs()
    return function()
        vim.o.operatorfunc = 'v:lua.ft_quote_operator'
        return 'g@'
    end
end

--- Quote the visual selection's line span (`'<` .. `'>`).
--- Only correct when the visual marks are committed (i.e. NOT from a
--- visual-mode keymap callback — nvim commits `'<`/`'>` only when visual
--- mode exits, so the visual `gz` keymap uses the operator path instead,
--- see `operatorfunc`). Kept for scripted use after a selection ends.
function M.quote_selection()
    M.quote_range(vim.fn.line("'<"), vim.fn.line("'>"))
end

return M
