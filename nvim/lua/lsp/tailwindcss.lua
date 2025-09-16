return {
  filetypes = { "html", "htm", "php", "vue", "blade", "twig", "templ" },
  init_options = {
    userLanguages = {
      templ = "html",
      blade = "html",
    },
  },
  on_attach = function(client)
    client.server_capabilities.inlayHintProvider = false
  end,
}
