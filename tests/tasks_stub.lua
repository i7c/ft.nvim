--- ft.nvim Tier 2 tests — editor behavior against a stub ft binary.
--- Run: `nvim --headless -l tests/tasks_stub.lua` (wired into `make test`).
---
--- The stub (a small sh script) logs its argv for exact-shape assertions
--- and emulates ft's on-disk mutations: it inserts a task line at
--- `--at-line` and rewrites `- [ ]` → `- [x]` / `- [-]` at the selector
--- line, then emits canned stdout / JSON errors per `$FT_STUB_MODE`.
--- No real ft binary needed — this suite pins the editor glue:
--- argv shape, save-before-mutate, reload-with-undo, idempotency
--- classification, cursor placement, missing-binary and outside-vault
--- paths.

vim.opt.rtp:prepend(vim.fn.getcwd())

local failures = 0

local function ok(cond, msg)
    if cond then
        print('ok   - ' .. msg)
    else
        failures = failures + 1
        print('FAIL - ' .. msg)
    end
end

-- ── Fixture vault + stub binary ───────────────────────────────────────────

local base = vim.fn.tempname() .. '.ftstub'
vim.fn.mkdir(base .. '/.obsidian', 'p')

local inbox = base .. '/inbox.md'

local stub = base .. '/ft-stub'
vim.fn.writefile({
    '#!/bin/sh',
    '# Tier 2 stub ft: log argv, emulate on-disk mutations, canned errors.',
    'log="${FT_STUB_LOG:?}"',
    'echo "$@" >> "$log"',
    'for a in "$@"; do',
    '  if [ "$a" = "--version" ]; then echo "ft 0.1.0"; exit 0; fi',
    'done',
    'vault=""; subcmd=""; desc=""; file=""; at_line=""; selector=""',
    'while [ $# -gt 0 ]; do',
    '  case "$1" in',
    '    --vault) vault="$2"; shift 2 ;;',
    '    --file) file="$2"; shift 2 ;;',
    '    --at-line) at_line="$2"; shift 2 ;;',
    '    --force|--yes|--json-errors|--edit) shift ;;',
    '    tasks) subcmd="$2"; shift 2 ;;',
    '    *)',
    '      if [ "$subcmd" = "create" ] && [ -z "$desc" ]; then desc="$1"',
    '      elif { [ "$subcmd" = "complete" ] || [ "$subcmd" = "cancel" ]; } && [ -z "$selector" ]; then selector="$1"',
    '      fi',
    '      shift ;;',
    '  esac',
    'done',
    'case "$subcmd" in',
    '  create)',
    '    abs="$vault/$file"',
    '    if [ -n "$at_line" ]; then',
    '      sed -i "${at_line}i- [ ] ${desc}" "$abs"',
    '    fi',
    '    echo "Created task at $file:$at_line"',
    '    exit 0',
    '    ;;',
    '  complete|cancel)',
    '    f="${selector%:*}"',
    '    l="${selector##*:}"',
    '    abs="$vault/$f"',
    '    case "${FT_STUB_MODE:-success}" in',
    '      success)',
    '        if [ "$subcmd" = "complete" ]; then',
    '          sed -i "${l}s/^- \\[ \\]/- [x]/" "$abs"',
    '        else',
    '          sed -i "${l}s/^- \\[ \\]/- [-]/" "$abs"',
    '        fi',
    '        if [ "$subcmd" = "complete" ]; then echo "Completed $f:$l"; else echo "Cancelled $f:$l"; fi',
    '        exit 0',
    '        ;;',
    '      already_done)',
    '        echo \'{"chain":["task at \'"$f"\':\'"$l"\' is already done (on 2026-08-01)"],"error":"task at \'"$f"\':\'"$l"\' is already done (on 2026-08-01)"}\' >&2',
    '        exit 1',
    '        ;;',
    '      no_match)',
    '        echo \'{"chain":["no tasks match selector `\'"$f"\':\'"$l"\'`"],"error":"no tasks match selector `\'"$f"\':\'"$l"\'`"}\' >&2',
    '        exit 1',
    '        ;;',
    '      hard_error)',
    '        echo \'{"chain":["line changed on disk"],"error":"task at \'"$f"\':\'"$l"\' changed on disk — rescan and retry"}\' >&2',
    '        exit 1',
    '        ;;',
    '      *) exit 0 ;;',
    '    esac',
    '    ;;',
    '  *) exit 0 ;;',
    'esac',
}, stub)
vim.fn.setfperm(stub, 'rwx------')

