-- Tab-scoped buffer lists and closing buffers, including terminals.
---@param h table tests.harness
---@param FIX string sandboxed fixtures directory
return function(h, FIX)
  local bl = require("bufline")

  -- Earlier specs left buffers and a terminal tab lying around, and the checks
  -- below count both. Start from a known-empty editor.
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! %bwipeout!")

  vim.o.columns = 120
  local function render()
    return vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 120 }).str
  end

  vim.cmd.edit(vim.fn.fnameescape(FIX .. "/indent/a.lua"))
  local b_lua = vim.api.nvim_get_current_buf()
  vim.cmd.edit(vim.fn.fnameescape(FIX .. "/indent/a.py"))
  local b_py = vim.api.nvim_get_current_buf()
  vim.cmd("tabnew")
  vim.cmd("term")
  local b_term = vim.api.nvim_get_current_buf()

  local t1, t2 = unpack(vim.api.nvim_list_tabpages())

  -- Buffers are global in Neovim; the bar is supposed to be per tab.
  local r2 = render()
  h.ok("bufline: the terminal tab lists only the terminal", not r2:match("a%.lua"), r2)
  vim.api.nvim_set_current_tabpage(t1)
  local r1 = render()
  h.ok("bufline: the file tab lists its own buffers", r1:match("a%.lua") and r1:match("a%.py"), r1)
  h.ok("bufline: and not the terminal", not r1:match("zsh") and not r1:match("bash") and not r1:match("sh"), r1)
  h.ok("bufline: tab indicators are still there", r1:match("1") and r1:match("2"), r1)

  h.ok("bufline: owns() is per tab", bl.owns(b_lua, t1) and not bl.owns(b_lua, t2))
  h.ok("bufline: the terminal belongs to its own tab", bl.owns(b_term, t2) and not bl.owns(b_term, t1))

  -- Closing keeps the window layout and lands on a neighbour.
  vim.cmd("vsplit")
  local nwin = #vim.api.nvim_tabpage_list_wins(t1)
  vim.api.nvim_set_current_buf(b_py)
  bl.close_buffer(b_py)
  h.ok("bufline: the buffer is gone", not vim.api.nvim_buf_is_valid(b_py))
  h.eq("bufline: the split survived", #vim.api.nvim_tabpage_list_wins(t1), nwin)
  h.eq("bufline: landed on the neighbour", vim.api.nvim_get_current_buf(), b_lua)

  -- A terminal's job is still running, so this needs a forced delete (E89).
  vim.api.nvim_set_current_tabpage(t2)
  bl.close_buffer(b_term)
  h.ok("bufline: a terminal really closes", not vim.api.nvim_buf_is_valid(b_term))
  h.eq("bufline: its emptied tab closes with it", #vim.api.nvim_list_tabpages(), 1)

  -- Last buffer in the last tab: a scratch buffer keeps the windows alive.
  bl.close_buffer(b_lua)
  h.ok("bufline: the last buffer is gone", not vim.api.nvim_buf_is_valid(b_lua))
  h.eq("bufline: the windows survive it", #vim.api.nvim_tabpage_list_wins(0), nwin)
  h.ok("bufline: the scratch buffer is owned", bl.owns(vim.api.nvim_get_current_buf()))

  -- Unsaved changes are still refused.
  vim.cmd.edit(vim.fn.fnameescape(FIX .. "/indent/a.lua"))
  local dirty = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(dirty, 0, 0, false, { "-- dirty" })
  bl.close_buffer(dirty)
  h.ok("bufline: a modified buffer is refused", vim.api.nvim_buf_is_valid(dirty))
  h.ok("bufline: and says so", h.noted("has unsaved changes"))
  vim.bo[dirty].modified = false
end
