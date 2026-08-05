--- ft.nvim visual-mode regression test — runs through the REAL input loop.
--- Run: `nvim --headless -u NONE -c "lua dofile('tests/quote_visual.lua')"`
--- (wired into `make test`).
---
--- `-l` script mode cannot drive visual mode through the real input
--- queue, and a visual-mode keymap callback cannot read `'<`/`'>`
--- directly (nvim commits those marks only when visual mode exits, so
--- they are still 0 while the callback runs). This test runs a real
--- headless event loop, feeds `Vj` then `gz` as typed keys, and asserts
--- the operator path applies to the selection — the regression where
--- visual gz reported `ft: invalid line range 0-0`.

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

-- Stub rpc so the range mechanics run without a real ft binary.
local rpc = require('ft.rpc')
local captured = {}
rpc.call = function(args)
    captured.argv = args
    return '> [!ft-source] "inbox.md" L1-2 @abc1234 #7f3a91\n> body\n', 0
end

-- Fixture vault + note.
local base = vim.fn.tempname() .. '.ftvis'
vim.fn.mkdir(base .. '/.obsidian', 'p')
local inbox = base .. '/inbox.md'
vim.fn.writefile({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' }, inbox)
vim.fn.setenv('FT_VAULT', base)

require('ft').setup({})
vim.cmd('edit ' .. vim.fn.fnameescape(inbox))
vim.cmd('setfiletype markdown') -- fires _setup_buffer (binds gz in both modes)

vim.defer_fn(function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_input('Vjgz') -- linewise select lines 2-3, then gz
end, 10)

vim.defer_fn(function()
    local argv = captured.argv
    ok(argv ~= nil and table.concat(argv, ' ') == 'notes quote inbox.md -l 2-3 --json-errors',
        'visual gz quotes the selection lines (2-3) via the operator')
    ok(vim.fn.getreg('"') ~= '', 'visual gz wrote the unnamed register')
    if failures > 0 then
        vim.cmd('cquit')
    else
        print('all visual-mode regression tests passed')
        vim.cmd('qa!')
    end
end, 300)
