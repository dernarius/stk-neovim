-- The line-length marker: which column it lands in per filetype, and that it
-- follows windows rather than buffers.
---@param h table tests.harness
---@param FIX string sandboxed fixtures directory
return function(h, FIX)
  local column = require("project.column")

  local function cc(file)
    vim.cmd.edit(vim.fn.fnameescape(file))
    return vim.wo.colorcolumn
  end

  -- ---- defaults ----
  -- Shares the indent fixtures: they are one-line files of assorted filetypes,
  -- which is all either suite needs of them.
  local dir = FIX .. "/indent/"

  -- name, expected 'colorcolumn'
  local cases = {
    -- The marker sits one past the limit, so 120 is drawn at 121.
    { "a.lua", "121" },
    { "a.py", "89" },
    -- Not named in the defaults, so it inherits "*" = 100.
    { "a.json", "101" },
    { "a.toml", "101" },
    -- Named as false: gofmt does not wrap, and prose has no fixed width.
    { "a.go", "" },
    { "a.md", "" },
  }
  for _, c in ipairs(cases) do
    local name, want = unpack(c)
    h.eq(("column: %s"):format(name), cc(dir .. name), want)
  end

  -- ---- windows, not buffers ----
  -- 'colorcolumn' is window-local, so every way of getting a buffer in front of
  -- you has to arrive at the same answer.
  vim.cmd.edit(vim.fn.fnameescape(dir .. "a.lua"))
  local lua_win = vim.api.nvim_get_current_win()

  vim.cmd("vsplit")
  h.eq("column: a split of the same buffer keeps the marker", vim.wo.colorcolumn, "121")

  -- Reusing a window for another filetype fires no FileType (the buffer is
  -- already typed), which is what BufWinEnter is there for.
  h.eq("column: reusing the window for go clears it", cc(dir .. "a.go"), "")
  h.eq("column: the other window is untouched", vim.wo[lua_win].colorcolumn, "121")

  vim.cmd("silent term")
  h.eq("column: terminal", vim.bo.buftype, "terminal")
  h.eq("column: a terminal gets no marker", vim.wo.colorcolumn, "")
  vim.cmd("silent! bwipeout!")
  vim.cmd("silent! only")

  -- ---- resolution ----
  h.eq("column: an unlisted filetype falls back to *", column.limit({ line_length = { ["*"] = 70 } }, "cobol"), 70)
  h.eq("column: false means no marker", column.limit({ line_length = { go = false, ["*"] = 70 } }, "go"), nil)
  h.eq("column: a config with no line_length still has a limit", column.limit({}, "lua"), 100)

  -- ---- the project layer ----
  local cols = FIX .. "/cols"
  assert(vim.secure.trust({ action = "allow", path = cols .. "/.nvim" }))
  require("project").reload()

  h.eq("column: project overrides a named filetype", cc(cols .. "/main.py"), "80")
  h.eq("column: project turns one off", cc(cols .. "/a.lua"), "")
  h.eq("column: project moves the * fallback", cc(cols .. "/a.json"), "91")
  -- The project set "*" but not markdown, and a per-filetype default outranks
  -- an inherited "*" whichever layer each came from.
  h.eq("column: a default false survives a project *", cc(cols .. "/a.md"), "")

  -- Reload has to repaint the windows already open, not just the next one.
  vim.cmd.edit(vim.fn.fnameescape(cols .. "/main.py"))
  vim.fn.writefile({ '{ "line_length": { "python": 50 } }' }, cols .. "/.nvim/config.json")
  require("project").reload()
  h.eq("column: reload repaints an open window", vim.wo.colorcolumn, "51")
end
