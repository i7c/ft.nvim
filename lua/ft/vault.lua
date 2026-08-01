--- Vault discovery.
---
--- Tries (in order):
--- 1. `FT_VAULT` env var (inherited from the ft TUI when nvim is
---    launched as $EDITOR inside one — the common case)
--- 2. User's explicit `vault` config passed to setup()
--- 3. Walk up from the current buffer's directory (or cwd) for `.obsidian/`
---
--- The resolved vault root is cached so subsequent calls are instant.
--- This module is the ONLY place vault discovery lives; it has no
--- dependencies and never spawns the `ft` binary — talk to ft through
--- `ft.rpc` instead.
---
--- @module ft.vault

local M = {}

-- Cache the resolved vault root.
--- @type string|nil
local cached_vault = nil

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

--- True when `path` is a file inside the vault root.
--- Used by cache invalidation to ignore writes outside the vault.
--- @param path string|nil  Absolute or relative path
--- @return boolean
function M.is_inside_vault(path)
    if not cached_vault or not path or #path == 0 then
        return false
    end
    local p = vim.fn.fnamemodify(path, ':p')
    local v = vim.fn.fnamemodify(cached_vault, ':p')
    if p == v then
        return true
    end
    local prefix = v .. '/'
    return p:sub(1, #prefix) == prefix
end

--- Convert an absolute path into a vault-relative path (the form
--- `ft tasks create --file` and task selectors expect). Returns nil
--- when the path is not a file inside the vault.
--- @param path string  Absolute path (or resolvable to one)
--- @return string|nil  Vault-relative path with forward slashes, or nil
function M.relativize(path)
    if not cached_vault or not path or #path == 0 then
        return nil
    end
    local p = vim.fn.fnamemodify(path, ':p'):gsub('/+$', '')
    local v = vim.fn.fnamemodify(cached_vault, ':p'):gsub('/+$', '')
    if p == v then
        return nil -- the root itself is not a file inside the vault
    end
    local prefix = v .. '/'
    if p:sub(1, #prefix) == prefix then
        return p:sub(#prefix + 1)
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
