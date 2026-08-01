--- Note list cache for wikilink autocompletion.
---
--- Builds an in-memory index of all notes in the vault by running
--- `ft graph query 'node where kind in {Note, Ghost}' --format ndjson`
--- as an async `rpc.job`. Ghost nodes are included so users can complete
--- links to notes that don't exist yet (referenced from other notes but
--- not yet created).
---
--- Freshness model (see ARCHITECTURE.md, "State & freshness"):
--- the index is DERIVED from disk, never authoritative. It is marked
--- dirty by vault events (BufWritePost / BufDelete / BufNewFile on .md
--- files inside the vault) and by the plugin's own mutations, and
--- rebuilt lazily — at most one rebuild in flight (single-flight via
--- rpc.job). Every successful rebuild bumps a monotonic generation
--- counter; consumers that captured an older generation re-derive.
---
--- @module ft.cache

local rpc = require('ft.rpc')
local vault = require('ft.vault')

local M = {}

-- Cached note index: title_lower → { title, path }
local notes = {}
-- Whether the cache has been populated at least once.
local ready = false
-- Monotonic generation of the current index (bumped on every rebuild).
local generation = 0
-- Dirty flag: set on vault events and own mutations; consumed by the
-- first use after the event (see M.search / M.refresh).
local dirty = false

-- Autocommand group for event-driven invalidation.
local augroup = vim.api.nvim_create_augroup('ft_cache', { clear = true })

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufDelete', 'BufNewFile' }, {
    group = augroup,
    pattern = '*.md',
    callback = function(ev)
        local path = ev.file or vim.api.nvim_buf_get_name(ev.buf)
        if vault.is_inside_vault(path) then
            dirty = true
        end
    end,
})

--- Mark the index dirty (used by the plugin's own mutations).
function M.mark_dirty()
    dirty = true
end

--- Rebuild the note index from `ft graph query`.
--- Async (rpc.job, single-flight on the 'index' kind). Returns true when
--- a job was started; a request while one is in flight coalesces into
--- one follow-up rebuild.
--- @return boolean
function M.refresh()
    if not vault.get_vault() then
        return false
    end
    return rpc.job({
        'graph',
        'query',
        'node where kind in {Note, Ghost}',
        '--format',
        'ndjson',
    }, 'index', function(stdout, exit_code)
        if exit_code ~= 0 or not stdout then
            ready = false
            return
        end

        local rebuilt = {}
        for line in stdout:gmatch('[^\r\n]+') do
            local ok, data = pcall(vim.json.decode, line)
            if ok and data and data.title and data.path then
                local key = data.title:lower()
                -- Prefer the first occurrence; later duplicates (same
                -- title, different paths) are ignored to keep the
                -- completion menu clean. The user can disambiguate by
                -- path.
                if not rebuilt[key] then
                    rebuilt[key] = {
                        title = data.title,
                        path = data.path,
                    }
                end
            end
        end

        notes = rebuilt
        generation = generation + 1
        ready = true
    end)
end

--- Search the cache for notes matching `query`.
--- If the cache is dirty (vault events or own mutations since the last
--- rebuild), kick off a lazy rebuild first and serve from the current
--- index — the next call sees the fresh generation.
--- Matching is case-insensitive prefix / substring.
--- Results are sorted: exact prefix matches first, then by title length.
--- @param query string  The search text (the part after [[)
--- @param max integer|nil  Max results (default: 20)
--- @return table[]  Array of { title, path } records
function M.search(query, max)
    if dirty then
        dirty = false
        M.refresh() -- fire-and-forget; single-flight coalesces
    end
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

--- Monotonic generation of the current index.
--- Consumers that captured an older generation (e.g. a picker opened
--- before a rebuild) compare and re-derive at use time.
--- @return integer
function M.generation()
    return generation
end

return M
