-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Nvim 0.12 reports progress to the terminal as OSC 9;4 (see the `nvim.progress`
-- group in runtime/lua/vim/_core/defaults.lua). Kitty understands that sequence and
-- draws a progress bar, but zellij forwards any OSC 9 from a pane to the host
-- terminal as a kitty OSC 99 notification, so the raw payload surfaces as a desktop
-- notification titled "4;1;0" / "4;0;0" on every save. The bar cannot render through
-- zellij anyway, so stop emitting it there.
if vim.env.ZELLIJ then
  pcall(vim.api.nvim_del_augroup_by_name, "nvim.progress")
end
