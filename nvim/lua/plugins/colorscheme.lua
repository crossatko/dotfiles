return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    opts = {
      highlight_groups = {
        -- Global background
        Normal = { bg = "#000000" },
        NormalNC = { bg = "#000000" },
        SignColumn = { bg = "#000000" },
        StatusLine = { bg = "#000000" },

        -- Floating/sidebar windows (dimmed)
        NormalFloat = { bg = "#000000", fg = "#6e6a86" },
        FloatBorder = { bg = "#000000", fg = "#3f3d52" },
        VertSplit = { fg = "#1a1a1a" },

        -- Neo-tree: dimmed Rosé Pine style
        NeoTreeNormal = { bg = "#000000", fg = "#6e6a86" },
        NeoTreeNormalNC = { bg = "#000000", fg = "#6e6a86" },
        NeoTreeEndOfBuffer = { bg = "#000000", fg = "#000000" },
        NeoTreeIndentMarker = { fg = "#3f3d52" },

        -- File/folder colors
        NeoTreeFileName = { fg = "#797593" },
        NeoTreeFileNameOpened = { fg = "#908caa" },
        NeoTreeDirectoryName = { fg = "#56949f" },
        NeoTreeDirectoryIcon = { fg = "#56949f" },

        -- Git status (dimmed)
        NeoTreeGitAdded = { fg = "#1f4c5c" },
        NeoTreeGitModified = { fg = "#907aa9" },
        NeoTreeGitDeleted = { fg = "#b4637a" },
        NeoTreeGitConflict = { fg = "#eb6f92" },
        NeoTreeGitIgnored = { fg = "#393552" },
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
