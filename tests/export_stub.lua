--- ft.nvim Tier 2 tests — clean-CommonMark export against a stub ft binary.
--- Run: `nvim --headless -l tests/export_stub.lua` (wired into `make test`).
---
--- The stub (a sh script) logs its argv for exact-shape assertions and
--- emits canned exported markdown on success, canned `--json-errors` per
--- `$FT_STUB_MODE`, or empty stdout for the legal-empty-export case. No
--- real ft binary needed — this suite pins the editor glue: argv shape
--- (rel path, `-l A-B` optional, `--json-errors`, `--vault` injection),
--- save-before-export, whole-file default (`:FtExport` no range), register
--- placement (linewise, config trims, deterministic clipboard provider),
--- operator / visual / command range extraction, empty-output policy
--- (INFO + registers untouched), error classification, outside-vault and
--- missing-binary paths.

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

local base = vim.fn.tempname() .. '.ftexport'
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
    '# Tier 2 stub ft: log argv; canned export / --json-errors per mode.',
    'log="${FT_STUB_LOG:?}"',
    'echo "$@" >> "$log"',
    'for a in "$@"; do',
    '  if [ "$a" = "--version" ]; then echo "ft 0.1.5"; exit 0; fi',
    'done',
    'vault=""; file=""; lines=""; format=""',
    'while [ $# -gt 0 ]; do',
    '  case "$1" in',
    '    --vault) vault="$2"; shift 2 ;;',
    '    -l) lines="$2"; shift 2 ;;',
    '    --format) format="$2"; shift 2 ;;',
    '    --json-errors) shift ;;',
    '    notes) shift 2 ;;',
    '    *) file="$1"; shift ;;',
    '  esac',
    'done',
    'case "${FT_STUB_MODE:-success}" in',
    '  empty)',
    '    exit 0',
    '    ;;',
    '  out_of_range)',
    '    echo \'{"chain":["line range L\'"$lines"\' outside file `\'"$file"\'` (file has 3 lines)"],"error":"line range L\'"$lines"\' outside file `\'"$file"\'` (file has 3 lines)"}\' >&2',
    '    exit 1',
    '    ;;',
    '  missing_file)',
    '    echo \'{"chain":["cannot read source file `\'"$file"\'`"],"error":"cannot read source file `\'"$file"\'`"}\' >&2',
    '    exit 1',
    '    ;;',
    '  *)',
    '    echo "# Clean Heading"',
    '    echo ""',
    '    echo "See bee and ![img.png](img.png) and #Anchor."',
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

-- ── Picker seam stub ──────────────────────────────────────────────────────

-- The format prompt goes through ft.picker.select → vim.ui.select. Stub
-- it deterministically: `picker_choice` = nil picks the first item
-- (commonmark), a format id picks that item, 'cancel' cancels (cb(nil)).
-- `picker_calls` counts invocations so config-skip scenarios can assert
-- no prompt happened.
local picker_choice = nil
local picker_calls = 0
vim.ui.select = function(items, _opts, cb)
    picker_calls = picker_calls + 1
    if picker_choice == 'cancel' then
        cb(nil)
        return
    end
    if picker_choice then
        for _, it in ipairs(items) do
            if it.id == picker_choice then
                cb(it)
                return
            end
        end
    end
    cb(items[1])
end

local function reset_state(content)
    vim.fn.writefile(content, inbox)
    vim.fn.delete(log)
    vim.fn.delete(clip_out)
    notified = {}
    picker_choice = nil
    picker_calls = 0
    vim.fn.setenv('FT_STUB_MODE', 'success')
    -- edit! discards any leftover buffer state between scenarios.
    vim.cmd('edit! ' .. vim.fn.fnameescape(inbox))
    -- -l mode skips filetype detection; fire the FileType event by hand
    -- so _setup_buffer (keymaps) runs like it does interactively.
    vim.cmd('setfiletype markdown')
end

-- Load the plugin (version check hits the stub; commands + keymaps wire up).
require('ft').setup({})
local export = require('ft.export')

