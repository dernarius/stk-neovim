-- Per-project settings.
--
-- Every project gets a config resolved from three layers -- the defaults in
-- project/config.lua, your machine-local project/registry.lua, and a
-- `.nvim/config.json` committed in the repo. Plugins ask for it per buffer
-- rather than being configured once at startup, so two projects open in one
-- Neovim get their own formatters, linters, language servers and executables.
--
--   :ProjectInfo     what this buffer resolved to, and why
--   :ProjectEdit     open (creating if needed) this project's .nvim/config.json
--   :ProjectReload   re-read config from disk and restart affected LSP clients
--   :ProjectTest     run the project's `test` command in a terminal
--
-- See project/config.lua for the schema and merge rules.

local M = {}

M.path = require("project.path")
M.root = require("project.root")
M.config = require("project.config")
M.bin = require("project.bin")
M.lsp = require("project.lsp")
M.indent = require("project.indent")
M.column = require("project.column")

--- Resolved config for a buffer's project.
---@param bufnr? integer
---@return table
function M.get(bufnr)
  return M.config.get(bufnr)
end

--- Formatter/linter names configured for a buffer's filetype.
---@param kind "formatters"|"linters"
---@param bufnr? integer
---@return string[]
function M.for_filetype(kind, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end
  return M.get(bufnr)[kind][vim.bo[bufnr].filetype] or {}
end

local function loaded_buffers()
  return vim.iter(vim.api.nvim_list_bufs()):filter(vim.api.nvim_buf_is_loaded):totable()
end

--- Re-read every project's config from disk.
function M.reload()
  -- Roots are collected before AND after clearing: adding a .nvim/ directory
  -- moves a buffer's root, and both the old and new one need their clients
  -- restarted.
  local roots = {}
  for _, b in ipairs(loaded_buffers()) do
    roots[M.root.get(b)] = true
  end

  M.root.clear()
  M.config.clear()
  M.bin.clear()
  M.lsp.clear()

  for _, b in ipairs(loaded_buffers()) do
    roots[M.root.get(b)] = true
  end

  M.lsp.restart(vim.tbl_keys(roots))
  vim.api.nvim_exec_autocmds("User", { pattern = "ProjectReloaded" })
end

local TEMPLATE = [[
{
  "formatters": {},
  "linters": {},
  "lsp": {},
  "bin": {},
  "test": ""
}
]]

local function edit()
  local dir = M.root.get()
  local path = vim.fs.joinpath(dir, ".nvim", "config.json")

  if not vim.uv.fs_stat(path) then
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(vim.split(vim.trim(TEMPLATE), "\n"), path)
    -- You just asked for this file, so trusting it is not a decision worth
    -- interrupting you for. Trust is on the directory, so edits keep working.
    pcall(vim.secure.trust, { action = "allow", path = vim.fs.dirname(path) })
    vim.notify(("project: created %s"):format(path))
  end

  vim.cmd.edit(vim.fn.fnameescape(path))
end

local function test()
  local bufnr = vim.api.nvim_get_current_buf()
  local cfg = M.get(bufnr)
  if not cfg.test or cfg.test == "" then
    vim.notify(
      ("project: no `test` command set for %s -- add one with :ProjectEdit"):format(cfg.root),
      vim.log.levels.WARN
    )
    return
  end

  vim.cmd.tabnew()
  vim.fn.jobstart(cfg.test, { term = true, cwd = cfg.root })
  vim.cmd.startinsert()
end

local function info()
  local bufnr = vim.api.nvim_get_current_buf()
  local cfg = M.get(bufnr)
  local ft = vim.bo[bufnr].filetype

  local lines = {
    "root      " .. cfg.root,
    "sources   " .. table.concat(cfg.sources, " -> "),
    "filetype  " .. (ft ~= "" and ft or "(none)"),
    "",
  }

  local function section(title, items)
    table.insert(lines, title)
    if #items == 0 then
      table.insert(lines, "  (none)")
    end
    for _, item in ipairs(items) do
      table.insert(lines, "  " .. item)
    end
    table.insert(lines, "")
  end

  local function with_path(names)
    return vim.tbl_map(function(name)
      local path = M.bin.find(bufnr, name)
      return path and ("%s  -> %s"):format(name, path) or name
    end, names)
  end

  section("formatters (" .. ft .. ")", with_path(M.for_filetype("formatters", bufnr)))
  section("linters (" .. ft .. ")", with_path(M.for_filetype("linters", bufnr)))

  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    -- cmd is a list for a normal server, but may be a function for an
    -- in-process one.
    local cmd = client.config.cmd
    cmd = type(cmd) == "table" and table.concat(cmd, " ") or "(in-process)"
    table.insert(clients, ("%s  %s"):format(client.name, cmd))
  end
  table.sort(clients)
  section("lsp attached", clients)

  local skipped = {}
  for name, why in pairs(M.lsp.skipped[cfg.root] or {}) do
    table.insert(skipped, ("%s  %s"):format(name, why))
  end
  table.sort(skipped)
  section("lsp skipped", skipped)

  local rule = M.indent.rule(cfg, ft)
  local limit = M.column.limit(cfg, ft)
  table.insert(lines, ("indent    %d %s"):format(rule.width, rule.style))
  table.insert(lines, "line len  " .. (limit and ("%d (marker at %d)"):format(limit, limit + 1) or "(no marker)"))
  table.insert(lines, "test      " .. (cfg.test or "(none)"))

  vim.notify(table.concat(lines, "\n"))
end

--- Create the user commands. Safe to call before any plugin has loaded --
--- nothing here depends on one.
function M.setup()
  local command = vim.api.nvim_create_user_command
  command("ProjectInfo", info, { desc = "Show the resolved config for this buffer's project" })
  command("ProjectEdit", edit, { desc = "Edit this project's .nvim/config.json" })
  command("ProjectReload", M.reload, { desc = "Re-read project configs from disk" })
  command("ProjectTest", test, { desc = "Run this project's test command" })

  M.indent.setup()
  M.column.setup()
end

return M
