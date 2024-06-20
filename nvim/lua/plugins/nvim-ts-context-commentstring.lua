return {
  "JoosepAlviste/nvim-ts-context-commentstring",
  depends = {
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    languages = {

      templ = {
        __default = "// %s",
        style_element = "// %s",
        style_attribute = "// %s",
        template_element = "// %s",
        template_attribute = "// %s",
        script_element = "// %s",
      },
    },
  },
}