local log = base .. '/stub.log'
local function log_lines()
    if vim.fn.filereadable(log) == 1 then
        return vim.fn.readfile(log)
    end
    return {}
end

vim.fn.setenv('FT_VAULT', base)
vim.fn.setenv('FT_BIN', stub)
vim.fn.setenv('FT_STUB_LOG', log)
vim.fn.setenv('FT_STUB_MODE', 'success')

-- Capture notifications (level = vim.log.levels.*).
local notified = {}
vim.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
end
local function last_notify()
    return notified[#notified]
end

-- Mock vim.ui.input: `next_input` nil → confirm the prefill (default);
-- `false` → cancel the prompt; a string → answer with it.
local next_input = nil
local last_prompt = nil
vim.ui.input = function(opts, cb)
    last_prompt = opts
    if next_input == false then
        cb(nil)
    elseif next_input == nil then
        cb(opts.default)
    else
        cb(next_input)
    end
end

local function reset_state(content)
    vim.fn.writefile(content, inbox)
    vim.fn.delete(log)
    notified = {}
    next_input = nil
    vim.fn.setenv('FT_STUB_MODE', 'success')
    -- edit! discards any leftover buffer state between scenarios (a
    -- previous undo may have left the buffer modified).
    vim.cmd('edit! ' .. vim.fn.fnameescape(inbox))
    -- -l mode skips filetype detection; fire the FileType event by hand
    -- so _setup_buffer (keymaps) runs like it does interactively.
    vim.cmd('setfiletype markdown')
end

local function buf_lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end
local function file_lines()
    return vim.fn.readfile(inbox)
end

-- Load the plugin (version check hits the stub; commands + keymaps wire up).
require('ft').setup({})

-- ── Create ─────────────────────────────────────────────────────────────────

reset_state({ '# Inbox', '', '- [ ] Buy milk', '- [ ] Walk dog' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
next_input = 'Buy milk'
local tasks = require('ft.tasks')
tasks.create()

local log_now = table.concat(log_lines(), '\n')
ok(log_now:find('tasks create Buy milk --file inbox.md --at-line 2 --force', 1, true) ~= nil,
    'create argv: description, --file, --at-line, --force')
ok(log_now:find('--json-errors', 1, true) ~= nil, 'create argv: --json-errors')
ok(file_lines()[2] == '- [ ] Buy milk', 'create wrote the task line at line 2 on disk')
ok(buf_lines()[2] == '- [ ] Buy milk', 'buffer reloaded with the new task line')
local cur = vim.api.nvim_win_get_cursor(0)
ok(cur[1] == 2 and cur[2] == 0, 'cursor lands on the new task line ({2,0})')
ok(vim.bo[0].modified == false, 'buffer is clean after reload')

-- Pre-fill from the current line ("turn the current line into a task").
reset_state({ '# Inbox', 'Water plants', '- [ ] Buy milk' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
next_input = nil -- confirm the prefill
tasks.create()
ok(last_prompt.default == 'Water plants', 'prompt pre-filled from the current line')
ok(buf_lines()[2] == '- [ ] Water plants', 'prefilled task inserted at the cursor line')
ok(buf_lines()[3] == 'Water plants', 'original line pushed down')

-- Save-before-mutate: unsaved buffer edits reach the stub's file read.
reset_state({ '# Inbox', '', '- [ ] Buy milk' })
vim.api.nvim_buf_set_lines(0, 2, 3, false, { '- [ ] Draft text' }) -- no write
vim.api.nvim_win_set_cursor(0, { 2, 0 })
next_input = 'Draft text'
tasks.create()
ok(buf_lines()[4] == '- [ ] Draft text', 'unsaved edit was on disk when ft ran (save-before-mutate)')
ok(buf_lines()[2] == '- [ ] Draft text', 'create result reflects the saved content')

-- Inline due: token extracted, raw value passed to --due.
reset_state({ '# Inbox', '', '- [ ] Buy milk' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
next_input = 'Write report due:+2d'
tasks.create()
local log_due = table.concat(log_lines(), '\n')
ok(log_due:find('tasks create Write report --file inbox.md --at-line 2 --force --json-errors --due +2d', 1, true) ~= nil,
    'due: token stripped from description and passed as --due +2d')
ok(buf_lines()[2] == '- [ ] Write report', 'task description excludes the due token')

-- Escaped due token stays literal.
reset_state({ '# Inbox', '', '- [ ] Buy milk' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
next_input = 'Send mail \\due:tomorrow'
tasks.create()
local log_esc = table.concat(log_lines(), '\n')
ok(log_esc:find('tasks create Send mail due:tomorrow', 1, true) ~= nil
    and log_esc:find('--due', 1, true) == nil,
    '\\due:... stays a literal description token')
ok(buf_lines()[2] == '- [ ] Send mail due:tomorrow', 'escaped token rendered literally')

-- Repeated due token aborts before any ft call.
reset_state({ '# Inbox', '', '- [ ] Buy milk' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
next_input = 'Foo due:today due:friday'
local before_count = #log_lines()
tasks.create()
ok(#log_lines() == before_count, 'repeated due: aborts without an ft call')
ok(last_notify().level == vim.log.levels.ERROR
    and last_notify().msg:find('specified twice', 1, true) ~= nil,
    'repeated due: surfaces an error notification')

-- Empty description aborts.
reset_state({ '# Inbox', '', '- [ ] Buy milk' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
next_input = ''
before_count = #log_lines()
tasks.create()
ok(#log_lines() == before_count, 'empty description aborts without an ft call')
ok(last_notify().msg:find('description is empty', 1, true) ~= nil,
    'empty description notified')

-- Prompt cancelled: nothing happens.
reset_state({ '# Inbox', '', '- [ ] Buy milk' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
next_input = false
before_count = #log_lines()
tasks.create()
ok(#log_lines() == before_count, 'cancelled prompt runs no ft command')
ok(notified[#notified] == nil, 'cancelled prompt is silent')

-- ── Done ───────────────────────────────────────────────────────────────────

reset_state({ '# Inbox', '', '- [ ] Buy milk', '- [ ] Walk dog' })
vim.api.nvim_win_set_cursor(0, { 4, 0 })
tasks.done()
local log_done = table.concat(log_lines(), '\n')
ok(log_done:find('tasks complete inbox.md:4 --yes', 1, true) ~= nil,
    'done argv: complete <file>:<line> --yes')
ok(buf_lines()[4] == '- [x] Walk dog', 'done rewrote the task line on reload')
ok(vim.api.nvim_win_get_cursor(0)[1] == 4, 'cursor stays on the completed line')

-- Already done is an info-level no-op (no reload).
reset_state({ '# Inbox', '', '- [ ] Buy milk', '- [ ] Walk dog' })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.fn.setenv('FT_STUB_MODE', 'already_done')
tasks.done()
ok(last_notify().level == vim.log.levels.INFO
    and last_notify().msg:find('is already done', 1, true) ~= nil,
    'already-done is an info notification, not an error')
ok(buf_lines()[3] == '- [ ] Buy milk', 'already-done leaves the buffer untouched')

-- Not a task: ft\'s "no tasks match selector" is a warning.
reset_state({ '# Inbox', '', '- [ ] Buy milk' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.fn.setenv('FT_STUB_MODE', 'no_match')
tasks.done()
ok(last_notify().level == vim.log.levels.WARN
    and last_notify().msg:find('no tasks match selector', 1, true) ~= nil,
    'non-task line surfaces a warning')

-- Other ft failures are errors.
reset_state({ '# Inbox', '', '- [ ] Buy milk' })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.fn.setenv('FT_STUB_MODE', 'hard_error')
tasks.done()
ok(last_notify().level == vim.log.levels.ERROR
    and last_notify().msg:find('changed on disk', 1, true) ~= nil,
    'hard ft failure surfaces as an error')

-- ── Cancel ─────────────────────────────────────────────────────────────────

reset_state({ '# Inbox', '', '- [ ] Buy milk', '- [ ] Walk dog' })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
tasks.cancel()
local log_cancel = table.concat(log_lines(), '\n')
ok(log_cancel:find('tasks cancel inbox.md:3 --yes', 1, true) ~= nil,
    'cancel argv: cancel <file>:<line> --yes')
ok(buf_lines()[3] == '- [-] Buy milk', 'cancel rewrote the task line on reload')

-- Already-cancelled: ft\'s CLI already exits 0 — success, no error.
reset_state({ '# Inbox', '', '- [-] Buy milk' })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
local notified_before = #notified
tasks.cancel()
ok(#notified == notified_before, 'already-cancelled produces no error notification')
ok(buf_lines()[3] == '- [-] Buy milk', 'already-cancelled leaves the line untouched')

-- ── Undo history survives a mutation ───────────────────────────────────────

reset_state({ '# Inbox', '', '- [ ] Buy milk', '- [ ] Walk dog' })
-- Start from a fresh undo history: earlier scenarios share the buffer's
-- tree, so a wipe isolates this scenario (bwipeout drops the history).
vim.cmd('bwipeout!')
vim.cmd('edit ' .. vim.fn.fnameescape(inbox))
vim.api.nvim_buf_set_lines(0, 2, 3, false, { '- [ ] Edited' }) -- undo entry 1
-- Close the undo block so the op's reload lands in its own entry, as
-- it would across keystrokes in interactive use (see :h undo-blocks).
vim.cmd('let &g:undolevels = &g:undolevels')
vim.api.nvim_win_set_cursor(0, { 3, 0 })
tasks.done()
ok(buf_lines()[3] == '- [x] Edited', 'mutation reloaded the edited content')
vim.cmd('undo')
ok(buf_lines()[3] == '- [ ] Edited', 'undo restores the pre-mutation buffer state')
vim.cmd('undo')
ok(buf_lines()[3] == '- [ ] Buy milk', 'undo history was not wiped by the reload')

-- ── Keymaps ────────────────────────────────────────────────────────────────

reset_state({ '# Inbox', '', '- [ ] Buy milk' }) -- re-opens + fires FileType

local function mapped(key)
    local m = vim.fn.maparg(key, 'n', false, true)
    return type(m) == 'table' and next(m) ~= nil
end

ok(mapped('<leader>tt'), 'default create keymap <leader>tt is set')
ok(mapped('<leader>td'), 'default done keymap <leader>td is set')
ok(mapped('<leader>tc'), 'default cancel keymap <leader>tc is set')

-- Re-setup with one keymap disabled; new buffer picks up the config.
require('ft').setup({ tasks = { keymaps = { cancel = false } } })
local other = base .. '/other.md'
vim.fn.writefile({ '# Other' }, other)
vim.cmd('edit ' .. vim.fn.fnameescape(other))
vim.cmd('setfiletype markdown')
ok(not mapped('<leader>tc'), 'disabled cancel keymap is unset after re-setup')
ok(mapped('<leader>tt') and mapped('<leader>td'), 'remaining keymaps survive re-setup')

-- ── Outside the vault / missing binary ─────────────────────────────────────

reset_state({ '# Inbox', '' })
local vault_mod = require('ft.vault')
vault_mod.reset()
vim.fn.setenv('FT_VAULT', '')
before_count = #log_lines()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
next_input = 'x'
tasks.create()
ok(#log_lines() == before_count, 'create outside a vault runs no ft command')
ok(last_notify().level == vim.log.levels.ERROR
    and last_notify().msg:find('no Obsidian vault', 1, true) ~= nil,
    'create outside a vault notifies an error')

vim.fn.setenv('FT_VAULT', base)
vault_mod.reset()
vault_mod.discover(nil)

-- Missing binary: rpc notifies; the operation must not crash.
vim.fn.setenv('FT_BIN', '')
if vim.fn.executable('ft') == 1 then
    ok(true, 'missing-binary path skipped (ft on PATH in this environment)')
else
    reset_state({ '# Inbox', '' })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    next_input = 'x'
    tasks.create()
    ok(#notified > 0 and last_notify().level == vim.log.levels.ERROR,
        'missing binary notifies without crashing')
end
vim.fn.setenv('FT_BIN', stub)

-- ── summary ─────────────────────────────────────────────────────────────────

if failures > 0 then
    print('\n' .. failures .. ' failure(s)')
    vim.cmd('cquit')
else
    print('\nall tier-2 stub tests passed')
end
