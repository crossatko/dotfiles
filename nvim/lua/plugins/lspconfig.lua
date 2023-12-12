return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "b0o/SchemaStore.nvim",
      version = false, -- last release is way too old
    },
    opts = {
      -- make sure mason installs the server
      servers = {
        htmx = {
          filetypes = { "html", "htm", "php", "vue", "blade", "twig", "templ" },
        },
        jsonls = {
          -- lazy-load schemastore when needed
          on_new_config = function(new_config)
            new_config.settings.json.schemas = new_config.settings.json.schemas or {}
            vim.list_extend(new_config.settings.json.schemas, require("schemastore").json.schemas())
          end,
          settings = {
            json = {
              format = {
                enable = false,
              },
              validate = { enable = true },
            },
          },
        },
        tsserver = {
          on_attach = function(client)
            -- disable formatting, since we use prettier
            client.resolved_capabilities.document_formatting = false
          end,
        },
        volar = {
          on_attach = function(client)
            -- disable formatting, since we use prettier
            client.resolved_capabilities.document_formatting = false
          end,
        },
        emmet_ls = {
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
          },
        },
      },
    },
  },
}
