return {
  "nvim-treesitter/nvim-treesitter",
  dependencies = {
    "JoosepAlviste/nvim-ts-context-commentstring",
    "nvim-treesitter/nvim-treesitter-context",
    "windwp/nvim-ts-autotag",
  },
  opts = {
    ensure_installed = {
      "php",
      "phpdoc",
      "typescript",
      "tsx",
      "json",
      "json5",
      "jsonc",
      "python",
      "rust",
      "vue",
      "sql",
      "yaml",
      "svelte",
      "javascript",
      "html",
      "css",
      "scss",
    },
    context_commentstring = {
      enable = true,
      vue = {
        style_element = "// %s",
        style_attribute = "// %s",
        template_element = "<!-- %s -->",
        template_attribute = "<!-- %s -->",
        script_element = "// %s",
      },
    },
    autotag = {
      enable = true,
      enable_rename = true,
      enable_close = true,
      enable_close_on_slash = true,
    },
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = { "markdown" },
    },
  },
}
