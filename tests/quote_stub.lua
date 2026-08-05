--- ft.nvim Tier 2 tests — protected-section quote against a stub ft binary.
--- Run: `nvim --headless -l tests/quote_stub.lua` (wired into `make test`).
---
--- The stub (a sh script) logs its argv for exact-shape assertions and
--- emits a canned callout on success or canned `--json-errors` per
--- `$FT_STUB_MODE`. No real ft binary needed — this suite pins the
--- editor glue: argv shape (rel path, `-l A-B`, `--json-errors`,
--- `--vault` injection), save-before-quote, register placement
--- (linewise, config trims, deterministic clipboard provider), operator
--- / visual / command range extraction, error classification, registers
--- untouched on failure, outside-vault and missing-binary paths.

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

local base = vim.fn.tempname() .. '.ftquote'
vim.fn.mkdir(base .. '/.obsidian', 'p')

local inbox = base .. '/inbox.md'
local clip_out = base .. '/clip.out'

-- Deterministic clipboard provider: the copy/paste scripts round-trip
-- through a file, so setreg('+') succeeds silently and reads back
-- (headless nvim has no usable system clipboard, and the default tmux
-- provider would error into the test output).
vim.fn.writefile({ '#!/bin/sh', 'cat > "' .. clip_out .. '"' }, base .. '/copy.sh')
vim.fn.writefile({ '#!/bin/sh', 'cat "' .. clip_out .. '"' }, base .. '/paste.sh')
vim.fn.setfperm(base .. '/copy.sh', 'rwx------')
vim.fn.setfperm(base .. '/paste.sh', 'rwx------')
vim.g.clipboard = {
    name = 'stub',
    copy = { ['+'] = base .. '/copy.sh', ['*'] = base .. '/copy.sh' },
    paste = { ['+'] = base .. '/paste.sh', ['*'] = base .. '/paste.sh' },
}

local stub = base .. '/ft-stub'
vim.fn.writefile({
    '#!/bin/sh',
    '# Tier 2 stub ft: log argv; canned callout / --json-errors per mode.',
    'log="${FT_STUB_LOG:?}"',
    'echo "$@" >> "$log"',
    'for a in "$@"; do',
    '  if [ "$a" = "--version" ]; then echo "ft 0.1.5"; exit 0; fi',
    'done',
    'vault=""; file=""; lines=""',
    'while [ $# -gt 0 ]; do',
    '  case "$1" in',
    '    --vault) vault="$2"; shift 2 ;;',
    '    -l) lines="$2"; shift 2 ;;',
    '    --json-errors) shift ;;',
    '    notes) shift 2 ;;',
    '    *) file="$1"; shift ;;',
    '  esac',
    'done',
    'case "${FT_STUB_MODE:-success}" in',
    '  dirty)',
    '    echo \'{"chain":["source file `\'"$file"\'` has uncommitted changes — `ft notes quote` pins to HEAD, so the file must be committed and unmodified (commit or stash first)"],"error":"source file `\'"$file"\'` has uncommitted changes — `ft notes quote` pins to HEAD, so the file must be committed and unmodified (commit or stash first)"}\' >&2',
    '    exit 1',
    '    ;;',
    '  out_of_range)',
    '    echo \'{"chain":["line range L\'"$lines"\' outside file `\'"$file"\'` (file has 3 lines)"],"error":"line range L\'"$lines"\' outside file `\'"$file"\'` (file has 3 lines)"}\' >&2',
    '    exit 1',
    '    ;;',
    '  hard_error)',
    '    echo \'{"chain":["vault is not inside a git repository — `ft notes quote` pins to HEAD and needs git history"],"error":"vault is not inside a git repository — `ft notes quote` pins to HEAD and needs git history"}\' >&2',
    '    exit 1',
    '    ;;',
    '  *)',
    '    echo "> [!ft-source] \\"$file\\" L$lines @abc1234 #7f3a91"',
    '    echo "> Quoted body line one"',
    '    echo "> Quoted body line two"',
    '    exit 0',
    '    ;;',
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

local function reset_state(content)
    vim.fn.writefile(content, inbox)
    vim.fn.delete(log)
    vim.fn.delete(clip_out)
    notified = {}
    vim.fn.setenv('FT_STUB_MODE', 'success')
    -- edit! discards any leftover buffer state between scenarios.
    vim.cmd('edit! ' .. vim.fn.fnameescape(inbox))
    -- -l mode skips filetype detection; fire the FileType event by hand
    -- so _setup_buffer (keymaps) runs like it does interactively.
    vim.cmd('setfiletype markdown')
end

-- Load the plugin (version check hits the stub; commands + keymaps wire up).
require('ft').setup({})
local quote = require('ft.quote')

local EXPECTED_CALLOUT = '> [!ft-source] "inbox.md" L1-2 @abc1234 #7f3a91\n'
    .. '> Quoted body line one\n'
    .. '> Quoted body line two\n'

-- ── argv shape + register placement ────────────────────────────────────────

reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
quote.quote_range(1, 2)

local log_now = table.concat(log_lines(), '\n')
ok(log_now:find('notes quote inbox.md -l 1-2 --json-errors', 1, true) ~= nil,
    'quote argv: notes quote <rel> -l A-B --json-errors')
ok(log_now:find('--vault ' .. base, 1, true) ~= nil, 'quote argv: --vault <root> injected')
ok(vim.fn.getreg('"') == EXPECTED_CALLOUT and vim.fn.getregtype('"') == 'V',
    'unnamed register holds the callout linewise')
ok(vim.fn.getreg('f') == EXPECTED_CALLOUT, 'named register f holds the callout')
ok(vim.fn.getreg('+') == EXPECTED_CALLOUT, 'clipboard register + holds the callout')
ok(last_notify().msg == 'ft: quoted L1-2 → ", f, +',
    'success notification lists the landed registers')

-- Single-line range.
reset_state({ 'aaa', 'bbb', 'ccc' })
vim.fn.delete(log)
quote.quote_range(3, 3)
ok(log_lines()[1]:find('-l 3-3', 1, true) ~= nil, 'single-line range becomes -l 3-3')

-- ── Save-before-quote ──────────────────────────────────────────────────────

reset_state({ 'aaa', 'bbb', 'ccc' })
vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'unsaved-bbb' }) -- no write yet
vim.api.nvim_win_set_cursor(0, { 2, 0 })
quote.quote_range(2, 2)
ok(vim.bo[0].modified == false, 'save-before-quote: buffer written to disk')
ok(vim.fn.readfile(inbox)[2] == 'unsaved-bbb', 'save-before-quote: disk holds the on-screen content')

