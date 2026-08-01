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
---   5. task operations: create at cursor (inline due:+2d → ISO date,
---      duplicate allowed), done, cancel, idempotent already-done, and
---      non-task warning

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

-- ── 5. Task operations with the real binary ────────────────────────────────

local tasks = require('ft.tasks')

-- Mock vim.ui.input for the create prompt: `ui_answer` nil → prefill.
local ui_answer = nil
vim.ui.input = function(opts, cb)
    cb(ui_answer ~= nil and ui_answer or opts.default)
end

local task_note = base .. '/Notes/Tasks.md'
vim.fn.writefile({ '# Tasks', '', '- [ ] Write report', '- [ ] Call dentist' }, task_note)
vim.cmd('edit ' .. vim.fn.fnameescape(task_note))

local function buf_line(n)
    return vim.api.nvim_buf_get_lines(0, n - 1, n, false)[1]
end
local function find_line(pat)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
        if l:match(pat) then
            return i
        end
    end
    return nil
end

local today = os.date('%Y-%m-%d')
local due2 = os.date('%Y-%m-%d', os.time() + 2 * 86400)

-- Create on the empty line 2 with an inline relative due date.
vim.api.nvim_win_set_cursor(0, { 2, 0 })
ui_answer = 'Write report due:+2d'
tasks.create()
local created = buf_line(2)
ok(created:match('%- %[ %] Write report') ~= nil, 'create inserted the task at the cursor line')
ok(created:find('📅 ' .. due2, 1, true) ~= nil, 'due:+2d became the ISO due date ' .. due2)
ok(created:find('➕ ' .. today, 1, true) ~= nil, 'created date is today')
local cur = vim.api.nvim_win_get_cursor(0)
ok(cur[1] == 2 and cur[2] == 0, 'cursor lands on the new task')
ok(vim.bo[0].modified == false, 'buffer is clean after the create reload')

-- Duplicate create is allowed (--force): a second identical line appears.
vim.api.nvim_win_set_cursor(0, { 2, 0 })
ui_answer = 'Write report due:+2d'
tasks.create()
local dup_count = 0
for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l == created then
        dup_count = dup_count + 1
    end
end
ok(dup_count == 2, 'duplicate create allowed (' .. dup_count .. ' identical task lines)')

-- Done: the task under the cursor becomes - [x] with ✅ today.
local done_line = find_line('^%- %[ %] Write report')
vim.api.nvim_win_set_cursor(0, { done_line, 0 })
tasks.done()
local done_text = buf_line(done_line)
ok(done_text:match('%- %[x%] Write report') ~= nil and done_text:find('✅ ' .. today, 1, true) ~= nil,
    'done rewrote the line with ✅ today')

-- Done on an already-done task: info notification, file untouched.
local notified_before = #notified
vim.api.nvim_win_set_cursor(0, { done_line, 0 })
tasks.done()
ok(#notified == notified_before + 1
    and notified[#notified]:find('is already done', 1, true) ~= nil,
    'already-done surfaces an info notification, not an error')
ok(buf_line(done_line) == done_text, 'already-done leaves the line untouched')

-- Non-task line: ft\'s "no tasks match selector" warning.
notified_before = #notified
vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- '# Tasks'
tasks.done()
ok(#notified == notified_before + 1
    and notified[#notified]:find('no tasks match selector', 1, true) ~= nil,
    'non-task line surfaces a warning')

-- Cancel: the task under the cursor becomes - [-] with ❌ today.
local cancel_line = find_line('Call dentist')
vim.api.nvim_win_set_cursor(0, { cancel_line, 0 })
tasks.cancel()
local cancel_text = buf_line(cancel_line)
ok(cancel_text:match('%- %[%-%] Call dentist') ~= nil
    and cancel_text:find('❌ ' .. today, 1, true) ~= nil,
    'cancel rewrote the line with [-] … ❌ today')

-- Due date edit: set via +7d, clear via none, bad date errors.
local due_line = find_line('^%- %[ %] Write report')
vim.api.nvim_win_set_cursor(0, { due_line, 0 })
ui_answer = '+7d'
tasks.set_due()
local due7 = os.date('%Y-%m-%d', os.time() + 7 * 86400)
local due_text = buf_line(due_line)
ok(due_text:find('📅 ' .. due7, 1, true) ~= nil, 'set_due wrote the ISO date ' .. due7)

ui_answer = 'none'
tasks.set_due()
ok(buf_line(due_line):find('📅', 1, true) == nil, 'set_due none cleared the due date')

notified_before = #notified
vim.api.nvim_win_set_cursor(0, { due_line, 0 })
ui_answer = 'not-a-date'
tasks.set_due()
ok(#notified == notified_before + 1
    and notified[#notified]:find('could not parse', 1, true) ~= nil,
    'invalid due input surfaces ft\'s parse error')

-- ── summary ─────────────────────────────────────────────────────────────────

if failures > 0 then
    print('\n' .. failures .. ' failure(s)')
    vim.cmd('cquit')
else
    print('\nall smoke tests passed')
end
