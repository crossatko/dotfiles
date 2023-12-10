return {
  "stevearc/conform.nvim",
  lazy = true,
  event = { "BufReadPre", "BufNewFile" }, -- to disable, comment this out
  opts = {
    formatters_by_ft = {
      css = { "prettier" },
      html = { "prettier" },
      javascript = { "prettier" },
      javascriptreact = { "prettier" },
      json = { "prettier" },
      lua = { "stylua" },
      markdown = { "prettier" },
      php = { "pint" },
      blade = { "prettier" },
      svelte = { "prettier" },
      vue = { "prettier" },
      tsx = { "prettier" },
      jsx = { "prettier" },
      typescript = { "prettier" },
      yaml = { "prettier" },
    },
  },
}
