--- Wikilink parsing utilities.
---
--- Recognises the same subset as ft-core's graph parser:
---   [[Target]]
---   [[Target|Display]]
---   [[Target#Anchor]]
---   [[Target#Anchor|Display]]
---   [[#Anchor]]
---   [[#Anchor|Display]]
---   ![[Target]]         (embed — parsed but not consumed by follow)
---
--- @module ft.wikilink

local M = {}

--- Parsed wikilink components.
--- @class Wikilink
--- @field target string  Pre-pipe, pre-anchor target (empty for [[#anchor]])
--- @field anchor string|nil  Post-# text
--- @field display string|nil  Post-| text (alias / link text)
--- @field is_embed boolean  True for ![[...]]
--- @field full_text string  The verbatim source text e.g. "[[Apple|See]]"
--- @field byte_start number  Byte offset of the opening [ (or ! for embeds)
--- @field byte_end number   Byte offset just past the closing ]]
--- @field line number 1-indexed line number

--- Parse all wikilinks from a line of text.
--- Returns an array of Wikilink records in document order.
--- @param line string
--- @param line_num number 1-indexed line number
--- @return Wikilink[]
function M.parse_wikilinks(line, line_num)
    local results = {}
    if not line then
        return results
    end

    local i = 1
    while i <= #line do
        -- Check for ![[ (embed) or [[ (wikilink)
        local is_embed = false
        local start_offset

        if line:byte(i) == 33 and i < #line and line:byte(i + 1) == 91 then -- ![
            if i + 2 <= #line and line:byte(i + 2) == 91 then -- ![[
                is_embed = true
                start_offset = i + 1 -- point at [[, skip the !
            else
                i = i + 1
                goto continue
            end
        elseif line:byte(i) == 91 and i < #line and line:byte(i + 1) == 91 then -- [[
            start_offset = i
        else
            i = i + 1
            goto continue
        end

        -- If we get here, we found [[ at start_offset. Find closing ]].
        local close_pos = line:find(']]', start_offset + 2)
        if not close_pos then
            i = i + 1
            goto continue
        end

        -- Empty body check
        if close_pos == start_offset + 2 then
            i = close_pos + 2
            goto continue
        end

        local body = line:sub(start_offset + 2, close_pos - 1)
        local full_start = is_embed and (start_offset - 1) or start_offset

        local parsed = M.parse_body(body)
        parsed.is_embed = is_embed
        parsed.full_text = line:sub(full_start, close_pos + 1)
        parsed.byte_start = full_start
        parsed.byte_end = close_pos + 1
        parsed.line = line_num

        table.insert(results, parsed)
        i = close_pos + 2

        ::continue::
    end

    return results
end

--- Parse the inner body of a wikilink (between [[ and ]]).
--- Extracts target, anchor, and display.
---
--- Grammar: `target[#anchor][|display]`
---
--- @param body string e.g. "Apple", "Foo#H", "Foo|Bar", "Foo#H|Bar", "#H"
--- @return Wikilink (partial — no position/line fields)
function M.parse_body(body)
    if not body or #body == 0 then
        return { target = '', anchor = nil, display = nil, is_embed = false, full_text = '',
                byte_start = 0, byte_end = 0, line = 0 }
    end

    local display
    local lhs = body
    local pipe_pos = body:find('|')
    if pipe_pos then
        display = body:sub(pipe_pos + 1)
        lhs = body:sub(1, pipe_pos - 1)
    end

    local anchor
    local target = lhs
    local hash_pos = lhs:find('#')
    if hash_pos then
        anchor = lhs:sub(hash_pos + 1)
        target = lhs:sub(1, hash_pos - 1)
    end

    -- [[#Anchor]] — target is empty, anchor is the heading
    if #target == 0 then
        target = ''
    end

    -- Trim target only (anchor/display preserve internal whitespace in Obsidian)
    target = target:match('^%s*(.-)%s*$') or target

    return {
        target = target,
        anchor = (anchor and #anchor > 0) and anchor or nil,
        display = display and #display > 0 and display or nil,
        is_embed = false,
        full_text = '',
        byte_start = 0,
        byte_end = 0,
        line = 0,
    }
end

--- Find the wikilink at the cursor position in a line.
--- @param line string  The full line text
--- @param col number   0-indexed byte column of the cursor
--- @param line_num number  1-indexed line number
--- @return Wikilink|nil  The wikilink at cursor, or nil
function M.wikilink_at_cursor(line, col, line_num)
    local wikilinks = M.parse_wikilinks(line, line_num)

    for _, wl in ipairs(wikilinks) do
        -- col is 0-indexed in Neovim's nvim_win_get_cursor
        -- byte_start/byte_end are 1-indexed from Lua's string indexing
        if col >= (wl.byte_start - 1) and col < wl.byte_end then
            return wl
        end
    end

    return nil
end

return M
