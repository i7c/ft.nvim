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

--- Trigger on `[` so blink.cmp re-evaluates after each bracket is typed.
--- Our get_completions returns empty items when not inside `[[...]]`.
--- @return string[]
function source:get_trigger_characters()
    return { '[' }
end

--- @param context blink.cmp.Context
--- @param resolve fun(response: blink.cmp.CompletionResponse)
function source:get_completions(context, resolve)
    local empty = {
        is_incomplete_forward = false,
        is_incomplete_backward = false,
        items = {},
    }

    if not cache.is_ready() then
        resolve(empty)
        return
    end

    local line = context.line
    local cursor_char = context.cursor[2] -- 0-indexed byte position

    -- Find the last `[[` before the cursor.
    -- Lua's `()` capture returns the 1-indexed position AFTER the
    -- captured pattern — i.e., the position right after `[[`.
    local before = line:sub(1, cursor_char)
    local after_open = before:match('.*%[%[()')
    if not after_open then
        resolve(empty)
        return
    end

    -- Text the user has typed BETWEEN `[[` and the cursor.
    -- `after_open` is 1-indexed (position after `[[`), `cursor_char`
    -- is 0-indexed.  For line:sub both can be used as-is since
    --   1-indexed 3 == 0-indexed 2-with-an-offset
    -- and line:sub(3, 4) gives chars at 1-indexed positions 3-4 = "Bu".
    local typed = line:sub(after_open, cursor_char)

    local matches = cache.search(typed, 25)
    if #matches == 0 then
        resolve(empty)
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

    -- Range start (0-indexed): `after_open` is 1-indexed position
    -- after `[[`, so 0-indexed = after_open - 1.
    local range_start = after_open - 1

    local items = {}
    for _, info in ipairs(matches) do
        table.insert(items, {
            label = info.title,
            textEdit = {
                range = {
                    start = { line = line_zero, character = range_start },
                    ['end'] = { line = line_zero, character = end_char },
                },
                newText = info.title .. ']]',
            },
        })
    end

    resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return source
