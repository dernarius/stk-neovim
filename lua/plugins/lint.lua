-- Linting, resolved per project.
--
-- Nothing lints by default -- `linters` in project/config.lua is empty, so this
-- stays quiet until a project asks for it:
--
--   { "linters": { "python": ["ruff"] }, "bin": { "ruff": ".venv/bin/ruff" } }

return {
  {
    "mfussenegger/nvim-lint",
    lazy = false,
    config = function()
      local project = require("project")
      local lint = require("lint")

      local function try(bufnr)
        local names = project.for_filetype("linters", bufnr)
        if #names == 0 then
          return
        end

        -- try_lint() reads the current buffer rather than taking a bufnr,
        -- so only lint when this event is about the current buffer.
        if bufnr ~= vim.api.nvim_get_current_buf() then
          return
        end

        local ok, err = pcall(lint.try_lint, names, {
          cwd = project.get(bufnr).root,
          -- Called before cmd/args are evaluated, which is exactly
          -- where the project's own executable belongs.
          wrap_linter = function(linter)
            if type(linter.cmd) == "string" then
              linter.cmd = project.bin.get(bufnr, linter.name, linter.cmd)
            end
            return linter
          end,
        })

        -- Most likely a linter name that doesn't exist; say so once
        -- rather than throwing on every save.
        if not ok then
          vim.notify(("project: lint failed -- %s"):format(err), vim.log.levels.WARN)
        end
      end

      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("ProjectLint", { clear = true }),
        callback = function(args)
          try(args.buf)
        end,
      })
    end,
  },
}
