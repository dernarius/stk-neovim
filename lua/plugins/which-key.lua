-- The cheatsheet.
--
-- Start any key sequence and pause: which-key lists every way of finishing it.
-- So the sheet is wherever your fingers already are, rather than a document you
-- have to go and open -- though <leader>? opens the whole thing on demand, and
-- :WhichKey [mode] [keys] answers a specific question.
--
-- It documents Neovim as well as this config. The `presets` below carry
-- descriptions for the built-in operators, motions, text objects, <C-w> window
-- commands and the g/z/[/] prefixes, none of which are mappings anything here
-- made. Marks, registers and spelling suggestions get listed too, by the
-- `plugins` below.
--
-- Colours come from base46: "whichkey" was removed from `excluded` in
-- lua/nvconfig.lua, which themes the keys, descriptions and group names.
return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      -- A panel across the bottom, which has room to read like a sheet.
      -- "classic" and "modern" are floats near the cursor instead.
      preset = "helix",

      -- How long a pause has to be before the sheet appears. The default is
      -- 200ms, which is eager here: every prefix is a trigger, and that
      -- includes operators like d and c and the f motion, not just <leader>.
      -- Keeping the function shape rather than writing a bare number is what
      -- leaves the mark and register lists opening instantly -- those are
      -- lists, not a keystroke you are in the middle of.
      delay = function(ctx)
        return ctx.plugin and 0 or 400
      end,

      -- Naming the prefixes this config invented. Everything else in the tree
      -- is either a mapping with its own desc or a preset above; these two are
      -- the ones that would otherwise show as a bare "+" group.
      spec = {
        { "<leader>", group = "leader" },
        { "]b", desc = "next buffer" },
        { "[b", desc = "previous buffer" },
      },
    },
    keys = {
      {
        "<leader>?",
        function()
          -- keys = "" is the root of the tree, and loop keeps the panel up as
          -- you walk into a prefix and back out, which is what makes this
          -- browsable rather than a single screenful.
          require("which-key").show({ keys = "", loop = true })
        end,
        desc = "CHEAT every keymap",
      },
      {
        "<leader>k",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "CHEAT this buffer's keymaps",
      },
    },
  },
}
