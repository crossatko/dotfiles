local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
parser_config.blade = {
  install_info = {
    url = "https://github.com/EmranMR/tree-sitter-blade",
    files = { "src/parser.c" },
    branch = "main",
  },
  filetype = "blade",
}

local bladeGrp
vim.api.nvim_create_augroup("BladeFiltypeRelated", { clear = true })
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  pattern = "*.blade.php",
  group = bladeGrp,
  callback = function()
    vim.opt.filetype = "blade"
  end,
})

return {
  "nvim-treesitter/nvim-treesitter",
  dependencies = {
    "nvim-treesitter/nvim-treesitter-context",
    -- "windwp/nvim-ts-autotag",
    "EmranMR/tree-sitter-blade",
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
      "blade",
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
    -- autotag = {
    --   enable = true,
    --   enable_rename = true,
    --   enable_close = true,
    --   enable_close_on_slash = true,
    -- },
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = { "markdown" },
    },
  },
}
