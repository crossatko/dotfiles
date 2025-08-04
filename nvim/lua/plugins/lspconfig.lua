return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "b0o/SchemaStore.nvim",
      version = false, -- last release is way too old
    },

    opts = function(_, opts)
      table.insert(opts.servers.vtsls.filetypes, "vue")
      LazyVim.extend(opts.servers.vtsls, "settings.vtsls.tsserver.globalPlugins", {
        {
          name = "@vue/typescript-plugin",
          location = LazyVim.get_pkg_path("vue-language-server", "/node_modules/@vue/language-server"),
          languages = { "vue" },
          configNamespace = "typescript",
          enableForWorkspaceTypeScriptVersions = true,
        },

        servers = {
          tailwindcss = {
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
          volar = {},
          -- Volar 2.0 has discontinued their "take over mode" which in previous version provided support for typescript in vue files.
          -- The new approach to get typescript support involves using the typescript language server along side volar.
          vtsls = {
            on_attach = function(client)
              -- disable formatting, since we use prettier
              client.server_capabilities.inlayHintProvider = false
              client.server_capabilities.documentFormattingProvider = false
            end,
            ---@diagnostic disable-next-line: missing-fields
            settings = {},
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
            on_attach = function(client)
              client.server_capabilities.inlayHintProvider = false
            end,
          },
        },
      })

      local keys = require("lazyvim.plugins.lsp.keymaps").get()
      keys[#keys + 1] = { "<C-k>", false, mode = { "i" } }
      return opts
    end,
  },
}
