--- ft.export — export a line range (or the whole note) of the current
--- buffer as clean CommonMark (`ft notes export`) into the registers.
---
--- Thin editor glue (pillar 1.1): the exported text from ft passes
--- through unparsed — Lua never touches the markdown conversion rules.
--- The inverse of quote: `gz` wraps a range *into* a pinned
--- `[!ft-source]` callout, `gy` *strips* vault structure (frontmatter,
--- `[!ft-source]` callout headers, wikilinks) so the output is portable
--- markdown for pasting outside the vault. The shared range-op pipeline
--- (preflight, save, classify, register placement) lives in
--- `ft.rangeop`; this module owns the export specifics: argv, the
--- legal-empty-output path (a range fully inside the frontmatter
--- exports nothing — ft strips it — and that is success, not an error),
--- and the notification text.
---
--- Entry points:
---   M.export_range(a, b)    — export the inclusive line range
---   M.export_whole_file()   — export the whole buffer (no `-l`, the
---                             CLI's whole-file default); `:FtExport`
---                             with no range
---   M.operatorfunc()        — `g@` callback (motions AND visual
---                             selections, same rationale as quote)
---   M.export_selection()    — scripted path for a committed selection
---
--- Registers: the exported text lands linewise in the unnamed register
--- `"`, the named register `f` (shared with quote — the ft copy
--- register, last op wins), and the system clipboard `"+`. Each is
--- disable-able via the `export.registers` config; a missing clipboard
--- degrades silently. A failed export writes nothing; an empty export
--- is reported at INFO with the registers left untouched.
---
--- @module ft.export

local rangeop = require('ft.rangeop')

local M = {}

-- nvim's `v:lua.` operatorfunc string form resolves only simple global
-- expressions (the `v:lua.require("mod").fn` form is a silent no-op),
-- so the g@ callback is exposed on a uniquely-named global the
-- operatorfunc string can name.
_G.ft_export_operator = function()
    M.operatorfunc()
end

-- Configured registers (set by export.setup() from init.lua).
local registers = {
    unnamed = true,
    named = true,
    clipboard = true,
}

--- Apply the `export` config section (called from init.lua setup).
--- @param cfg table  merged export config
function M.setup(cfg)
    registers = cfg.registers
end

-- ── Core ───────────────────────────────────────────────────────────────────

--- Export the inclusive line range [a, b] of the current buffer as
--- clean CommonMark and place it linewise into the configured
--- registers. On failure the registers are left untouched.
--- @param a integer  first line (1-indexed)
--- @param b integer  last line (1-indexed)
function M.export_range(a, b)
    local spec = rangeop.range_spec(a, b)
    if not spec then
        vim.notify(
            'ft: invalid line range ' .. tostring(a) .. '-' .. tostring(b),
            vim.log.levels.ERROR
        )
        return
    end

    rangeop.run(spec, {
        name = 'export',
        registers = registers,
        cmd = function(rel, s)
            return { 'notes', 'export', rel, '-l', s, '--json-errors' }
        end,
        -- A range fully inside the frontmatter is a legal empty export:
        -- ft exits 0 with nothing (frontmatter is never exported, and the
        -- start clamps past it). Report at INFO, never clobber registers.
        empty = vim.log.levels.INFO,
        empty_msg = 'export is empty — nothing left after stripping frontmatter and callout headers',
        success = function(s, set)
            return 'ft: exported L' .. s .. ' → ' .. table.concat(set, ', ')
        end,
    })
end

--- Export the whole current buffer as clean CommonMark (no `-l` — the
--- CLI's whole-file default) and place it into the registers.
--- `:FtExport` with no range.
function M.export_whole_file()
    rangeop.run(nil, {
        name = 'export',
        registers = registers,
        cmd = function(rel)
            return { 'notes', 'export', rel, '--json-errors' }
        end,
        empty = vim.log.levels.INFO,
        empty_msg = 'export is empty — nothing left after stripping frontmatter and callout headers',
        success = function(_, set)
            return 'ft: exported whole note → ' .. table.concat(set, ', ')
        end,
    })
end

--- The `g@` operator callback: export the range covered by the motion.
--- g@ sets `'[` and `']` before invoking this; the min/max guards the
--- odd inverted-marks case of no-op motions.
function M.operatorfunc()
    local a = vim.fn.line("'[")
    local b = vim.fn.line("']")
    if a > b then
        a, b = b, a
    end
    M.export_range(a, b)
end

--- Build the normal-mode operator keymap callback: an expr mapping that
--- arms `operatorfunc` and returns `g@`, so the next motion is applied
--- and `M.operatorfunc` runs with `'[`/`']` set. The caller must pass
--- `{ expr = true }`.
--- @return function
function M.operator_rhs()
    return function()
        vim.o.operatorfunc = 'v:lua.ft_export_operator'
        return 'g@'
    end
end

--- Export the visual selection's line span (`'<` .. `'>`).
--- Only correct when the visual marks are committed (see quote for the
--- rationale); the visual `gy` keymap uses the operator path instead.
function M.export_selection()
    M.export_range(vim.fn.line("'<"), vim.fn.line("'>"))
end

return M
