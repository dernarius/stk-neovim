-- Open buffers as tabs along the top, with nvim-tree given its own labelled
-- panel to the left of them.
--
-- That panel is the `offsets` entry: bufferline shifts the buffer buttons right
-- by the width of the tree window and fills the gap with a header, which is
-- what NvChad's tabufline calls its treeOffset module.
--
-- The bar carries two different things: this tab's buffers on the left, the
-- list of tabs on the right. Buffers are global in Neovim, so without a filter
-- the left half would show every buffer in every tab and the split would be
-- meaningless -- see lua/bufline.lua for who owns what.

return {
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    lazy = false,
    -- A function, not a table, so the style_preset enum can be named rather
    -- than written as the bare numbers it is underneath. lazy.nvim calls this
    -- once the plugin is on the runtimepath, which a table literal is not.
    opts = function()
      local preset = require("bufferline").style_preset
      return {
        options = {
          close_command = function(bufnr)
            require("bufline").close_buffer(bufnr)
          end,
          right_mouse_command = function(bufnr)
            require("bufline").close_buffer(bufnr)
          end,

          custom_filter = function(bufnr)
            return require("bufline").owns(bufnr)
          end,

          -- Counts on each button, fed by everything that publishes into
          -- vim.diagnostic -- so nvim-lint shows up here too, not just LSP.
          diagnostics = "nvim_lsp",
          diagnostics_indicator = function(_, _, diagnostics)
            local parts = {}
            for level, n in pairs(diagnostics) do
              table.insert(parts, ("%s%d"):format(level == "error" and "󰅙 " or "󰀦 ", n))
            end
            table.sort(parts)
            return table.concat(parts, " ")
          end,

          separator_style = "thin",
          show_buffer_close_icons = true,
          show_close_icon = false,
          show_tab_indicators = true,
          always_show_bufferline = true,

          -- The selected buffer is already marked out by its background and by
          -- the indicator bar; bolding and italicising it on top of that only
          -- makes the label harder to read. These drop both across every
          -- highlight bufferline derives, so nothing is left half-styled.
          style_preset = { preset.no_bold, preset.no_italic },
        },
      }
    end,
  },
}
