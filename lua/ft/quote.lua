--- ft.quote — quote a line range of the current note as a protected
--- section (`ft notes quote`) into the registers.
---
--- Thin editor glue (pillar 1.1): the callout text from ft passes
--- through unparsed — Lua never touches the `[!ft-source]` grammar.
--- The shared range-op pipeline (preflight, save, classify, register
--- placement) lives in `ft.rangeop`; this module owns only the quote
--- specifics: argv, the dirty-source warn marker, and the notification
--- text. Entry points, all funneling into `quote_range(a, b)`:
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
--- written by this plugin — export shares it, last op wins), and the
--- system clipboard `"+` (cross-session paste for `clipboard=unnamedplus`
--- users). Each is disable-able via the `quote.registers` config; a
--- missing clipboard degrades silently — the success notification lists
--- only the registers that were set, and a failed quote writes nothing
--- (registers are only touched on exit 0).
---
--- @module ft.quote

local rangeop = require('ft.rangeop')

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

-- ft error-text marker the plugin classifies (decoded from the
-- `--json-errors` object on failure) — a dirty source means the
-- pinning callout would not reproduce the working tree, and ft's own
-- message names the remedy (commit or stash first). The shared
-- `outside file` marker warns via rangeop.classify.
local DIRTY_MARKER = 'has uncommitted changes'

--- Apply the `quote` config section (called from init.lua setup).
--- @param cfg table  merged quote config
function M.setup(cfg)
    registers = cfg.registers
end

--- Format a 1-indexed inclusive line range as the `A-B` token
--- `ft notes quote -l` expects. Delegates to the shared rangeop core.
--- @param a integer  first line
--- @param b integer  last line
--- @return string|nil
function M.range_spec(a, b)
    return rangeop.range_spec(a, b)
end

--- Resolve the enabled registers from config into an ordered list of
--- `{ reg, name }` pairs (`"` unnamed, `f` named, `+` clipboard).
--- Delegates to the shared rangeop core.
--- @param cfg table  registers config (unnamed/named/clipboard booleans)
--- @param clipboard_available boolean
--- @return table[]
function M.register_targets(cfg, clipboard_available)
    return rangeop.register_targets(cfg, clipboard_available)
end

-- ── Core ───────────────────────────────────────────────────────────────────

--- Quote the inclusive line range [a, b] of the current buffer as a
--- protected section: run `ft notes quote`, place the returned callout
--- linewise into the configured registers, and notify. On failure the
--- registers are left untouched (a failed quote is not a quote).
--- @param a integer  first line (1-indexed)
--- @param b integer  last line (1-indexed)
function M.quote_range(a, b)
    local spec = M.range_spec(a, b)
    if not spec then
        vim.notify(
            'ft: invalid line range ' .. tostring(a) .. '-' .. tostring(b),
            vim.log.levels.ERROR
        )
        return
    end

    rangeop.run(spec, {
        name = 'notes quote',
        registers = registers,
        warn_markers = { DIRTY_MARKER },
        cmd = function(rel, s)
            return { 'notes', 'quote', rel, '-l', s, '--json-errors' }
        end,
        success = function(s, set)
            return 'ft: quoted L' .. s .. ' → ' .. table.concat(set, ', ')
        end,
    })
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
