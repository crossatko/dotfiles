return {
  filetypes = {
    "html",
    "css",
    "blade",
    "vue",
    "svelte",
    "php",
    "scss",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "templ",
  },
  on_attach = function(client)
    client.server_capabilities.inlayHintProvider = false
  end,
}
