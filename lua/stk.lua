local map = vim.keymap.set

vim.opt.nu = true
vim.opt.signcolumn = "no"

-- One clipboard, everywhere. Neovim resolves a backend per platform on first
-- use -- wl-copy/wl-paste under sway, win32yank on Windows, pbcopy/pbpaste on
-- macOS -- so there is nothing to branch on here. "unnamedplus" rather than
-- "unnamed" because `+` is the CLIPBOARD selection on Wayland, while `*` is
-- PRIMARY (middle-click) there and only an alias for `+` on the other two.
-- Needs wl-clipboard present on NixOS; the other two ship their own.
vim.opt.clipboard = "unnamedplus"

map("n", ";", ":", { desc = "CMD enter command mode" })

-- The cost of 'clipboard' above is that d, c and x all route through the
-- system clipboard, so deleting a line throws away whatever you had copied
-- from the browser. <Leader>d is the same operator aimed at the black hole
-- register: naming a register explicitly overrides 'clipboard', and `_` stores
-- nothing, so `+`, the unnamed register and the numbered registers are all
-- left alone. Operator-pending, so <Leader>dd, <Leader>dw, <Leader>dap work.
map({ "n", "x" }, "<Leader>d", '"_d', { desc = "EDIT delete without yanking" })

map("n", "<Leader>t", function()
  vim.cmd("tabnew")
  vim.cmd("term")
end, { desc = "TERM open terminal" })

map("t", "<C-x>", "<C-\\><C-n>", { desc = "TERM exit terminal mode" })
