-- Per-project settings for THIS machine, keyed by absolute project root.
--
-- Same schema as .nvim/config.json (see project/config.lua), but it lives here
-- rather than in the repo -- for projects you don't own, paths that only make
-- sense on this box, and anything you'd rather not commit.
--
-- Paths are normalized and symlinks resolved before matching, so the key just
-- has to name the same directory as `:ProjectInfo` reports, not spell it the
-- same way. `~` works, as do Windows paths in any spelling -- backslashes,
-- forward slashes and drive-letter case are all normalized away, so
-- ["c:\\src\\thing"] and ["C:/src/thing"] are the same key.
--
-- This layer sits between the defaults and the repo's own .nvim/config.json --
-- so a project that ships its own config still wins. Object values merge,
-- arrays replace.

return {
  -- This config, editing itself. The portable half of the lua_ls setup lives
  -- in .nvim/config.json where it gets committed; what's left here is the part
  -- that can't be: $VIMRUNTIME is a different path on every machine, and on
  -- this one it changes with every Neovim update.
  ["~/.config/nvim"] = {
    lsp = {
      lua_ls = {
        settings = {
          Lua = {
            workspace = {
              library = { vim.env.VIMRUNTIME .. "/lua" },
            },
          },
        },
      },
    },
  },

  -- ["~/src/somebody-elses-repo"] = {
  -- 	formatters = { python = { "ruff_format", "ruff_organize_imports" } },
  -- 	linters = { python = { "ruff" } },
  -- 	lsp = { pylsp = false, ty = true },
  -- 	bin = { ruff = ".venv/bin/ruff" },
  -- 	-- `test` runs through 'shell', so keep it to something the shell on
  -- 	-- each machine you use actually understands.
  -- 	test = "pytest -q",
  -- },
}