-- ── Operator / visual / command entry points ───────────────────────────────

-- operatorfunc reads the g@ range from '[' / ']'.
reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
vim.fn.delete(log)
vim.api.nvim_buf_set_mark(0, '[', 2, 0, {})
vim.api.nvim_buf_set_mark(0, ']', 4, 0, {})
quote.operatorfunc()
ok(log_lines()[1]:find('-l 2-4', 1, true) ~= nil, 'operatorfunc quotes the motion range (2-4)')

-- Inverted marks (no-op/backward motion edge) are normalized.
vim.fn.delete(log)
vim.api.nvim_buf_set_mark(0, '[', 4, 0, {})
vim.api.nvim_buf_set_mark(0, ']', 2, 0, {})
quote.operatorfunc()
ok(log_lines()[1]:find('-l 2-4', 1, true) ~= nil, 'operatorfunc normalizes inverted marks')

-- The real operator keymap: gz + a motion, cursor lands at the range start.
reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
vim.fn.delete(log)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.cmd('normal gzap')
ok(log_lines()[1]:find('-l 1-5', 1, true) ~= nil, 'gz operator + paragraph motion quotes the range')
ok(vim.api.nvim_win_get_cursor(0)[1] == 1, 'operator leaves the cursor at the range start')

vim.fn.delete(log)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd('normal gz3j')
ok(log_lines()[1]:find('-l 2-5', 1, true) ~= nil, 'gz operator + count motion quotes N lines')

-- Visual entry: the keymap is the same operator as normal mode (`g@`
-- applies the operatorfunc to the selection). A visual callback cannot
-- read `'<`/`'>` directly — nvim commits those marks only when visual
-- mode exits — so the visual path shares the tested operatorfunc; assert
-- the keymap itself is the expr mapping that arms it.
reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
local vmap = vim.fn.maparg('gz', 'v', false, true)
ok(type(vmap) == 'table' and vmap.expr == 1, 'visual gz keymap is an expr mapping')
ok(type(vmap.callback) == 'function' and vmap.callback() == 'g@'
    and vim.o.operatorfunc == 'v:lua.ft_quote_operator',
    'visual gz callback arms operatorfunc and returns g@ (selection via operator)')

-- Scripted path (marks already committed): quote_selection reads '< '>'.
reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
vim.fn.delete(log)
vim.fn.setpos("'<", { 0, 2, 0, 0 })
vim.fn.setpos("'>", { 0, 3, 0, 0 })
quote.quote_selection()
ok(log_lines()[1]:find('-l 2-3', 1, true) ~= nil,
    'quote_selection quotes the committed visual span (2-3)')

