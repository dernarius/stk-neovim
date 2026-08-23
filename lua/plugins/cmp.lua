return {
  {
    "hrsh7th/nvim-cmp",
    -- The `nvim_lsp` and `buffer` sources below live in separate plugins.
    dependencies = { "hrsh7th/cmp-nvim-lsp", "hrsh7th/cmp-buffer" },
    config = function()
      local options = {}

      local cmp = require("cmp")

      cmp.setup({
        -- Servers advertise snippet support (via cmp-nvim-lsp's capabilities),
        -- so something has to expand them. Neovim has this built in now.
        snippet = {
          expand = function(args)
            vim.snippet.expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            else
              fallback()
            end
          end, {
            "i",
            "s",
          }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            else
              fallback()
            end
          end, {
            "i",
            "s",
          }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "buffer" },
        }),
        preselect = cmp.PreselectMode.None,
      })

      cmp.setup.cmdline({ "/", "?" }, {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = "buffer" },
        },
      })

      -- options.completion = {
      --   completeopt = "menu,menuone,preview,noselect"
      -- }
    end,
  },
}
