local M = {}

local FALLBACK = { width = 2, style = "spaces" }

--- The rule in force for a filetype: the "*" entry with the filetype's own
--- fields laid over it.
---@param cfg table resolved project config
---@param ft string
---@return { width: integer, style: "spaces"|"tabs" }
function M.rule(cfg, ft)
  local indent = cfg.indent or {}
  local rule = vim.tbl_extend("force", FALLBACK, indent["*"] or {})
  return vim.tbl_extend("force", rule, indent[ft] or {})
end

--- Set 'expandtab', 'shiftwidth', 'tabstop' and 'softtabstop' from the project
--- config.
---@param bufnr? integer
function M.apply(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Terminals, help, the file tree: nothing you indent, and their filetypes
  -- would only ever match the "*" fallback anyway.
  local bo = vim.bo[bufnr]
  if bo.buftype ~= "" then
    return
  end

  local rule = M.rule(require("project.config").get(bufnr), bo.filetype)
  local spaces = rule.style ~= "tabs"

  bo.expandtab = spaces
  bo.shiftwidth = rule.width
  bo.tabstop = rule.width
  -- With tabs, 'softtabstop' has to be 0 or <Tab> starts inserting spaces to
  -- reach the next stop, which is the one thing tabs-style is asking not to do.
  bo.softtabstop = spaces and rule.width or 0
end

--- Watch for filetypes and config reloads. Called from project.setup().
function M.setup()
  local group = vim.api.nvim_create_augroup("ProjectIndent", { clear = true })

  -- Neovim's bundled ftplugins set indentation for some filetypes and not
  -- others -- python gets 4 spaces, lua and json are left on the 8-wide tab
  -- default. This has to land after them to be the single answer rather than a
  -- suggestion, so it is registered in its own group: within one FileType
  -- event, groups fire in the order they were created, and $VIMRUNTIME's
  -- filetypeplugin group already exists by the time init.lua runs.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      M.apply(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ProjectReloaded",
    callback = function()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) then
          M.apply(b)
        end
      end
    end,
  })
end

return M
