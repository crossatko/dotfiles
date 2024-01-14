-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
vim.keymap.set("n", "<A-S-j>", ":m .+1<cr>==", { desc = "Move down" })
vim.keymap.set("v", "<A-S-j>", ":m '>+1<cr>gv=gv", { desc = "Move down" })
vim.keymap.set("i", "<A-S-j>", "<Esc>:m .+1<cr>==gi", { desc = "Move down" })
vim.keymap.set("n", "<A-S-k>", ":m .-2<cr>==", { desc = "Move up" })
vim.keymap.set("v", "<A-S-k>", ":m '<-2<cr>gv=gv", { desc = "Move up" })
vim.keymap.set("i", "<A-S-k>", "<Esc>:m .-2<cr>==gi", { desc = "Move up" })
