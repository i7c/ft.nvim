--- ft.picker — picker seam.
---
--- The backend decision is deferred and reversible per feature, exactly
--- like ft.rpc defers the transport decision. Two entry points:
---
---   select(items, opts) — single-choice picker.
---     Default backend: vim.ui.select, which delegates to the user's own
---     global override when one is installed (telescope, dressing,
---     fzf-lua all ship overrides) — so the zero-dep default
---     automatically becomes "whatever picker the user configured."
---     Telescope and fzf-lua are feature-detected and used only when the
---     user has enabled them (config `picker = { backend = 'auto' |
---     'select' | 'telescope' | 'fzf-lua' }`).
---
---   multi(items, opts) — declared but NOT implemented. vim.ui.select
---     has no multi-select concept, so this needs a real backend
---     (telescope `multi`, fzf-lua `multi = true`, or a custom picker).
---     The first feature that requires it (Gather's send-selected-
---     entries-to-synth) forces that decision; until then this raises a
---     clear error instead of silently degrading to single-select.
---
--- @module ft.picker

local M = {}

-- Config resolved at setup; nil until then (auto backend).
--- @type table|nil
local config = nil

--- Configure the picker (called from ft.setup with the `picker` key).
--- @param opts table|nil  { backend = 'auto'|'select'|'telescope'|'fzf-lua' }
function M.setup(opts)
    config = opts
end

local function telescope_available()
    return pcall(require, 'telescope')
end

local function fzf_lua_available()
    return pcall(require, 'fzf-lua')
end

--- Resolve the effective backend from config.
--- 'auto' (default): fzf-lua if installed, else telescope if installed,
--- else vim.ui.select. An explicitly requested backend that is not
--- installed degrades to vim.ui.select.
--- @return string  'select' | 'telescope' | 'fzf-lua'
local function resolve_backend()
    local pref = (config or {}).backend or 'auto'
    if pref == 'select' then
        return 'select'
    end
    if pref == 'telescope' then
        if telescope_available() then
            return 'telescope'
        end
        return 'select'
    end
    if pref == 'fzf-lua' then
        if fzf_lua_available() then
            return 'fzf-lua'
        end
        return 'select'
    end
    -- auto
    if fzf_lua_available() then
        return 'fzf-lua'
    end
    if telescope_available() then
        return 'telescope'
    end
    return 'select'
end

local function telescope_select(items, opts)
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local sorters = require('telescope.sorters')

    pickers
        .new({}, {
            prompt_title = opts.prompt or 'Select',
            finder = finders.new_table({
                results = items,
                entry_maker = function(item, idx)
                    return {
                        value = item,
                        ordinal = idx,
                        display = opts.format_item
                                and opts.format_item(item)
                            or tostring(item),
                    }
                end,
            }),
            sorter = sorters.get_generic_fuzzy_sorter(),
            on_choice = function(selection)
                if selection then
                    opts.on_choice(selection.value)
                else
                    opts.on_choice(nil)
                end
            end,
        })
        :find()
end

local function fzf_select(items, opts)
    local fzf = require('fzf-lua')

    -- fzf-lua operates on display strings; map them back to the
    -- original items on selection.
    local by_display = {}
    local entries = {}
    for i, item in ipairs(items) do
        local display = opts.format_item and opts.format_item(item)
            or tostring(item)
        by_display[display] = item
        entries[i] = display
    end

    fzf.fzf_exec(entries, {
        prompt = (opts.prompt or 'Select') .. '> ',
        actions = {
            ['default'] = function(selected)
                local choice = selected and selected[1]
                if choice and by_display[choice] then
                    opts.on_choice(by_display[choice])
                else
                    opts.on_choice(nil)
                end
            end,
        },
    })
end

--- Single-choice picker over `items`.
--- @param items table[]  Items to choose from (any type)
--- @param opts table  { prompt = string|nil, format_item = fun(item):
---   string|nil, on_choice = fun(item|nil) }
function M.select(items, opts)
    opts = opts or {}
    local backend = resolve_backend()
    if backend == 'telescope' then
        telescope_select(items, opts)
        return
    end
    if backend == 'fzf-lua' then
        fzf_select(items, opts)
        return
    end
    -- Default: vim.ui.select — delegates to the user's override.
    vim.ui.select(items, {
        prompt = opts.prompt or 'Select',
        format_item = opts.format_item,
    }, function(choice)
        opts.on_choice(choice)
    end)
end

--- Multi-select picker. NOT IMPLEMENTED — declared so features can be
--- written against the seam now and the backend decision stays local.
--- @param _items table[]
--- @param _opts table
function M.multi(_items, _opts)
    error(
        'ft.picker.multi: multi-select is not yet implemented. '
            .. 'The first feature that needs it (Gather multi-send) will '
            .. 'choose the backend (telescope / fzf-lua / custom).'
    )
end

return M
