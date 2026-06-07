--- Note list cache for wikilink autocompletion.
---
--- Builds an in-memory index of all notes in the vault by running
--- `ft graph query 'node where kind in {Note, Ghost}' --format ndjson`.
--- Ghost nodes are included so users can complete links to notes that
--- don't exist yet (referenced from other notes but not yet created).
--- The result is cached so subsequent lookups are instant.
---
--- @module ft.cache

local vault = require('ft.vault')

local M = {}

-- Cached note index: title_lower → { title, path }
local notes = {}
-- Whether the cache has been populated at least once.
local ready = false

--- Fetch the full note list from `ft` and populate the cache.
--- @return boolean  true if the cache was populated successfully
function M.refresh()
    if not vault.get_vault() then
        return false
    end

    local stdout, code = vault.ft_run({
        'graph',
        'query',
        'node where kind in {Note, Ghost}',
        '--format',
        'ndjson',
    })

    if code ~= 0 or not stdout then
        ready = false
        return false
    end

    notes = {}
    for line in stdout:gmatch('[^\r\n]+') do
        local ok, data = pcall(vim.json.decode, line)
        if ok and data and data.title and data.path then
            local key = data.title:lower()
            -- Prefer the first occurrence; later duplicates (same title,
            -- different paths) are ignored to keep the completion menu
            -- clean. The user can disambiguate by path.
            if not notes[key] then
                notes[key] = {
                    title = data.title,
                    path = data.path,
                }
            end
        end
    end

    ready = true
    return true
end

--- Search the cache for notes matching `query`.
--- Matching is case-insensitive prefix / substring.
--- Results are sorted: exact prefix matches first, then by title length.
--- @param query string  The search text (the part after [[)
--- @param max integer|nil  Max results (default: 20)
--- @return table[]  Array of { title, path } records
function M.search(query, max)
    if not ready or next(notes) == nil then
        return {}
    end

    max = max or 20
    local q = query:lower()
    local matches = {}

    for _, info in pairs(notes) do
        if #q == 0 then
            -- Empty query: match everything.
            table.insert(matches, info)
        else
            local t = info.title:lower()
            if t:find(q, 1, true) then
                table.insert(matches, info)
            end
        end
    end

    -- Sort: prefix matches first, then by title length ascending.
    -- When query is empty, all entries are prefix matches (Lua's find
    -- returns 1 for empty pattern), so the fallback sort by title
    -- length gives a stable order.
    table.sort(matches, function(a, b)
        if #q > 0 then
            local a_pref = a.title:lower():find(q, 1, true) == 1
            local b_pref = b.title:lower():find(q, 1, true) == 1
            if a_pref ~= b_pref then
                return a_pref
            end
        end
        return #a.title < #b.title
    end)

    -- Trim to max
    if #matches > max then
        local trimmed = {}
        for i = 1, max do
            trimmed[i] = matches[i]
        end
        return trimmed
    end

    return matches
end

--- Number of cached notes.
--- @return integer
function M.count()
    local n = 0
    for _ in pairs(notes) do
        n = n + 1
    end
    return n
end

--- Whether the cache has been populated.
--- @return boolean
function M.is_ready()
    return ready
end

return M
