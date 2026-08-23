-- Project root detection.
--
-- `markers` is an ORDERED list. vim.fs.root() tries each marker in turn and
-- returns the directory of the FIRST marker it finds walking upward -- so an
-- earlier marker far above the file beats a later marker sitting right next to
-- it. The order below means:
--
--   1. an explicit `.nvim/` directory always wins,
--   2. then language/build markers, so a package inside a monorepo is its own
--      project (its own venv, its own LSP root),
--   3. then the VCS root as a last resort.

local path = require("project.path")

local M = {}

M.markers = {
  ".nvim",

  "Cargo.toml",
  "go.mod",
  "pyproject.toml",
  "setup.py",
  "package.json",

  "flake.nix",
  ".git",
  ".hg",
}

-- bufnr -> resolved root
local cache = {}

local function normalize(p)
  return path.normalize(vim.uv.fs_realpath(p) or p)
end

function M.cwd()
  return normalize(vim.uv.cwd() or ".")
end

--- Project root for a buffer.
--- Buffers without a file on disk (terminals, scratch, unnamed) fall back to cwd.
---@param bufnr? integer defaults to the current buffer
---@return string
function M.get(bufnr)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local hit = cache[bufnr]
  if hit then
    return hit
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return M.cwd()
  end

  local root
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or vim.bo[bufnr].buftype ~= "" then
    -- Not cached: cwd can change, and the buffer may yet get a name.
    return M.cwd()
  end

  root = normalize(vim.fs.root(bufnr, M.markers) or vim.fs.dirname(name))
  cache[bufnr] = root
  return root
end

--- Forget cached roots.
---@param bufnr? integer clear just this buffer, or all buffers when nil
function M.clear(bufnr)
  if bufnr then
    cache[bufnr] = nil
  else
    cache = {}
  end
end

local group = vim.api.nvim_create_augroup("ProjectRoot", { clear = true })

-- A buffer's root is derived from its name, so drop the entry whenever the name
-- can change or the buffer goes away.
vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "BufFilePost" }, {
  group = group,
  callback = function(args)
    cache[args.buf] = nil
  end,
})

return M
