--- Blink.cmp source for wikilink completion.
---
--- Registered programmatically by `ft.complete.setup()` — no user config
--- changes needed. Provides note title completions when the cursor is
--- inside `[[...]]` in markdown files.
---
--- @module ft.blink

local cache = require('ft.cache')

local source = {}

--- @param opts table
--- @param _config table  blink.cmp.SourceProviderConfig
--- @return blink.cmp.Source
function source.new(opts, _config)
    return setmetatable({}, { __index = source })
end

--- @param context blink.cmp.Context
--- @param resolve fun(response: blink.cmp.CompletionResponse)
function source:get_completions(context, resolve)
    if not cache.is_ready() then
        resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
        return
    end

    local line = context.line
    local cursor_char = context.cursor[2] -- 0-indexed byte position

    -- Find the last `[[` before the cursor, capturing the typed text.
    local before = line:sub(1, cursor_char)
    local start_col = before:match('.*%[%[()') -- 1-indexed position of opening [[

    if not start_col then
        resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
        return
    end

    -- Text the user has typed between [[ and cursor.
    local typed = line:sub(start_col + 2, cursor_char)

    local matches = cache.search(typed, 25)
    if #matches == 0 then
        resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
        return
    end

    -- Determine end of range: extend past cursor to eat any `]]` that
    -- auto-pair plugins may have already inserted.
    local after = line:sub(cursor_char + 1, cursor_char + 2)
    local end_char = cursor_char
    if after == ']]' then
        end_char = cursor_char + 2
    end

    local line_zero = context.cursor[1] - 1 -- blink uses 0-indexed lines

    local items = {}
    for _, info in ipairs(matches) do
        table.insert(items, {
            label = info.title,
            textEdit = {
                range = {
                    start = { line = line_zero, character = start_col + 1 }, -- after [[
                    ['end'] = { line = line_zero, character = end_char },
                },
                newText = info.title .. ']]',
            },
        })
    end

    resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return source
