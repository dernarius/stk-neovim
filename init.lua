vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.termguicolors = true

require("diagnostics")
require("highlighting").setup()

-- Before lazy: plugin configs ask the project module for their settings, so its
-- commands and defaults need to exist first. It depends on no plugins itself.
require("project").setup()

require("config.lazy")

require("bufline")

require("stk")
