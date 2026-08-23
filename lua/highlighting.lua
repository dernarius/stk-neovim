-- Commands for working out which highlighter is actually painting a buffer.
--
-- Treesitter and LSP semantic tokens colour the same text, and whichever has
-- the higher priority wins (see lua/plugins/treesitter.lua). When highlighting
-- looks wrong, the useful question is which of the two is producing it -- and
-- the quickest way to answer that is to switch one off and look.
--
--   :HlStatus          what is on, what could be on, and what paints the cursor
--   :HlTreesitter      toggle treesitter for this buffer (or on / off)
--   :HlLsp             toggle LSP semantic tokens for this buffer (or on / off)
--
-- Neovim also ships :Inspect (what paints the token under the cursor) and
-- :InspectTree (the parse tree). Those answer statically; these let you A/B it.
--
-- Note that turning treesitter off does NOT bring back Vim's regex syntax --
-- vim.treesitter.stop() only tears down the highlighter. If a buffer goes
-- completely grey, that is why, and `:setl syntax=ON` restores it.

local M = {}

local function resolve(arg, current)
  if arg == "on" then
    return true
  elseif arg == "off" then
    return false
  end
  return not current
end

local function ts_active(buf)
  return vim.treesitter.highlighter.active[buf] ~= nil
end

local function lsp_active(buf)
  return vim.lsp.semantic_tokens.is_enabled({ bufnr = buf })
end

--- Language this buffer's filetype maps to, and whether a parser exists for it.
---@return string|nil lang, boolean available
local function ts_language(buf)
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if not lang then
    return nil, false
  end
  return lang, vim.treesitter.language.add(lang) == true
end

function M.treesitter(arg)
  local buf = vim.api.nvim_get_current_buf()
  local want = resolve(arg, ts_active(buf))

  if want then
    local lang, available = ts_language(buf)
    if not available then
      vim.notify(
        ("no treesitter parser for filetype %q (language %s)"):format(vim.bo[buf].filetype, lang or "unresolved"),
        vim.log.levels.WARN
      )
      return
    end
    vim.treesitter.start(buf, lang)
  else
    vim.treesitter.stop(buf)
  end

  vim.notify(("treesitter highlighting %s (syntax=%q)"):format(want and "ON" or "OFF", vim.bo[buf].syntax))
end

function M.lsp(arg)
  local buf = vim.api.nvim_get_current_buf()
  local want = resolve(arg, lsp_active(buf))
  vim.lsp.semantic_tokens.enable(want, { bufnr = buf })
  vim.notify(("LSP semantic token highlighting %s"):format(want and "ON" or "OFF"))
end

function M.status()
  local buf = vim.api.nvim_get_current_buf()
  local lang, available = ts_language(buf)
  local ts_priority = vim.hl.priorities.treesitter
  local lsp_priority = vim.hl.priorities.semantic_tokens

  local lines = {
    ("filetype    %s"):format(vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "(none)"),
    ("ts language %s"):format(lang or "(filetype maps to no language)"),
    ("ts parser   %s"):format(available and "found" or "MISSING"),
    ("regex syntax %s"):format(vim.bo[buf].syntax ~= "" and vim.bo[buf].syntax or "(off)"),
    "",
    ("treesitter  %s   priority %d"):format(ts_active(buf) and "ON " or "OFF", ts_priority),
    ("lsp tokens  %s   priority %d%s"):format(
      lsp_active(buf) and "ON " or "OFF",
      lsp_priority,
      lsp_priority > ts_priority and "   <- wins where both apply" or ""
    ),
    "",
  }

  local servers = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    table.insert(
      servers,
      ("  %s  semantic tokens: %s"):format(
        client.name,
        client.server_capabilities.semanticTokensProvider and "yes" or "no"
      )
    )
  end
  table.insert(lines, "attached servers")
  table.insert(lines, #servers > 0 and table.concat(servers, "\n") or "  (none)")
  table.insert(lines, "")

  -- What is actually painting the cursor right now.
  local cursor = vim.api.nvim_win_get_cursor(0)
  local pos = vim.inspect_pos(buf, cursor[1] - 1, cursor[2])
  table.insert(lines, ("under cursor (line %d col %d)"):format(cursor[1], cursor[2]))

  local captures = {}
  for _, c in ipairs(pos.treesitter) do
    table.insert(captures, "@" .. c.capture)
  end
  table.insert(lines, ("  treesitter  %s"):format(#captures > 0 and table.concat(captures, " ") or "(nothing)"))

  local tokens = {}
  for _, s in ipairs(pos.semantic_tokens) do
    table.insert(tokens, ("%s(p%s)"):format(s.opts.hl_group, tostring(s.opts.priority)))
  end
  table.insert(lines, ("  lsp tokens  %s"):format(#tokens > 0 and table.concat(tokens, " ") or "(nothing)"))

  vim.notify(table.concat(lines, "\n"))
end

local function complete()
  return { "on", "off" }
end

function M.setup()
  local command = vim.api.nvim_create_user_command
  command("HlStatus", M.status, { desc = "Report which highlighter is painting this buffer" })
  command("HlTreesitter", function(o)
    M.treesitter(o.args ~= "" and o.args or nil)
  end, { nargs = "?", complete = complete, desc = "Toggle treesitter highlighting for this buffer" })
  command("HlLsp", function(o)
    M.lsp(o.args ~= "" and o.args or nil)
  end, { nargs = "?", complete = complete, desc = "Toggle LSP semantic token highlighting for this buffer" })
end

return M
