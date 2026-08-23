-- Colourscheme, via NvChad's theming engine without the rest of NvChad.
--
-- base46 doesn't work like a normal colourscheme. It compiles a theme into one
-- Lua chunk per "integration" (defaults, treesitter, lsp, cmp, ...) cached on
-- disk, and applying the theme means loading those chunks. That's why there's
-- no vim.cmd.colorscheme() call here.
--
-- Its only hard dependency on NvChad is a module called `nvconfig`, which this
-- config supplies itself -- see lua/nvconfig.lua. The remaining NvChad
-- references (chadrc, nvchad.utils, plenary) live inside toggle_theme() and
-- load_all_highlights(), which is why :Base46Compile below reimplements the
-- one line of those we need rather than calling them.

return {
  {
    "NvChad/base46",
    lazy = false,
    priority = 1000,
    -- Read at require() time, so it has to be set before the plugin loads.
    init = function()
      vim.g.base46_cache = vim.fn.stdpath("data") .. "/base46/"
    end,
    build = function()
      require("theme").rebuild()
    end,
    config = function()
      local compile = require("theme")

      -- The cache is a build artefact, so it's missing on a fresh checkout and
      -- after clearing stdpath("data").
      if not vim.uv.fs_stat(vim.g.base46_cache .. "defaults") then
        compile.rebuild()
      end
      compile.apply()

      -- Editing lua/nvconfig.lua changes the inputs to the compile step, not
      -- the highlights themselves, so a rebuild is needed to see it.
      vim.api.nvim_create_user_command("Base46Compile", function()
        compile.rebuild()
        compile.apply()
        vim.notify("base46: recompiled " .. require("nvconfig").base46.theme)
      end, { desc = "Rebuild the base46 highlight cache from lua/nvconfig.lua" })
    end,
  },
}
