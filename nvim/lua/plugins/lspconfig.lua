return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "b0o/SchemaStore.nvim",
      "vrischmann/tree-sitter-templ",
      version = false, -- last release is way too old
    },
    opts = {
      -- make sure mason installs the server
      servers = {
        -- htmx = {
        --   filetypes = { "html", "htm", "php", "vue", "blade", "twig", "templ" },
        -- },
        tailwindcss = {
          filetypes = { "html", "htm", "php", "vue", "blade", "twig", "templ" },
          init_options = {
            userLanguages = {
              templ = "html",
              blade = "html",
            },
          },
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
        bashls = {
          cmd = { "bash-language-server", "start" },
          filetypes = { "sh", "bash" },
        },
        tsserver = {
          on_attach = function(client)
            -- disable formatting, since we use prettier
            client.server_capabilities.documentFormattingProvider = false
          end,
          init_options = {
            plugins = {
              {
                name = "@vue/typescript-plugin",
                location = "/usr/local/lib/node_modules/@vue/typescript-plugin",
                languages = { "javascript", "typescript", "vue" },
              },
            },
          },
          filetypes = {
            "javascript",
            "typescript",
            "vue",
          },
          ---@diagnostic disable-next-line: missing-fields
          settings = {},
        },
        volar = {
          on_attach = function(client)
            -- disable formatting, since we use prettier
            client.server_capabilities.documentFormattingProvider = false
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
            "templ",
          },
        },
      },
    },
  },
}
