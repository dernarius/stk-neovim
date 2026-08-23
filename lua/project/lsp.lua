-- Starting language servers per project.
--
-- This deliberately does NOT use vim.lsp.enable(). enable() resolves one global
-- config per server and validates `cmd` against $PATH before it ever looks at
-- the buffer, so it cannot start `.venv/bin/pylsp` in one project and a
-- different pylsp in another -- which is the entire point here.
--
-- Instead we take nvim-lspconfig's server definition as a starting point
-- (that's all vim.lsp.config[name] is: whatever `lsp/<name>.lua` files on the
-- runtimepath declare, merged with `vim.lsp.config['*']`), layer the project's
-- overrides on top, and call vim.lsp.start() ourselves. vim.lsp.start() already
-- reuses a client when name and root_dir match, so one server per project falls
-- out for free.

local bin = require("project.bin")
local config = require("project.config")
local root = require("project.root")

local M = {}

-- Servers we declined to start, root -> server -> why. Surfaced by :ProjectInfo,
-- because "my LSP didn't start" is otherwise a silent mystery.
M.skipped = {}

-- vim.lsp.config[name] re-reads lsp/<name>.lua from disk on every access unless
-- the server was enable()d, and we never enable() anything, so cache it here.
local bases = {}

local function base_config(name)
  local hit = bases[name]
  if hit ~= nil then
    return hit or nil
  end

  local ok, base = pcall(function()
    return vim.lsp.config[name]
  end)
  if not ok or type(base) ~= "table" then
    bases[name] = false
    return nil
  end

  bases[name] = base
  return base
end

local function skip(dir, name, why)
  M.skipped[dir] = M.skipped[dir] or {}
  M.skipped[dir][name] = why
end

--- Build the config to hand vim.lsp.start(), or nil if this server shouldn't
--- start for this buffer.
---@return vim.lsp.Config|nil
local function build(name, bufnr, dir, cfg)
  local base = base_config(name)
  if not base then
    skip(dir, name, "no lsp/" .. name .. ".lua on the runtimepath")
    return nil
  end

  -- nil filetypes means "every filetype", matching vim.lsp.enable().
  local filetypes = base.filetypes
  if type(filetypes) == "table" and not vim.list_contains(filetypes, vim.bo[bufnr].filetype) then
    return nil
  end

  local overrides = cfg.lsp[name]
  if type(overrides) ~= "table" then
    overrides = {}
  end

  -- config.merge() rather than vim.tbl_deep_extend(): tbl_deep_extend merges
  -- lists index by index, so overriding a 2-element `cmd` with a 1-element one
  -- would leave the old second argument dangling.
  --
  -- The empty case is skipped deliberately: to merge(), an empty Lua table is
  -- an empty ARRAY (nothing distinguishes the two), so merging one would
  -- replace the base config rather than leave it alone. `lsp = { gopls = true }`
  -- lands here, and it means "no overrides".
  local final = next(overrides) == nil and vim.deepcopy(base) or config.merge(base, overrides)
  final.name = name
  final.root_dir = dir

  if type(final.cmd) == "table" then
    if not overrides.cmd then
      local exe = final.cmd[1]
      if type(exe) == "string" then
        local resolved = bin.find(bufnr, name, exe)
        if resolved then
          final.cmd = vim.deepcopy(final.cmd)
          final.cmd[1] = resolved
        end
      end
    end

    if vim.fn.executable(final.cmd[1]) == 0 then
      -- Not an error: you configure servers for every language you touch
      -- and only install some of them on any given machine.
      skip(dir, name, ("%s is not executable"):format(final.cmd[1]))
      return nil
    end
  elseif type(final.cmd) ~= "function" then
    -- vim.lsp.start() would throw deep inside the RPC layer.
    skip(dir, name, "config has no runnable `cmd`")
    return nil
  end

  if M.skipped[dir] then
    M.skipped[dir][name] = nil
  end
  return final
end

--- Start every server the buffer's project asks for.
---@param bufnr? integer
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  -- Same guard vim.lsp.enable() uses: real files and help buffers only.
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" and buftype ~= "help" then
    return
  end

  local dir = root.get(bufnr)
  local cfg = config.for_root(dir)

  local names = {}
  for name, enabled in pairs(cfg.lsp) do
    if enabled then
      table.insert(names, name)
    end
  end
  table.sort(names)

  for _, name in ipairs(names) do
    local final = build(name, bufnr, dir, cfg)
    if final then
      vim.lsp.start(final, { bufnr = bufnr })
    end
  end
end

--- Stop every client rooted at one of `dirs` and re-attach the affected buffers
--- with the config as it now reads. Used by :ProjectReload -- LSP settings are
--- sent once at initialize, so a restart is the only way to pick up a change.
---@param dirs string[]
function M.restart(dirs)
  local wanted = {}
  for _, dir in ipairs(dirs) do
    wanted[dir] = true
  end

  local ids = {}
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.root_dir and wanted[client.root_dir] then
      table.insert(ids, client.id)
      client:stop()
    end
  end

  -- Resolve buffers before waiting: a client that stops mid-wait must not
  -- change which buffers we come back to.
  local buffers = vim
    .iter(vim.api.nvim_list_bufs())
    :filter(function(b)
      return vim.api.nvim_buf_is_loaded(b) and wanted[root.get(b)]
    end)
    :totable()

  if #ids > 0 then
    vim.wait(2000, function()
      for _, id in ipairs(ids) do
        if vim.lsp.get_client_by_id(id) then
          return false
        end
      end
      return true
    end, 50)
  end

  for _, b in ipairs(buffers) do
    M.attach(b)
  end
end

--- Forget cached server definitions, e.g. after changing vim.lsp.config('*').
function M.clear()
  bases = {}
  M.skipped = {}
end

return M
