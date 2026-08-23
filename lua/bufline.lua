local M = {}

-- Buffers are global in Neovim, but the bar along the top reads as if they
-- belong to the tab you're looking at. Left alone that means a terminal opened
-- with <Leader>t shows up in every tab's list, next to the tab numbers on the
-- right -- two different things sharing one row.
--
-- So each tab keeps its own list. A tab-scoped variable is the right home for
-- it: Neovim drops it when the tab closes, which is exactly when the list stops
-- meaning anything.
local TAB_VAR = "bufline_bufs"

---@param tab integer tabpage handle, or 0 for the current one
---@return integer[] listed buffers this tab owns, wiped entries dropped
local function owned(tab)
  local ok, list = pcall(vim.api.nvim_tabpage_get_var, tab, TAB_VAR)
  if not ok then
    return {}
  end
  local out = {}
  for _, b in ipairs(list) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
      out[#out + 1] = b
    end
  end
  return out
end

local function claim(bufnr, tab)
  if not (vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted) then
    return
  end
  local list = owned(tab)
  if vim.tbl_contains(list, bufnr) then
    return
  end
  list[#list + 1] = bufnr
  vim.api.nvim_tabpage_set_var(tab, TAB_VAR, list)
end

local function release(bufnr)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local kept = vim.tbl_filter(function(b)
      return b ~= bufnr
    end, owned(tab))
    vim.api.nvim_tabpage_set_var(tab, TAB_VAR, kept)
  end
end

--- Does this tab show `bufnr` in its bar? bufferline's custom_filter.
---@param bufnr integer
---@param tab? integer defaults to the current tab
function M.owns(bufnr, tab)
  return vim.tbl_contains(owned(tab or 0), bufnr)
end

--- Buffer to land on after `bufnr` goes away, from `tab`'s own list.
---
--- Prefers the one to the right, the way closing a tab in an editor moves you
--- to the next one. nil means the tab has nothing left to show.
local function successor(tab, bufnr)
  local list = owned(tab)
  local before
  for _, b in ipairs(list) do
    if b ~= bufnr then
      if b > bufnr then
        return b
      end
      before = b
    end
  end
  return before
end

--- Close a buffer without taking the window layout with it.
---
--- :bdelete closes every window showing the buffer, which collapses splits and
--- can drop you out of the tab entirely. Pointing those windows somewhere else
--- first leaves the layout as it was. A tab left with nothing of its own does
--- get closed -- it has no buffers to show, so keeping it would leave an empty
--- bar over a buffer that belongs to some other tab.
---@param bufnr? integer defaults to the current buffer
function M.close_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- A terminal's job is still running, and nvim_buf_delete refuses to take the
  -- buffer out from under it (E89) unless forced. Nothing is lost by forcing:
  -- terminal scrollback isn't a file, and 'modified' is never set on one.
  local force = vim.bo[bufnr].buftype == "terminal"

  if not force and vim.bo[bufnr].modified then
    local name = vim.api.nvim_buf_get_name(bufnr)
    vim.notify(
      ("%s has unsaved changes"):format(name ~= "" and vim.fn.fnamemodify(name, ":t") or "buffer"),
      vim.log.levels.WARN
    )
    return
  end

  release(bufnr)

  -- Repoint every window on it, tab by tab, so each one lands on a buffer that
  -- tab actually owns rather than borrowing from its neighbour.
  local stranded = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      local tab = vim.api.nvim_win_get_tabpage(win)
      local into = successor(tab, bufnr)
      if into then
        vim.api.nvim_win_set_buf(win, into)
      else
        stranded[tab] = stranded[tab] or {}
        table.insert(stranded[tab], win)
      end
    end
  end

  for tab, wins in pairs(stranded) do
    if #vim.api.nvim_list_tabpages() > 1 then
      for _, win in ipairs(wins) do
        pcall(vim.api.nvim_win_close, win, true)
      end
    else
      -- Last tab standing: keep its windows alive on a fresh scratch buffer.
      local scratch = vim.api.nvim_create_buf(true, false)
      claim(scratch, tab)
      for _, win in ipairs(wins) do
        vim.api.nvim_win_set_buf(win, scratch)
      end
    end
  end

  local ok, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = force })
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

local group = vim.api.nvim_create_augroup("BuflineTabScope", { clear = true })

-- BufAdd catches a buffer the moment it joins the list, BufWinEnter catches one
-- that already existed being pulled into a second tab. Both fire with the
-- owning tab current, including for :term.
vim.api.nvim_create_autocmd({ "BufAdd", "BufWinEnter" }, {
  group = group,
  callback = function(ev)
    claim(ev.buf, 0)
  end,
})

vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
  group = group,
  callback = function(ev)
    release(ev.buf)
  end,
})

-- Buffers already on screen when this module loads never fired the events above.
for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    claim(vim.api.nvim_win_get_buf(win), tab)
  end
end

-- Buffer tabs. Note that <Tab> and <C-i> are the same byte in most terminals,
-- so mapping it here costs you jumplist-forward unless your terminal speaks the
-- kitty keyboard protocol. NvChad makes the same trade; ]b and [b are bound too
-- if you'd rather take those and drop these.
vim.keymap.set("n", "<Tab>", "<cmd>BufferLineCycleNext<cr>", { desc = "BUFFER next" })
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<cr>", { desc = "BUFFER previous" })
vim.keymap.set("n", "]b", "<cmd>BufferLineCycleNext<cr>", { desc = "BUFFER next" })
vim.keymap.set("n", "[b", "<cmd>BufferLineCyclePrev<cr>", { desc = "BUFFER previous" })

vim.keymap.set("n", "<Leader>x", function()
  M.close_buffer()
end, { desc = "BUFFER close" })

return M
