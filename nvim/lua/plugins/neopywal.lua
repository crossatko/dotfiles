return {
  "RedsXDD/neopywal.nvim",
  name = "neopywal",
  lazy = false,
  opts = {
    transparent_background = true,
    use_wallust = true,
    colorscheme_file = "~/.config/nvim/wallust.vim",
  },
  config = function(plugin, opts)
    local options = {
      transparent_background = true,
      use_wallust = true,
      colorscheme_file = "~/.cache/wal/colors-wal.vim",
    }

    local neopywal = require("neopywal")
    neopywal.setup(options)
    vim.cmd.colorscheme("neopywal")
  end,
}