-- :FtQuote — current line in normal mode, explicit ranges work.
reset_state({ 'aaa', 'bbb', 'ccc' })
vim.fn.delete(log)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd('FtQuote')
ok(log_lines()[1]:find('-l 2-2', 1, true) ~= nil, ':FtQuote in normal mode quotes the current line')
vim.fn.delete(log)
vim.cmd('1,3FtQuote')
ok(log_lines()[1]:find('-l 1-3', 1, true) ~= nil, ':FtQuote with an explicit range quotes it')

-- ── Register config trims ──────────────────────────────────────────────────

reset_state({ 'aaa', 'bbb' })
quote.setup({ registers = { unnamed = true, named = false, clipboard = true } })
vim.fn.setreg('f', 'stale-f', 'l')
vim.fn.delete(log)
quote.quote_range(1, 2)
ok(vim.fn.getreg('f') == 'stale-f\n', 'named register skipped when disabled')
ok(vim.fn.getreg('"') ~= '' and vim.fn.getreg('+') ~= '', 'enabled registers still set')
ok(last_notify().msg == 'ft: quoted L1-2 → ", +', 'notification lists only enabled registers')

-- ── Error classification ───────────────────────────────────────────────────

-- Dirty source: WARN with ft's message + commit/stash hint, registers untouched.
reset_state({ 'aaa', 'bbb', 'ccc' })
vim.fn.setenv('FT_STUB_MODE', 'dirty')
vim.fn.setreg('"', 'keep-me', 'l')
vim.fn.delete(log)
quote.quote_range(1, 2)
ok(last_notify().level == vim.log.levels.WARN, 'dirty source classifies as WARN')
ok(last_notify().msg:find('has uncommitted changes', 1, true) ~= nil,
    'dirty WARN carries ft\'s message')
ok(last_notify().msg:find('commit or stash', 1, true) ~= nil,
    'dirty WARN carries the commit/stash hint')
ok(vim.fn.getreg('"') == 'keep-me\n', 'failed quote leaves the registers untouched')

-- Out-of-bounds range: WARN.
vim.fn.setenv('FT_STUB_MODE', 'out_of_range')
vim.fn.delete(log)
quote.quote_range(9, 10)
ok(last_notify().level == vim.log.levels.WARN
    and last_notify().msg:find('outside file', 1, true) ~= nil,
    'out-of-range classifies as WARN with ft\'s message')

-- Everything else: ERROR.
vim.fn.setenv('FT_STUB_MODE', 'hard_error')
vim.fn.delete(log)
quote.quote_range(1, 2)
ok(last_notify().level == vim.log.levels.ERROR
    and last_notify().msg:find('not inside a git repository', 1, true) ~= nil,
    'other failures classify as ERROR')

-- ── Outside a vault / missing binary ───────────────────────────────────────

local vault_mod = require('ft.vault')
vim.fn.setenv('FT_VAULT', '/nonexistent')
vault_mod.reset()
vim.fn.delete(log)
quote.quote_range(1, 2)
ok(last_notify().level == vim.log.levels.ERROR and #log_lines() == 0,
    'outside a vault aborts before any ft call')
vim.fn.setenv('FT_VAULT', base)
vault_mod.reset()
vault_mod.discover(nil)

vim.fn.setenv('FT_BIN', '')
if vim.fn.executable('ft') == 1 then
    ok(true, 'missing-binary path skipped (ft on PATH in this environment)')
else
    reset_state({ 'aaa', 'bbb' })
    vim.fn.delete(log)
    quote.quote_range(1, 2)
    ok(last_notify().level == vim.log.levels.ERROR and #log_lines() == 0,
        'missing binary notifies without crashing')
end
vim.fn.setenv('FT_BIN', stub)

-- ── Keymap disable config ──────────────────────────────────────────────────

-- Re-setup with the operator keymap disabled (supported: setup can be
-- re-called). A fresh buffer gets no gz mapping; :FtQuote still works.
local ok_setup = pcall(require('ft').setup, { quote = { keymaps = { operator = false } } })
ok(ok_setup, 'setup with quote.keymaps.operator = false loads')
vim.cmd('enew')
vim.fn.writefile({ 'x', 'y' }, base .. '/fresh.md')
vim.cmd('edit! ' .. base .. '/fresh.md')
vim.cmd('setfiletype markdown')
ok(vim.fn.maparg('gz', 'n') == '' and vim.fn.maparg('gz', 'v') == '',
    'operator=false disables the gz keymaps')
vim.fn.delete(log)
vim.cmd('FtQuote')
ok(log_lines()[1]:find('-l', 1, true) ~= nil, ':FtQuote still works with keymaps disabled')

-- ── summary ─────────────────────────────────────────────────────────────────

if failures > 0 then
    print('\n' .. failures .. ' failure(s)')
    vim.cmd('cquit')
else
    print('\nall tier-2 quote stub tests passed')
end
