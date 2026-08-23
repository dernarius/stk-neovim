-- base46 reads its configuration from a module called `nvconfig`, which is
-- normally supplied by the NvChad plugin. This is that module, standalone.
--
-- It is reduced to the fields base46 actually reads once the NvChad-specific
-- integrations are excluded below: everything under `base46`, plus `ui.cmp`
-- for the completion menu. `ui.statusline`, `ui.telescope` and `cheatsheet`
-- are read only by integrations we exclude, so they are deliberately absent --
-- re-enable one of those and it will tell you it wants them.

return {
  base46 = {
    -- Any of the ~97 themes in base46/lua/base46/themes/.
    theme = "everforest_light",
    theme_toggle = { "everforest_light", "everforest" },
    transparency = false,

    -- base46 always builds this set:
    --   blankline blink cmp defaults devicons git lsp mason nvcheatsheet
    --   nvimtree statusline syntax treesitter tbline telescope whichkey
    -- Excluded here are the ones for plugins this config doesn't have, plus
    -- NvChad's own UI pieces (its statusline and its tabufline) which we don't
    -- use. Deleting a name from this list is all it takes to get it back.
    excluded = {
      "blankline",
      "blink",
      "mason",
      "nvcheatsheet",
      "statusline",
      "tbline",
      "telescope",
    },

    -- Extra integrations beyond the built-in set.
    integrations = {},

    -- New groups, and overrides of base46's own. Both are merged at compile
    -- time, so they need a :Base46Compile to take effect. Colours may be named
    -- rather than written as hex: any key of the theme's base_30 or base_16
    -- table resolves at compile time, so these follow a theme change.
    hl_add = {
      -- StatusLine is defined ONLY inside base46's `statusline` integration,
      -- which is excluded above because it exists to paint NvChad's own
      -- statusline module. Excluding it left these two groups on Neovim's
      -- built-in grey, which lualine's `auto` theme then inherited for its
      -- middle section -- it reads section C's background straight off
      -- StatusLine. Defining them here fixes lualine and the native statusline
      -- together. The colours are the ones base46's statusline integration
      -- would have used.
      StatusLine = { fg = "white", bg = "statusline_bg" },
      StatusLineNC = { fg = "light_grey", bg = "darker_black" },
    },
    hl_override = {
      -- everforest_light's polish paints WhichKey (the key itself) the same
      -- white as WhichKeyDesc, which leaves the key column and its description
      -- indistinguishable -- the one distinction a cheatsheet is made of.
      -- base46's own whichkey integration uses blue for the key; this puts it
      -- back. The dark theme never overrode it, so there it changes nothing.
      WhichKey = { fg = "blue" },
    },

    -- Per-theme palette tweaks, e.g. { everforest_light = { base_30 = { ... } } }
    changed_themes = {},
  },

  ui = {
    cmp = {
      -- default | flat_light | flat_dark | atom | atom_colored
      style = "default",
    },
  },
}
