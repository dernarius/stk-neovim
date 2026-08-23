-- How diagnostics are shown.
--
-- Core rather than plugin config: nvim-lint and the LSP clients both publish
-- into vim.diagnostic, so this governs everything that reports a problem.
--
-- Neovim 0.11+ ships with virtual_text off and signs on, which is why an
-- unconfigured setup only ever gives you a letter in the gutter.

vim.diagnostic.config({
  -- The message, at the end of the offending line. Glyphs are NvChad's, so
  -- they render in the same terminal/font this config already assumes.
  virtual_text = {
    prefix = "■",
    spacing = 2,
    -- Name the producer only when more than one is reporting on the buffer,
    -- so lua_ls and luacheck stay distinguishable without repeating
    -- themselves on every line.
    source = "if_many",
  },

  underline = true,

  -- Errors sort above warnings on a line that has both, so the virtual text
  -- shows the worst problem rather than whichever arrived first.
  severity_sort = true,

  -- Re-linting on every keystroke means messages flicker while you're still
  -- typing the thing they're complaining about.
  update_in_insert = false,

  float = { border = "single", source = "if_many" },
})
