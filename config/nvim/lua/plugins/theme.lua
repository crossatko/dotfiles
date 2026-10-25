return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      local function apply()
        -- Palette is generated from the wallpaper: ~/.config/theme/theme.toml
        -- out/ = this machine's render (git-ignored), default/ = committed fallback
        local ok, P = pcall(dofile, vim.fn.expand("~/.config/theme/out/palette.lua"))
        if not ok then
          P = dofile(vim.fn.expand("~/.config/theme/default/palette.lua"))
        end
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
        -- light / dark mode of the theme (theme.py mode): the palette's bg is pale in light mode
        local function lum(hex)
          local c = {}
          for i = 2, 6, 2 do
            local v = tonumber(hex:sub(i, i + 1), 16) / 255
            c[#c + 1] = v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
          end
          return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
        end
        vim.o.background = lum(P.bg) > 0.4 and "light" or "dark"
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