local EXPECTED_EXPORT = '# Clean Heading\n\nSee bee and ![img.png](img.png) and #Anchor.\n'

-- ── argv shape + register placement ────────────────────────────────────────

reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
export.export_range(1, 2)

local log_now = table.concat(log_lines(), '\n')
ok(log_now:find('notes export inbox.md -l 1-2 --format commonmark --json-errors', 1, true) ~= nil,
    'export argv: notes export <rel> -l A-B --format <fmt> --json-errors')
ok(log_now:find('--vault ' .. base, 1, true) ~= nil, 'export argv: --vault <root> injected')
ok(vim.fn.getreg('"') == EXPECTED_EXPORT and vim.fn.getregtype('"') == 'V',
    'unnamed register holds the exported text linewise')
ok(vim.fn.getreg('f') == EXPECTED_EXPORT, 'named register f holds the exported text')
ok(vim.fn.getreg('+') == EXPECTED_EXPORT, 'clipboard register + holds the exported text')
ok(last_notify().msg == 'ft: exported L1-2 (commonmark) → ", f, +',
    'success notification lists the landed registers and the format')

-- Whole-file export: no -l flag; the CLI whole-file default.
reset_state({ 'aaa', 'bbb' })
vim.fn.delete(log)
export.export_whole_file()
ok(log_lines()[1]:find('notes export inbox.md --format commonmark --json-errors', 1, true) ~= nil,
    'whole-file argv omits -l')
ok(last_notify().msg == 'ft: exported whole note (commonmark) → ", f, +',
    'whole-file success notification names the whole note and the format')

-- Single-line range.
reset_state({ 'aaa', 'bbb', 'ccc' })
vim.fn.delete(log)
export.export_range(3, 3)
ok(log_lines()[1]:find('-l 3-3', 1, true) ~= nil, 'single-line range becomes -l 3-3')

-- ── Save-before-export ─────────────────────────────────────────────────────

reset_state({ 'aaa', 'bbb', 'ccc' })
vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'unsaved-bbb' }) -- no write yet
vim.api.nvim_win_set_cursor(0, { 2, 0 })
export.export_range(2, 2)
ok(vim.bo[0].modified == false, 'save-before-export: buffer written to disk')
ok(vim.fn.readfile(inbox)[2] == 'unsaved-bbb', 'save-before-export: disk holds the on-screen content')

-- ── Operator / visual / command entry points ───────────────────────────────

-- operatorfunc reads the g@ range from '[' / ']'.
reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
vim.fn.delete(log)
vim.api.nvim_buf_set_mark(0, '[', 2, 0, {})
vim.api.nvim_buf_set_mark(0, ']', 4, 0, {})
export.operatorfunc()
ok(log_lines()[1]:find('-l 2-4', 1, true) ~= nil, 'operatorfunc exports the motion range (2-4)')

-- Inverted marks (no-op/backward motion edge) are normalized.
vim.fn.delete(log)
vim.api.nvim_buf_set_mark(0, '[', 4, 0, {})
vim.api.nvim_buf_set_mark(0, ']', 2, 0, {})
export.operatorfunc()
ok(log_lines()[1]:find('-l 2-4', 1, true) ~= nil, 'operatorfunc normalizes inverted marks')

-- The real operator keymap: gy + a motion, cursor lands at the range start.
reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
vim.fn.delete(log)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.cmd('normal gyap')
ok(log_lines()[1]:find('-l 1-5', 1, true) ~= nil, 'gy operator + paragraph motion exports the range')
ok(vim.api.nvim_win_get_cursor(0)[1] == 1, 'operator leaves the cursor at the range start')

vim.fn.delete(log)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd('normal gy3j')
ok(log_lines()[1]:find('-l 2-5', 1, true) ~= nil, 'gy operator + count motion exports N lines')

