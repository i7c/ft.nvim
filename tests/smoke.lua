--- ft.nvim integration smoke test.
--- Run: `FT_BIN=/path/to/ft/target/release/ft make smoke` (or
--- `FT_BIN=... nvim --headless -l tests/smoke.lua`).
---
--- Needs a real ft binary and a real nvim. Builds a temp fixture vault
--- (`.obsidian/` marker + two notes) and verifies:
---   1. setup warns on an artificially old `ft --version` (stub script)
---   2. follow resolves a [[wikilink]] to the target note
---   3. the completion index rebuilds (async) and finds the notes
---   4. a legacy `embeds` config key loads without error and embed.lua
---      no longer exists (embeds removal)

local failures = 0

local function ok(cond, msg)
    if cond then
        print('ok   - ' .. msg)
    else
        failures = failures + 1
        print('FAIL - ' .. msg)
    end
end

-- Capture notifications so the version-warning test can assert.
local notified = {}
vim.notify = function(msg, _lvl)
    table.insert(notified, msg)
end

local real_bin = vim.fn.environ()['FT_BIN']
if not real_bin or #real_bin == 0 then
    print('smoke test requires a real ft binary: set $FT_BIN (e.g. ../ft/target/release/ft)')
    vim.cmd('cquit')
    return
end

-- nvim -l mode doesn't load user config; make the plugin loadable.
vim.opt.rtp:prepend(vim.fn.getcwd())

-- ── Fixture vault ──────────────────────────────────────────────────────────

local base = vim.fn.tempname() .. '.ftnvim'
vim.fn.mkdir(base .. '/.obsidian', 'p')
vim.fn.mkdir(base .. '/Notes', 'p')
local apple = base .. '/Notes/Apple.md'
local banana = base .. '/Notes/Banana.md'
vim.fn.writefile({ '# Apple', '', 'See [[Banana]] for details.' }, apple)
vim.fn.writefile({ '# Banana', '', 'The banana note.' }, banana)
vim.fn.setenv('FT_VAULT', base)

-- ── 1. Version warning with an artificially old ft ─────────────────────────

local stub = base .. '/fake-old-ft'
vim.fn.writefile({ '#!/bin/sh', 'echo "ft 0.0.1"' }, stub)
vim.fn.setfperm(stub, 'rwx------')
vim.fn.setenv('FT_BIN', stub)

-- Also exercises the embeds-removal path: a legacy `embeds` config key
-- must load without error (it is simply ignored).
local setup_ok = pcall(function()
    require('ft').setup({
        embeds = { enable = true, max_lines = 5 },
    })
end)
ok(setup_ok, 'setup with legacy embeds config key loads without error')

local warned = false
for _, m in ipairs(notified) do
    if m:find('older than the required 0.1.0', 1, true) then
        warned = true
    end
end
ok(warned, 'version warning fired for stub ft 0.0.1')

local embed_exists = vim.fn.filereadable(vim.fn.getcwd() .. '/lua/ft/embed.lua') == 1
ok(not embed_exists, 'embed.lua no longer exists (embeds removed)')

-- ── 2. Follow, 3. Completion with the real binary ──────────────────────────

vim.fn.setenv('FT_BIN', real_bin)

-- Open Apple.md (fires FileType → _setup_buffer → async cache refresh).
vim.cmd('edit ' .. vim.fn.fnameescape(apple))

-- Follow [[Banana]]: cursor inside the wikilink on line 3.
vim.api.nvim_win_set_cursor(0, { 3, 8 })
local follow = require('ft.follow')
follow.follow_wikilink()
local current = vim.api.nvim_buf_get_name(0)
ok(current:find('Banana%.md$') ~= nil, 'follow opened the linked note (' .. current .. ')')

-- Completion index: async rebuild, then search.
local cache = require('ft.cache')
cache.refresh()
local ready = vim.wait(10000, function()
    return cache.is_ready()
end)
ok(ready, 'completion index rebuilt (async, single-flight)')
local banana_hits = cache.search('ban', 5)
ok(#banana_hits == 1 and banana_hits[1].title == 'Banana', 'completion finds Banana')
local apple_hits = cache.search('app', 5)
ok(#apple_hits == 1 and apple_hits[1].title == 'Apple', 'completion finds Apple')
ok(cache.generation() >= 1, 'generation counter bumped on rebuild')

-- ── summary ─────────────────────────────────────────────────────────────────

if failures > 0 then
    print('\n' .. failures .. ' failure(s)')
    vim.cmd('cquit')
else
    print('\nall smoke tests passed')
end
