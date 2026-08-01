--- ft.nvim unit tests. Run: `make test` (or `nvim --headless -l tests/run.lua`)
---
--- No ft binary needed. Covers:
---   1. Source-scan guard (pillar 1.1 / spec R1): no module other than
---      ft.rpc may spawn the ft process, and the removed `ft_run` /
---      `ft_cmd` helpers appear nowhere.
---   2. rpc pure functions: resolve_bin, build_cmd, parse_version,
---      version_lt.

-- nvim -l mode doesn't load user config; make the plugin loadable.
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

-- ── 1. Source-scan guard ────────────────────────────────────────────────────

local spawn_terms = { 'vim.fn.system', 'io.popen', 'jobstart' }
local removed_terms = { 'ft_run', 'ft_cmd' }

local root = vim.fn.getcwd() .. '/lua/ft'
local files = vim.fn.glob(root .. '/*.lua', false, true)
ok(#files >= 7, 'found plugin modules under lua/ft (' .. #files .. ')')

local violations = {}
for _, f in ipairs(files) do
    local name = vim.fn.fnamemodify(f, ':t')
    local content = table.concat(vim.fn.readfile(f), '\n')
    for _, term in ipairs(spawn_terms) do
        if content:find(term, 1, true) and name ~= 'rpc.lua' then
            violations[#violations + 1] = name .. ' uses ' .. term
        end
    end
    for _, term in ipairs(removed_terms) do
        if content:find(term, 1, true) then
            violations[#violations + 1] = name .. ' references removed helper ' .. term
        end
    end
end
ok(#violations == 0, 'no ft process spawns outside rpc.lua; no ft_run/ft_cmd remnants'
    .. (#violations > 0 and (' — ' .. table.concat(violations, ', ')) or ''))

-- rpc.lua must itself contain the sync spawn (sanity that the guard has teeth).
local rpc_content = table.concat(vim.fn.readfile(root .. '/rpc.lua'), '\n')
ok(rpc_content:find('vim.fn.system', 1, true) ~= nil, 'rpc.lua owns the sync spawn')

-- ── 2. rpc pure functions ───────────────────────────────────────────────────

local rpc = require('ft.rpc')
local vault = require('ft.vault')

-- resolve_bin: $FT_BIN wins, then `ft` on PATH, then nil.
vim.fn.setenv('FT_BIN', '/tmp/fake-ft-bin')
ok(rpc.resolve_bin() == '/tmp/fake-ft-bin', 'resolve_bin honors $FT_BIN')
vim.fn.setenv('FT_BIN', '')
if vim.fn.executable('ft') == 1 then
    ok(rpc.resolve_bin() == 'ft', 'resolve_bin falls back to ft on PATH')
else
    ok(rpc.resolve_bin() == nil, 'resolve_bin is nil without FT_BIN and without ft on PATH')
end
vim.fn.setenv('FT_BIN', '/tmp/fake-ft-bin')

-- build_cmd: argv is direct (no shell), --vault injected when known.
vault.reset()
vim.fn.setenv('FT_VAULT', '/tmp/fake-vault')
ok(vault.discover(nil) == '/tmp/fake-vault', 'discover reads $FT_VAULT')
local cmd = rpc.build_cmd({ 'find', 'Target', '--format', 'ndjson', '--limit', '1' })
ok(#cmd == 9, 'build_cmd length is 9 (bin, --vault, root, 6 args) — got ' .. #cmd)
ok(cmd[1] == '/tmp/fake-ft-bin', 'build_cmd[1] is the bin')
ok(cmd[2] == '--vault' and cmd[3] == '/tmp/fake-vault', 'build_cmd injects --vault <root>')
ok(cmd[4] == 'find' and cmd[7] == 'ndjson', 'build_cmd passes args through verbatim')

-- build_cmd without a vault: no --vault injection.
vault.reset()
vim.fn.setenv('FT_VAULT', '')
local cmd_novault = rpc.build_cmd({ '--version' })
ok(#cmd_novault == 2 and cmd_novault[1] == '/tmp/fake-ft-bin' and cmd_novault[2] == '--version',
    'build_cmd omits --vault when the vault is unknown')

-- parse_version / version_lt.
local v = rpc.parse_version('ft 0.1.0')
ok(v ~= nil and v[1] == 0 and v[2] == 1 and v[3] == 0, 'parse_version("ft 0.1.0") -> {0,1,0}')
local v2 = rpc.parse_version('ft 1.2.3-alpha\n')
ok(v2 ~= nil and v2[1] == 1 and v2[2] == 2 and v2[3] == 3, 'parse_version handles suffix + newline')
ok(rpc.parse_version('garbage') == nil, 'parse_version rejects garbage')
ok(rpc.parse_version(nil) == nil, 'parse_version rejects nil')
ok(not rpc.version_lt({ 0, 1, 0 }, { 0, 1, 0 }), 'version_lt is false for equal versions')
ok(rpc.version_lt({ 0, 0, 9 }, { 0, 1, 0 }), 'version_lt catches older patch')
ok(not rpc.version_lt({ 1, 0, 0 }, { 0, 9, 9 }), 'version_lt: major wins')

-- ── 3. tasks.parse_due ────────────────────────────────────────────────────

local tasks = require('ft.tasks')

local function check_parse(input, want_desc, want_due, want_err)
    local p = tasks.parse_due(input)
    ok(p.description == want_desc, 'parse_due(' .. vim.inspect(input) .. ') description')
    ok(p.due == want_due, 'parse_due(' .. vim.inspect(input) .. ') due')
    ok(p.error == want_err, 'parse_due(' .. vim.inspect(input) .. ') error')
end

-- Plain text: no token.
check_parse('Buy milk', 'Buy milk', nil, nil)
-- Relative / keyword / ISO forms pass through verbatim (ft resolves them).
check_parse('Write report due:+2d', 'Write report', '+2d', nil)
check_parse('Call dentist due:today', 'Call dentist', 'today', nil)
check_parse('Ship due:2026-05-10', 'Ship', '2026-05-10', nil)
-- Case-insensitive prefix; value verbatim.
check_parse('DUE:tomorrow urgent', 'urgent', 'tomorrow', nil)
check_parse('Foo Due:Friday', 'Foo', 'Friday', nil)
-- Backslash escape: literal description token, no due.
check_parse('Send mail \\due:tomorrow', 'Send mail due:tomorrow', nil, nil)
-- Repeated token is an error (first wins for the value).
check_parse('Foo due:today due:friday', 'Foo', 'today', '`due:` specified twice')
-- Empty value is an error.
check_parse('Foo due: bar', 'Foo bar', nil, '`due:` requires a value')
-- Token-only input leaves an empty description (caller rejects it).
check_parse('due:tomorrow', '', 'tomorrow', nil)
-- Tags stay inline; unknown colon tokens stay literal.
check_parse('buy milk #errands', 'buy milk #errands', nil, nil)
check_parse('email Bob re:invoice', 'email Bob re:invoice', nil, nil)
-- Empty / nil input.
check_parse('', '', nil, nil)
check_parse(nil, '', nil, nil)
-- Unicode description untouched.
check_parse('обзор кода due:tomorrow', 'обзор кода', 'tomorrow', nil)

-- ── 4. vault.relativize ─────────────────────────────────────────────────────

vault.reset()
vim.fn.setenv('FT_VAULT', '/tmp/fake-vault')
vault.discover(nil)
ok(vault.relativize('/tmp/fake-vault/Notes/Apple.md') == 'Notes/Apple.md',
    'relativize yields vault-relative path')
ok(vault.relativize('/tmp/fake-vault/Apple.md') == 'Apple.md',
    'relativize handles a root-level file')
ok(vault.relativize('/tmp/fake-vault') == nil, 'relativize: root itself is nil')
ok(vault.relativize('/tmp/fake-vault/') == nil, 'relativize: root with trailing slash is nil')
ok(vault.relativize('/tmp/other/Apple.md') == nil, 'relativize: outside the vault is nil')
ok(vault.relativize('/tmp/fake-vault2/Apple.md') == nil,
    'relativize: sibling prefix is not inside the vault')
ok(vault.relativize(nil) == nil, 'relativize: nil path is nil')
vault.reset()
vim.fn.setenv('FT_VAULT', '')
ok(vault.relativize('/tmp/fake-vault/Apple.md') == nil,
    'relativize: nil without a discovered vault')

-- ── summary ─────────────────────────────────────────────────────────────────

if failures > 0 then
    print('\n' .. failures .. ' failure(s)')
    vim.cmd('cquit')
else
    print('\nall unit tests passed')
end
