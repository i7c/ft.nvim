--- Vault discovery and ft CLI path resolution.
---
--- Tries (in order):
--- 1. `FT_VAULT` env var
--- 2. User's explicit `vault` config passed to setup()
--- 3. Walk up from the current buffer's directory (or cwd) for `.obsidian/`
---
--- The resolved vault root is cached so subsequent calls are instant.
---
--- @module ft.vault

local M = {}

-- Cache the resolved vault root.
--- @type string|nil
local cached_vault = nil

--- Check if `ft` is installed and on PATH.
--- @return boolean
function M.ft_available()
    return vim.fn.executable('ft') == 1
end

--- Build the ft command args, optionally prepending `--vault`.
--- When we know the vault root explicitly, pass it so ft doesn't
--- have to walk up on every invocation.
--- @param args string[]  e.g. `{'find', 'Apple', '--format', 'ndjson'}`
--- @return string[]
function M.ft_cmd(args)
    if not M.ft_available() then
        error(
            'ft.nvim requires the `ft` CLI tool.\n'
                .. 'Install with: cargo install --path /path/to/ft'
        )
    end

    if cached_vault then
        return vim.list_extend({ 'ft', '--vault', cached_vault }, args)
    end
    return vim.list_extend({ 'ft' }, args)
end

--- Run an ft command synchronously and return (stdout, exit_code).
--- @param args string[]
--- @return string|nil stdout  nil on errors before command execution
--- @return integer exit_code
function M.ft_run(args)
    local ok, cmd = pcall(M.ft_cmd, args)
    if not ok then
        vim.notify(cmd, vim.log.levels.ERROR)
        return nil, -1
    end

    local stdout = vim.fn.system(cmd)
    return stdout, vim.v.shell_error
end

--- Discover the vault root path.
--- Returns the cached value if already discovered.
--- @param explicit_vault string|nil  User-provided vault path from setup()
--- @return string|nil  Absolute path to vault root, or nil
function M.discover(explicit_vault)
    if cached_vault then
        return cached_vault
    end

    -- 1. FT_VAULT env var (highest precedence)
    local env_vault = vim.fn.environ()['FT_VAULT']
    if env_vault and #env_vault > 0 then
        cached_vault = env_vault
        return cached_vault
    end

    -- 2. User's explicit config
    if explicit_vault and #explicit_vault > 0 then
        cached_vault = explicit_vault
        return cached_vault
    end

    -- 3. Walk up from the current buffer's directory for .obsidian/
    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path and #buf_path > 0 then
        local dir = vim.fn.fnamemodify(buf_path, ':h')
        local found = M.walk_up_for_obsidian(dir)
        if found then
            cached_vault = found
            return cached_vault
        end
    end

    -- 4. Walk up from cwd
    local cwd = vim.fn.getcwd()
    local found = M.walk_up_for_obsidian(cwd)
    if found then
        cached_vault = found
        return cached_vault
    end

    return nil
end

--- Walk up from a directory looking for a `.obsidian/` folder.
--- @param start_dir string  Absolute path to start from
--- @return string|nil  Absolute path to the parent of .obsidian/, or nil
function M.walk_up_for_obsidian(start_dir)
    local dir = vim.fn.resolve(start_dir)
    local max_up = 20

    for _ = 1, max_up do
        local check = dir .. '/.obsidian'
        if vim.fn.isdirectory(check) == 1 then
            return dir
        end
        local parent = vim.fn.fnamemodify(dir, ':h')
        if parent == dir then
            break -- hit the root
        end
        dir = parent
    end

    return nil
end

--- Reset the cached vault (useful for testing or vault switching).
function M.reset()
    cached_vault = nil
end

--- Get the cached vault path without re-discovering.
--- @return string|nil
function M.get_vault()
    return cached_vault
end

return M
