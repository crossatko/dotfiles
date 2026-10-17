return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      local function apply()
        -- Palette is generated from the wallpaper: ~/.config/theme/theme.toml
        local P = dofile(vim.fn.expand("~/.config/theme/out/palette.lua"))
        require("catppuccin").setup({
          flavour = "mocha",
          color_overrides = {
            mocha = {
              rosewater = P.bright_red, flamingo = P.red, pink = P.magenta, mauve = P.accent,
              red = P.red, maroon = P.bright_red, peach = P.orange, yellow = P.yellow,
              green = P.green, teal = P.cyan, sky = P.bright_cyan, sapphire = P.blue,
              blue = P.blue, lavender = P.bright_blue,
              text = P.fg, subtext1 = P.fg_dim, subtext0 = P.fg_dim,
              overlay2 = P.fg_dim, overlay1 = P.subtle, overlay0 = P.muted, -- comments / line numbers / guides: all stay legible on near-black
              surface2 = P.surface2, surface1 = P.surface, surface0 = P.surface,
              base = P.bg, mantle = P.bg_alt, crust = P.bg,
            },
          },
          transparent_background = true,
          integrations = {
            cmp = true,
            gitsigns = true,
            nvimtree = true,
            telescope = true,
            treesitter = true,
            notify = true,
            mini = true,
          },
          custom_highlights = function(colors)
            local active_bg = colors.surface2
            local active_fg = colors.mauve

            return {
              Normal = { bg = "NONE" },
              NormalNC = { bg = "NONE" },
              NormalFloat = { bg = "NONE" },
              FloatBorder = { bg = "NONE" },
              VertSplit = { fg = colors.overlay0, bg = "NONE" },
              SignColumn = { bg = "NONE" },
              StatusLine = { bg = "NONE" },
              StatusLineNC = { fg = colors.overlay1, bg = "NONE" },
              Pmenu = { bg = "NONE" },
              PmenuSel = { fg = colors.mauve, bg = colors.surface1, bold = true },
              PmenuSbar = { bg = "NONE" },
              PmenuThumb = { bg = "NONE" },
              WinSeparator = { fg = colors.overlay0, bg = "NONE" },
              CursorLine = { bg = "NONE" },
              CursorLineNr = { fg = colors.mauve, bg = "NONE", bold = true },
              LineNr = { fg = colors.overlay1, bg = "NONE" },
              Folded = { bg = "NONE" },
              FoldColumn = { fg = colors.overlay0, bg = "NONE" },
              EndOfBuffer = { bg = "NONE" },

              BufferLineFill = { bg = "NONE" },
              BufferLineBufferSelected = { bg = active_bg, fg = active_fg, bold = true },
              BufferLineModifiedSelected = { bg = active_bg, fg = colors.peach },
              BufferLineErrorSelected = { bg = active_bg, fg = colors.red, bold = true },
              BufferLineWarningSelected = { bg = active_bg, fg = colors.yellow, bold = true },
              BufferLineInfoSelected = { bg = active_bg, fg = colors.blue, bold = true },
              BufferLineHintSelected = { bg = active_bg, fg = colors.teal, bold = true },
              BufferLineErrorDiagnosticSelected = { bg = active_bg, fg = colors.red, bold = true },
              BufferLineWarningDiagnosticSelected = { bg = active_bg, fg = colors.yellow, bold = true },
              BufferLineInfoDiagnosticSelected = { bg = active_bg, fg = colors.blue, bold = true },
              BufferLineHintDiagnosticSelected = { bg = active_bg, fg = colors.teal, bold = true },
              BufferLineSeparatorSelected = { bg = active_bg, fg = active_bg },
              BufferLineCloseButtonSelected = { bg = active_bg, fg = colors.overlay0 },
            }
          end,
        })
        require("catppuccin").compile()
        vim.cmd.colorscheme("catppuccin")
      end

      apply()
      -- Called over RPC by ~/.config/theme/theme.py so open editors follow the wallpaper live.
      _G.ThemeReload = apply
    end,
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
      transparent = true,
    },
  },
}
