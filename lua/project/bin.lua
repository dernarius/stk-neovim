-- Finding the executable a project actually wants.
--
-- The point of the whole per-project setup: `black` in one repo is
-- `.venv/bin/black`, in another it's whatever is on $PATH, and in a third it's
-- pinned somewhere odd. Resolution order for a name:
--
--   1. an explicit entry in the project's `bin` map
--   2. a project-local bin directory (`.venv/bin`, `node_modules/.bin`, ...)
--   3. nothing -- callers keep their own default
--
-- Callers pass every name worth trying, most specific first. A conform
-- formatter called "ruff_format" runs the `ruff` binary, so it asks for
-- ("ruff_format", "ruff"): you can pin it by either name.

local config = require("project.config")
local path = require("project.path")
local root = require("project.root")

local M = {}

-- root -> cache key -> resolved path or false
local cache = {}

local function resolve(dir, cfg, names)
  for _, name in ipairs(names) do
    local pinned = cfg.bin[name]
    if pinned then
      local p = path.resolve(dir, pinned)
      local found = path.executable(p)
      if not found then
        -- Pinning is deliberate, so a bad pin is a mistake worth saying
        -- out loud rather than quietly falling back to $PATH.
        vim.notify(("project: %s is pinned to %s, which is not executable"):format(name, p), vim.log.levels.WARN)
      end
      -- `found` carries the Windows extension when one was needed.
      return found or p
    end
  end

  for _, subdir in ipairs(cfg.bin_paths) do
    for _, name in ipairs(names) do
      local found = path.executable(path.normalize(vim.fs.joinpath(dir, subdir, name)))
      if found then
        return found
      end
    end
  end

  return nil
end

--- Look for a project-specific executable.
---@param bufnr integer|nil
---@param ... string names to try, most specific first
---@return string|nil path nil when the project has nothing to say
function M.find(bufnr, ...)
  local names = { ... }
  if #names == 0 then
    return nil
  end

  local dir = root.get(bufnr)
  local key = table.concat(names, "\0")

  local per_root = cache[dir]
  if not per_root then
    per_root = {}
    cache[dir] = per_root
  end

  local hit = per_root[key]
  if hit ~= nil then
    return hit or nil
  end

  local found = resolve(dir, config.for_root(dir), names)
  per_root[key] = found or false
  return found
end

--- Like find(), but always returns something runnable: falls back to the first
--- name, to be looked up on $PATH.
---@param bufnr integer|nil
---@param ... string
---@return string
function M.get(bufnr, ...)
  local names = { ... }
  return M.find(bufnr, ...) or names[1]
end

--- Drop cached lookups. Call this after creating a venv mid-session.
---@param dir? string
function M.clear(dir)
  if dir then
    cache[dir] = nil
  else
    cache = {}
  end
end

return M
