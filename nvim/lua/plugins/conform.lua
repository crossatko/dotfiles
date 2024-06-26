return {
  "stevearc/conform.nvim",
  lazy = true,
  event = { "BufReadPre", "BufNewFile" }, -- to disable, comment this out
  opts = {
    formatters_by_ft = {
      css = { "prettierd" },
      html = { "prettierd" },
      -- go = { "gopls" },
      javascript = { "prettierd" },
      javascriptreact = { "prettierd" },
      json = { "prettierd" },
      lua = { "stylua" },
      markdown = { "prettierd" },
      php = { "pint" },
      blade = { "prettierd" },
      svelte = { "prettierd" },
      vue = { "prettierd" },
      tsx = { "prettierd" },
      jsx = { "prettierd" },
      typescript = { "prettierd" },
      yaml = { "prettierd" },
    },
  },
}
