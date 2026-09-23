return {
  "norcalli/nvim-colorizer.lua",
  event = "BufReadPost",
  config = function()
    require("colorizer").setup({
      "*",
      css = {
        RGB = true,
        RRGGBB = true,
        names = true,
        RRGGBBAA = true,
        rgb_fn = true,
        hsl_fn = true,
        css = true,
        css_fn = true,
        mode = "background",
      },
    })
  end,
}
