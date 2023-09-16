return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = false,
    priority = 1000,
    opts = {
      --- @usage 'auto'|'main'|'moon'|'dawn'
      variant = "main",
      --- @usage 'main'|'moon'|'dawn'
      dark_variant = "main",
      groups = {
        disable_float_background = true,
        didsble_background = true,
      },
      highlight_groups = {
        TabLineFill = { bg = "none" },
        MiniIndentscopeSymbol = { fg = "iris" },
        MiniIndentscopeSymbolOff = { fg = "iris" },
        IndentBlanklineChar = { fg = "overlay" },
        IndentBlanklineSpaceChar = { fg = "overlay" },
        IndentBlanklineSpaceCharBlankline = { fg = "overlay" },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "rose-pine",
    },
  },
}
