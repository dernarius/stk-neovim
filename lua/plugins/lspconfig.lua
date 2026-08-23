-- nvim-lspconfig is used here purely as a source of server definitions: the
-- `lsp/<server>.lua` files it puts on the runtimepath are what vim.lsp.config
-- reads. Deciding which servers run, with which cmd and which settings, is
-- project/lsp.lua's job -- see the comment there for why vim.lsp.enable() can't
-- do it.

return {
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    dependencies = { "hrsh7th/cmp-nvim-lsp" },
    config = function()
      -- Merged into every server's config by vim.lsp.config's "*" entry.
      -- Must happen before the first server resolves, which is why it's
      -- the first thing here.
      local ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
      if ok then
        vim.lsp.config("*", { capabilities = cmp_lsp.default_capabilities() })
      end

      local project = require("project")

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("ProjectLsp", { clear = true }),
        callback = function(args)
          project.lsp.attach(args.buf)
        end,
      })

      -- Catches buffers that already exist, e.g. after :Lazy reload.
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
          project.lsp.attach(bufnr)
        end
      end
    end,
  },
}
