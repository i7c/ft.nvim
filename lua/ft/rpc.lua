--- ft.rpc — the single transport seam to the `ft` binary.
---
--- Every plugin↔ft communication flows through this module; nothing else
--- may spawn the `ft` process (see the source-scan test in tests/run.lua
--- and the "Protocol contract" section of ARCHITECTURE.md).
---
--- Two tiers:
---   rpc.call(args)               — synchronous, for quick ops (follow,
---                                  task create at cursor, find)
---   rpc.job(args, kind, on_done) — async via jobstart, for slow ops
---                                  (gather, pulse, index rebuilds),
---                                  single-flight per kind with dirty-flag
---                                  coalescing (mirrors the TUI's GraphJob)
---
--- Bin resolution: $FT_BIN (dev builds, e.g. ../ft/target/release/ft)
--- before `ft` on PATH. When the vault root is known, every command is
--- prefixed with `--vault <root>` so ft does not re-walk the filesystem.
---
--- @module ft.rpc

local vault = require('ft.vault')

local M = {}

-- Autocommand group for async completion delivery.
local augroup = vim.api.nvim_create_augroup('ft_rpc', { clear = true })

-- Single-flight state per job kind: kind -> true while a job runs.
local in_flight = {}
-- Coalesced follow-up request per kind (only the newest request is kept,
-- so bursts collapse to at most one additional job).
local pending = {}

--- Resolve the ft binary path.
--- $FT_BIN wins (dev builds); otherwise `ft` from PATH; nil when neither.
--- @return string|nil
function M.resolve_bin()
    local from_env = vim.fn.environ()['FT_BIN']
    if from_env and #from_env > 0 then
        return from_env
    end
    if vim.fn.executable('ft') == 1 then
        return 'ft'
    end
    return nil
end

--- Build the argv for one ft invocation.
--- argv is a table so both `vim.fn.system` and `jobstart` pass it
--- directly to execvp — no shell, no quoting, no injection surface.
--- @param args string[]
--- @return string[]|nil  nil when the ft binary is unavailable
function M.build_cmd(args)
    local bin = M.resolve_bin()
    if not bin then
        return nil
    end
    local cmd = { bin }
    local root = vault.get_vault()
    if root then
        cmd[#cmd + 1] = '--vault'
        cmd[#cmd + 1] = root
    end
    for _, a in ipairs(args) do
        cmd[#cmd + 1] = a
    end
    return cmd
end

--- Run an ft command synchronously.
--- @param args string[]
--- @return string|nil stdout  nil when the binary is unavailable
--- @return integer exit_code  -1 when the binary is unavailable
function M.call(args)
    local cmd = M.build_cmd(args)
    if not cmd then
        vim.notify(
            'ft.nvim requires the `ft` CLI tool — set $FT_BIN or add it to PATH.',
            vim.log.levels.ERROR
        )
        return nil, -1
    end
    local stdout = vim.fn.system(cmd)
    return stdout, vim.v.shell_error
end

--- Run an ft command asynchronously.
---
--- Single-flight per `kind`: a request while one is in flight coalesces
--- into at most one follow-up job (the newest request wins). The result
--- is delivered two ways: to the `on_done(stdout, exit_code)` callback,
--- and as a `User ft:rpc-done` autocmd with `vim.v.event` =
--- `{ kind, stdout, exit_code }` for generic subscribers.
---
--- @param args string[]
--- @param kind string  job kind used for single-flight and the event
--- @param on_done fun(stdout: string|nil, exit_code: integer)|nil
--- @return boolean  true when a job was started (false = coalesced or
---                  binary unavailable)
function M.job(args, kind, on_done)
    kind = kind or 'default'
    if in_flight[kind] then
        -- Coalesce: keep the newest request, drop earlier ones.
        pending[kind] = { args = args, on_done = on_done }
        return false
    end

    local cmd = M.build_cmd(args)
    if not cmd then
        vim.notify(
            'ft.nvim requires the `ft` CLI tool — set $FT_BIN or add it to PATH.',
            vim.log.levels.ERROR
        )
        return false
    end

    in_flight[kind] = true
    local stdout_lines = {}
    local job_id = vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data)
            stdout_lines = data
        end,
        on_exit = function(_, exit_code)
            in_flight[kind] = false
            local stdout = table.concat(stdout_lines, '\n')
            if on_done then
                on_done(stdout, exit_code)
            end
            vim.api.nvim_exec_autocmds('User', {
                pattern = 'ft:rpc-done',
                data = { kind = kind, stdout = stdout, exit_code = exit_code },
            })
            -- Run the coalesced follow-up, if any.
            local next_req = pending[kind]
            if next_req then
                pending[kind] = nil
                M.job(next_req.args, kind, next_req.on_done)
            end
        end,
    })
    if job_id <= 0 then
        in_flight[kind] = false
        vim.notify('ft.nvim: failed to start ft job', vim.log.levels.ERROR)
        return false
    end
    return true
end

--- Parse an `ft --version` string ("ft 1.2.3", "ft 0.1.0") into
--- { major, minor, patch }. Returns nil on garbage.
--- @param v string
--- @return table|nil
function M.parse_version(v)
    if not v then
        return nil
    end
    local major, minor, patch = v:match('(%d+)%.(%d+)%.(%d+)')
    if not major then
        return nil
    end
    return { tonumber(major), tonumber(minor), tonumber(patch) }
end

--- True when version `a` is strictly older than version `b`.
--- Both are { major, minor, patch } tables from `parse_version`.
--- @param a table
--- @param b table
--- @return boolean
function M.version_lt(a, b)
    for i = 1, 3 do
        if a[i] ~= b[i] then
            return a[i] < b[i]
        end
    end
    return false
end

return M
