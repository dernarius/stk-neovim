local map = vim.keymap.set

vim.opt.nu = true
vim.opt.signcolumn = "no"

map("n", ";", ":", { desc = "CMD enter command mode" })

map("n", "<Leader>t", function()
  vim.cmd("tabnew")
  vim.cmd("term")
end, { desc = "TERM open terminal" })

map("t", "<C-x>", "<C-\\><C-n>", { desc = "TERM exit terminal mode" })
