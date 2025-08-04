require("config.lazy")

-- force transparent background globally
vim.cmd([[
  highlight Normal guibg=NONE ctermbg=NONE
  highlight NormalNC guibg=NONE ctermbg=NONE
  highlight NeoTreeNormal guibg=NONE ctermbg=NONE
  highlight NeoTreeNormalNC guibg=NONE ctermbg=NONE
  highlight NeoTreeEndOfBuffer guibg=NONE ctermbg=NONE
  highlight EndOfBuffer guibg=NONE ctermbg=NONE
  highlight statusline guibg=NONE ctermbg=NONE
]])

-- prevent colorscheme overrides
-- vim.api.nvim_create_autocmd("ColorScheme", {
--   pattern = "*",
--   callback = function()
--     vim.cmd([[
--       highlight Normal guibg=NONE ctermbg=NONE
--       highlight NormalNC guibg=NONE ctermbg=NONE
--       highlight NeoTreeNormal guibg=NONE ctermbg=NONE
--       highlight NeoTreeNormalNC guibg=NONE ctermbg=NONE
--       highlight NeoTreeEndOfBuffer guibg=NONE ctermbg=NONE
--       highlight EndOfBuffer guibg=NONE ctermbg=NONE
--       highlight statusline guibg=NONE ctermbg=NONE
--     ]])
--   end,
-- })