-- Visual entry: the keymap is the same operator as normal mode (`g@`
-- applies the operatorfunc to the selection). A visual callback cannot
-- read `'<`/`'>` directly — nvim commits those marks only when visual
-- mode exits — so the visual path shares the tested operatorfunc; assert
-- the keymap itself is the expr mapping that arms it.
reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
local vmap = vim.fn.maparg('gy', 'v', false, true)
ok(type(vmap) == 'table' and vmap.expr == 1, 'visual gy keymap is an expr mapping')
ok(type(vmap.callback) == 'function' and vmap.callback() == 'g@'
    and vim.o.operatorfunc == 'v:lua.ft_export_operator',
    'visual gy callback arms operatorfunc and returns g@ (selection via operator)')

-- Scripted path (marks already committed): export_selection reads '< '>'.
reset_state({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
vim.fn.delete(log)
vim.fn.setpos("'<", { 0, 2, 0, 0 })
vim.fn.setpos("'>", { 0, 3, 0, 0 })
export.export_selection()
ok(log_lines()[1]:find('-l 2-3', 1, true) ~= nil,
    'export_selection exports the committed visual span (2-3)')

-- :FtExport — no range exports the whole buffer; explicit ranges pass -l.
reset_state({ 'aaa', 'bbb', 'ccc' })
vim.fn.delete(log)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd('FtExport')
ok(log_lines()[1]:find('notes export inbox.md --format commonmark --json-errors', 1, true) ~= nil,
    ':FtExport with no range exports the whole buffer (no -l)')
vim.fn.delete(log)
vim.cmd('1,3FtExport')
ok(log_lines()[1]:find('-l 1-3', 1, true) ~= nil, ':FtExport with an explicit range exports it')
vim.fn.delete(log)
vim.cmd('3FtExport')
ok(log_lines()[1]:find('-l 3-3', 1, true) ~= nil, ':FtExport single-line range exports that line')

-- ── Empty output is legal: INFO + registers untouched ──────────────────────

reset_state({ 'aaa', 'bbb', 'ccc' })
vim.fn.setenv('FT_STUB_MODE', 'empty')
vim.fn.setreg('"', 'keep-me', 'l')
vim.fn.setreg('f', 'keep-f', 'l')
vim.fn.delete(log)
export.export_range(1, 2)
ok(last_notify().level == vim.log.levels.INFO, 'empty export notifies at INFO')
ok(last_notify().msg:find('empty', 1, true) ~= nil, 'empty INFO message names the empty result')
ok(vim.fn.getreg('"') == 'keep-me\n' and vim.fn.getreg('f') == 'keep-f\n',
    'empty export leaves the registers untouched')

-- ── Register config trims ──────────────────────────────────────────────────

reset_state({ 'aaa', 'bbb' })
export.setup({ registers = { unnamed = true, named = false, clipboard = true } })
vim.fn.setreg('f', 'stale-f', 'l')
vim.fn.delete(log)
export.export_range(1, 2)
ok(vim.fn.getreg('f') == 'stale-f\n', 'named register skipped when disabled')
ok(vim.fn.getreg('"') ~= '' and vim.fn.getreg('+') ~= '', 'enabled registers still set')
ok(last_notify().msg == 'ft: exported L1-2 (commonmark) → ", +', 'notification lists only enabled registers')

-- ── Format selection ───────────────────────────────────────────────────────

-- Picker choice: slack is passed as --format and named in the notification.
reset_state({ 'aaa', 'bbb' })
export.setup({ format = 'prompt', registers = { unnamed = true, named = true, clipboard = true } })
picker_choice = 'slack'
vim.fn.delete(log)
export.export_range(1, 2)
ok(log_lines()[1]:find('--format slack', 1, true) ~= nil,
    'picker choice slack → argv carries --format slack')
ok(last_notify().msg == 'ft: exported L1-2 (slack) → ", f, +',
    'success notification names the picked format')

-- Cancel: no ft call, no register write, no notification.
reset_state({ 'aaa', 'bbb' })
picker_choice = 'cancel'
vim.fn.setreg('"', 'keep-me', 'l')
vim.fn.delete(log)
export.export_range(1, 2)
ok(#log_lines() == 0, 'cancelled format prompt: no ft call runs')
ok(vim.fn.getreg('"') == 'keep-me\n', 'cancelled format prompt: registers untouched')
ok(#notified == 0, 'cancelled format prompt: no notification')

-- Whole-file export prompts too.
reset_state({ 'aaa', 'bbb' })
picker_choice = 'slack'
vim.fn.delete(log)
export.export_whole_file()
ok(log_lines()[1]:find('notes export inbox.md --format slack --json-errors', 1, true) ~= nil,
    'whole-file export prompts and passes --format')

-- Configured format skips the prompt entirely.
reset_state({ 'aaa', 'bbb' })
export.setup({ format = 'slack', registers = { unnamed = true, named = true, clipboard = true } })
vim.fn.delete(log)
export.export_range(1, 2)
ok(picker_calls == 0, 'export.format = slack: no prompt is shown')
ok(log_lines()[1]:find('--format slack', 1, true) ~= nil,
    'export.format = slack: argv carries --format slack')

-- Unknown config value behaves like 'prompt' (falls back to the picker).
reset_state({ 'aaa', 'bbb' })
export.setup({ format = 'bogus', registers = { unnamed = true, named = true, clipboard = true } })
vim.fn.delete(log)
export.export_range(1, 2)
ok(picker_calls == 1 and log_lines()[1]:find('--format commonmark', 1, true) ~= nil,
    'unknown export.format falls back to the prompt (commonmark picked)')

-- Restore the default config for the remaining scenarios.
export.setup({ format = 'prompt', registers = { unnamed = true, named = true, clipboard = true } })

-- ── Error classification ───────────────────────────────────────────────────

-- Out-of-bounds range: WARN with ft's message, registers untouched.
reset_state({ 'aaa', 'bbb', 'ccc' })
vim.fn.setenv('FT_STUB_MODE', 'out_of_range')
vim.fn.setreg('"', 'keep-me', 'l')
vim.fn.delete(log)
export.export_range(9, 10)
ok(last_notify().level == vim.log.levels.WARN
    and last_notify().msg:find('outside file', 1, true) ~= nil,
    'out-of-range classifies as WARN with ft\'s message')
ok(vim.fn.getreg('"') == 'keep-me\n', 'failed export leaves the registers untouched')

-- Missing source file: ERROR.
vim.fn.setenv('FT_STUB_MODE', 'missing_file')
vim.fn.delete(log)
export.export_range(1, 2)
ok(last_notify().level == vim.log.levels.ERROR
    and last_notify().msg:find('cannot read source file', 1, true) ~= nil,
    'missing source file classifies as ERROR')

-- ── Outside a vault / missing binary ───────────────────────────────────────

local vault_mod = require('ft.vault')
vim.fn.setenv('FT_VAULT', '/nonexistent')
vault_mod.reset()
vim.fn.delete(log)
export.export_range(1, 2)
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
    export.export_range(1, 2)
    ok(last_notify().level == vim.log.levels.ERROR and #log_lines() == 0,
        'missing binary notifies without crashing')
end
vim.fn.setenv('FT_BIN', stub)

-- ── Keymap disable config ──────────────────────────────────────────────────

-- Re-setup with the export operator keymap disabled (supported: setup can
-- be re-called). A fresh buffer gets no gy mapping; :FtExport still works.
local ok_setup = pcall(require('ft').setup, { export = { keymaps = { operator = false } } })
ok(ok_setup, 'setup with export.keymaps.operator = false loads')
vim.cmd('enew')
vim.fn.writefile({ 'x', 'y' }, base .. '/fresh.md')
vim.cmd('edit! ' .. base .. '/fresh.md')
vim.cmd('setfiletype markdown')
ok(vim.fn.maparg('gy', 'n') == '' and vim.fn.maparg('gy', 'v') == '',
    'operator=false disables the gy keymaps')
vim.fn.delete(log)
vim.cmd('FtExport')
ok(log_lines()[1]:find('notes export', 1, true) ~= nil, ':FtExport still works with keymaps disabled')

-- ── summary ─────────────────────────────────────────────────────────────────

if failures > 0 then
    print('\n' .. failures .. ' failure(s)')
    vim.cmd('cquit')
else
    print('\nall tier-2 export stub tests passed')
end
