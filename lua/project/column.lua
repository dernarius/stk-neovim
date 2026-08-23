-- The line-length marker: a stripe down the first column you are not allowed
-- to type in.
--
-- Configured as a maximum line length per filetype, because that is the number
-- the tools already state -- black's 88, stylua's column_width, pycodestyle's
-- maxLineLength. The stripe then goes one column further right, so a character
-- touching it is already one too many. `false` turns the marker off for a
-- filetype; prose and Go have no column to sit under.
local M = {}

local FALLBACK = 100

--- Maximum line length for a filetype, or nil when the marker is off.
---@param cfg table resolved project config
---@param ft string
---@return integer|nil
function M.limit(cfg, ft)
  local lengths = cfg.line_length or {}
  local limit = lengths[ft]
  if limit == nil then
    limit = lengths["*"]
  end
  if limit == nil then
    limit = FALLBACK
  end
  return limit ~= false and limit or nil
end

--- Set 'colorcolumn' for a window from its buffer's project config.
---
--- Window-local, not buffer-local, which is the whole awkwardness here: one
--- buffer shown in two splits has two independent values, and a `:split`
--- inherits whatever the window it came from had. So this is driven by the
--- events that put a buffer in a window rather than by FileType alone, and
--- non-file windows are cleared rather than skipped -- otherwise splitting a
--- code window into a terminal leaves a stripe down the terminal.
---@param win? integer
function M.apply(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(win)
  local limit
  if vim.bo[bufnr].buftype == "" then
    limit = M.limit(require("project.config").get(bufnr), vim.bo[bufnr].filetype)
  end

  vim.wo[win].colorcolumn = limit and tostring(limit + 1) or ""
end

--- Every window currently showing a buffer.
---@param bufnr integer
local function windows_showing(bufnr)
  return vim.iter(vim.api.nvim_list_wins()):filter(function(win)
    return vim.api.nvim_win_get_buf(win) == bufnr
  end)
end

--- Watch for filetypes, window changes and config reloads. Called from
--- project.setup().
function M.setup()
  local group = vim.api.nvim_create_augroup("ProjectColumn", { clear = true })

  -- FileType fires once for the buffer, whichever windows happen to hold it --
  -- :sfind and :vsplit on an unloaded file both reach here with the buffer
  -- already in more than one.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      windows_showing(ev.buf):each(M.apply)
    end,
  })

  -- And this covers the reverse: an already-typed buffer arriving in a window
  -- that was showing something else, which fires no FileType at all.
  vim.api.nvim_create_autocmd({ "BufWinEnter", "TermOpen" }, {
    group = group,
    callback = function()
      M.apply()
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ProjectReloaded",
    callback = function()
      vim.iter(vim.api.nvim_list_wins()):each(M.apply)
    end,
  })
end

return M
