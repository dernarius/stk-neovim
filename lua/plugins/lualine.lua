-- One statusline for the whole editor rather than one per window.
--
-- Neovim's default is laststatus=2, which puts a statusline under every window.
-- Open the file tree and you have two of them, and the one under your cursor
-- swaps between the active and inactive rendering as focus moves. globalstatus
-- draws a single line across the bottom instead; lualine sets laststatus=3
-- itself to match, so there is nothing to set here by hand.
--
-- That settles where the line is, but not what it says. Focusing the tree would
-- still redraw the one line as `NvimTree_1 [-]`, filetype NvimTree. ignore_focus
-- tells lualine not to treat those windows as the current one, so the line goes
-- on describing the file you were actually editing.
return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  opts = {
    options = {
      globalstatus = true,
      ignore_focus = { "NvimTree" },
    },
  },
}
