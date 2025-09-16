return {
  filetypes = {
    "typescript",
    "javascript",
    "typescriptreact",
    "javascriptreact",
    "vue",
  },
  on_attach = function(client)
    client.server_capabilities.inlayHintProvider = false
    client.server_capabilities.documentFormattingProvider = false
  end,
  settings = {},
}
