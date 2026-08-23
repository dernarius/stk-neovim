-- The file tree, as a picker rather than a panel: you open it, choose a file,
-- and it gets out of the way again. <leader>e is the way in, and both ways out
-- are below.
return {
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    lazy = false,
    keys = {
      { "<leader>e", "<cmd>NvimTreeFocus<cr>", desc = "Focus file tree" },
    },
    opts = {
      view = { width = 32 },
      renderer = { group_empty = true },
      filters = { dotfiles = false },
      git = { enable = true, ignore = false, timeout = 500 },

      -- Close on opening a file. This is checked inside the open-file action
      -- rather than being a mapping of its own, which is what makes it apply to
      -- every way of opening one -- <CR>, <C-v>, <C-x>, <C-t> -- instead of
      -- just the one that got wrapped. Expanding a directory never reaches it
      -- (folders return earlier, before anything is opened), and neither does
      -- <Tab>, which previews a file while deliberately keeping focus in the
      -- tree.
      actions = { open_file = { quit_on_open = true } },

      -- The other way out. on_attach REPLACES nvim-tree's own mappings rather
      -- than adding to them, so the defaults have to be asked for by name
      -- first, or <CR> stops opening anything.
      on_attach = function(bufnr)
        local api = require("nvim-tree.api")
        api.map.on_attach.default(bufnr)

        -- Buffer-local, so <Esc> keeps meaning <Esc> everywhere else. nowait
        -- because Neovim would otherwise sit on 'timeoutlen' waiting to see
        -- whether a longer mapping starting with <Esc> was coming.
        vim.keymap.set("n", "<Esc>", api.tree.close, {
          buffer = bufnr,
          nowait = true,
          desc = "nvim-tree: Close the tree",
        })
      end,
    },
  },
}
