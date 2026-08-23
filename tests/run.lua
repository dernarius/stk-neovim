-- Entry point for the test suite. Run it with:
--
--   nvim -l tests/run.lua
--
-- which is what `:ProjectTest` does. `-l` implies --headless and hands the
-- script's exit code back to the shell -- the same invocation on Windows as on
-- Linux, with no shell script in the middle.
--
-- What `-l` does NOT do is read your config: it only puts stdpath("config") on
-- the runtimepath, so `require` finds modules while init.lua never runs and no
-- plugin is ever set up. This file therefore loads the config itself, from the
-- checkout it lives in rather than from wherever Neovim would have looked --
-- testing one tree while reading another gives results that look fine and mean
-- nothing.
--
-- Everything the suites touch is then redirected into a temp directory; see
-- harness.sandbox(). The checkout is never written to.

-- This file is <root>/tests/run.lua. `-l` may hand us a relative path.
local this = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(this)))

-- tests/ is deliberately not under lua/, so it needs saying where it is.
package.path = root .. "/?.lua;" .. package.path

-- `-l` turns 'loadplugins' off, and lazy.setup() returns immediately when it is
-- off -- silently, leaving zero plugins configured and every plugin-facing
-- check passing against nothing. Turn it back on before the config loads.
vim.go.loadplugins = true

vim.opt.runtimepath:prepend(root)
dofile(root .. "/init.lua")

local project_at =
  vim.fs.normalize(vim.fn.fnamemodify(assert(vim.api.nvim_get_runtime_file("lua/project/init.lua", false)[1]), ":p"))
if not vim.startswith(project_at, root .. "/") then
  print(("tests: loaded %s, expected it under %s"):format(project_at, root))
  vim.cmd("cq 2")
end

-- Nothing here is lazy-loaded by an event, because headless fires none of them:
-- conform waits for BufWritePre, bufferline for UIEnter. Naming them keeps that
-- explicit rather than leaving it to whichever spec happens to touch one first.
for _, plugin in ipairs({ "conform.nvim", "nvim-lint", "bufferline.nvim", "lualine.nvim" }) do
  require("lazy.core.loader").load(plugin, { cmd = "tests" })
end

local h = require("tests.harness")
local fixtures = h.sandbox(root)
h.capture_notify()

for _, name in ipairs({ "project", "schema", "indent", "column", "bufline", "style" }) do
  require("tests.specs." .. name)(h, fixtures, root)
end

h.report()
