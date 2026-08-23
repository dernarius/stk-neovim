-- Indentation, including the two filetypes where the indent character is
-- load-bearing rather than stylistic.
---@param h table tests.harness
---@param FIX string sandboxed fixtures directory
return function(h, FIX)
  local dir = FIX .. "/indent/"

  -- name, filetype, shiftwidth, expandtab
  local cases = {
    { "a.lua", "lua", 2, true },
    { "a.json", "json", 2, true },
    { "a.toml", "toml", 2, true },
    { "a.nix", "nix", 2, true },
    { "a.md", "markdown", 2, true },
    -- Neovim's bundled ftplugin already sets these three. Ours has to land
    -- after it: python must stay 4, and make and go must stay on real tabs.
    { "a.py", "python", 4, true },
    { "Makefile", "make", 8, false },
    { "a.go", "go", 4, false },
  }

  for _, c in ipairs(cases) do
    local name, ft, width, spaces = unpack(c)
    vim.cmd.edit(vim.fn.fnameescape(dir .. name))
    h.eq(("indent: %s filetype"):format(name), vim.bo.filetype, ft)
    h.eq(("indent: %s shiftwidth"):format(name), vim.bo.shiftwidth, width)
    h.eq(("indent: %s tabstop"):format(name), vim.bo.tabstop, width)
    h.eq(("indent: %s expandtab"):format(name), vim.bo.expandtab, spaces)
    h.eq(("indent: %s softtabstop"):format(name), vim.bo.softtabstop, spaces and width or 0)
  end

  -- What actually lands in the buffer, which is the thing being complained
  -- about when this is wrong.
  local function shift(name)
    vim.cmd.edit(vim.fn.fnameescape(dir .. name))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x" })
    vim.cmd("normal! gg>>")
    return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  end
  h.eq("indent: >> in lua inserts two spaces", shift("a.lua"), "  x")
  h.eq("indent: >> in a Makefile inserts a real tab", shift("Makefile"), "\tx")

  -- Non-file buffers are left alone.
  vim.cmd("tabnew")
  vim.cmd("term")
  h.eq("indent: terminal is skipped", vim.bo.buftype, "terminal")
  vim.cmd("silent! bwipeout!")

  local indent = require("project.indent")
  h.eq(
    "indent: a rule inherits width from *",
    indent.rule({ indent = { ["*"] = { width = 2, style = "spaces" }, go = { style = "tabs" } } }, "go"),
    { width = 2, style = "tabs" }
  )
  h.eq(
    "indent: an unlisted filetype falls back to *",
    indent.rule({ indent = { ["*"] = { width = 7, style = "tabs" } } }, "cobol"),
    { width = 7, style = "tabs" }
  )
end
