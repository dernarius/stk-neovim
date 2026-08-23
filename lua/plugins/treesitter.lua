-- Treesitter highlighting.
--
-- Two things here are easy to get wrong, and the previous version got both:
--
--  * A FileType autocmd matches FILETYPES, but parsers are named after
--    LANGUAGES, and the two lists don't line up -- filetype `sh` uses the
--    `bash` parser, `typescriptreact` uses `tsx`, `gitcommit` has its own.
--    Using the parser names as autocmd patterns silently misses all of those,
--    so this matches every filetype and asks Neovim which language it maps to.
--
--  * install() is async. On a fresh checkout the parsers land after the first
--    buffers are already open, so highlighting has to be re-applied when they
--    finish rather than only on FileType.
--
-- Where a language has no parser the buffer keeps Vim's regex syntax. That's
-- the correct fallback, not a failure -- but it is also why a short `langs`
-- list looks like "treesitter isn't working": everything outside it silently
-- stays on regex highlighting, leaving LSP semantic tokens as the only thing
-- adding meaning.

local langs = {
  "bash",
  "c",
  "css",
  "diff",
  "git_config",
  "gitcommit",
  "go",
  "gomod",
  "gosum",
  "html",
  "javascript",
  "json",
  "latex",
  "lua",
  "luadoc",
  "markdown",
  "markdown_inline",
  "nix",
  "python",
  "query",
  "rust",
  "toml",
  "tsx",
  "typescript",
  "vim",
  "vimdoc",
  "yaml",
}

--- Turn on treesitter for a buffer, if its language has a parser.
local function start(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end

  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  -- add() answers "is there a parser for this anywhere on the runtimepath",
  -- which covers Neovim's bundled ones as well as the installed ones, and
  -- without assuming a library extension (.so/.dll/.dylib). It reports a
  -- missing parser rather than throwing.
  if not lang or not vim.treesitter.language.add(lang) then
    return
  end

  -- Deliberately not wrapped in pcall: a parser that exists but fails to
  -- start is a real problem and should say so instead of vanishing.
  vim.treesitter.start(buf, lang)
  vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
end

local function start_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and not vim.treesitter.highlighter.active[buf] then
      start(buf)
    end
  end
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = function()
      require("nvim-treesitter").install(langs):wait(300000)
    end,
    config = function()
      -- Treesitter and LSP semantic tokens both colour the same text, and by
      -- default the LSP wins: semantic tokens sit at priority 125 against
      -- treesitter's 100. On a Lua buffer with lua_ls attached that is every
      -- single token treesitter had an opinion about, which is what makes a
      -- working treesitter setup look like it isn't there at all.
      --
      -- Dropping the base below 100 flips it. Semantic tokens still show
      -- wherever treesitter has nothing to say, so what the server knows and
      -- the parser can't infer isn't lost. Modifiers add at most 2 to the base
      -- (@lsp.mod.* and @lsp.typemod.*), hence 95 rather than 99.
      vim.hl.priorities.semantic_tokens = 95

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("StkTreesitter", { clear = true }),
        callback = function(args)
          start(args.buf)
        end,
      })

      -- install() skips languages that are already present, so this is
      -- cheap on every start and picks up anything added to `langs` since
      -- the last :Lazy build.
      require("nvim-treesitter").install(langs):await(vim.schedule_wrap(function(err)
        if err then
          vim.notify(("treesitter: parser install failed -- %s"):format(err), vim.log.levels.WARN)
        end
        start_all()
      end))

      -- The buffer Neovim was opened with already fired its FileType event
      -- before this plugin loaded.
      start_all()
    end,
  },
}
