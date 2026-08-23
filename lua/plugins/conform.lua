-- Formatting, resolved per project.
--
-- Two hooks, both of which hand us a bufnr -- which is what makes this correct
-- when you format a buffer belonging to a project other than the one you're
-- sitting in (:wa across two repos, say):
--
--   formatters_by_ft["*"] -- a function conform calls per format, returning the
--                            formatter names for that buffer
--   formatters[name]      -- a function conform calls when it needs a
--                            formatter's config, returning an override
--
-- Note that the obvious-looking `setmetatable({}, {__index = ...})` on
-- formatters_by_ft does NOT work: conform's setup() copies the table with
-- vim.tbl_extend, which drops metatables and never sees __index keys, so the
-- lookup silently resolves to nothing.

return {
  {
    "stevearc/conform.nvim",
    lazy = false,
    config = function()
      local project = require("project")

      local formatters = {}
      -- One override per formatter conform ships, so `bin` can repoint any
      -- of them. Each is a function, so nothing is resolved until that
      -- formatter actually runs.
      for _, path in ipairs(vim.api.nvim_get_runtime_file("lua/conform/formatters/*.lua", true)) do
        local name = vim.fn.fnamemodify(path, ":t:r")
        formatters[name] = function(bufnr)
          local ok, builtin = pcall(require, "conform.formatters." .. name)
          local command = ok and builtin.command or nil

          -- Pin by formatter name ("ruff_format") or by the executable
          -- it actually runs ("ruff").
          local resolved
          if type(command) == "string" then
            resolved = project.bin.find(bufnr, name, command)
          else
            resolved = project.bin.find(bufnr, name)
          end

          -- nil means "no opinion", and conform keeps its own config.
          if resolved then
            return { command = resolved }
          end
        end
      end

      require("conform").setup({
        formatters = formatters,
        formatters_by_ft = {
          ["*"] = function(bufnr)
            return project.for_filetype("formatters", bufnr)
          end,
        },
        default_format_opts = {
          lsp_format = "fallback",
        },
      })

      vim.api.nvim_create_autocmd("BufWritePre", {
        group = vim.api.nvim_create_augroup("ProjectFormat", { clear = true }),
        callback = function(args)
          require("conform").format({ bufnr = args.buf })
        end,
      })
    end,
  },
}
