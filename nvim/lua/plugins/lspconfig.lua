return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "b0o/SchemaStore.nvim",
      version = false, -- last release is way too old
    },

    opts = function(_, opts)
      -- Load each LSP server config from config/lsp/
      local servers = {
        "tailwindcss",
        "jsonls",
        "bashls",
        "volar",
        "vtsls",
        "emmet_ls",
      }
      opts.servers = opts.servers or {}
      for _, server in ipairs(servers) do
        local ok, config = pcall(require, "lsp." .. server)
        if ok and type(config) == "table" then
          opts.servers[server] = vim.tbl_deep_extend("force", opts.servers[server] or {}, config)
        else
          vim.notify("Failed to load LSP config for: " .. server, vim.log.levels.ERROR)
        end
      end

      -- Special logic for vtsls: add vue typescript plugin
      if opts.servers.vtsls then
        opts.servers.vtsls.settings = opts.servers.vtsls.settings or {}
        opts.servers.vtsls.settings.tsserver = opts.servers.vtsls.settings.tsserver or {}
        opts.servers.vtsls.settings.tsserver.globalPlugins = opts.servers.vtsls.settings.tsserver.globalPlugins or {}
        table.insert(opts.servers.vtsls.settings.tsserver.globalPlugins, {
          name = "@vue/typescript-plugin",
          location = LazyVim.get_pkg_path("vue-language-server", "/node_modules/@vue/language-server"),
          languages = { "vue" },
          configNamespace = "typescript",
          enableForWorkspaceTypeScriptVersions = true,
        })
      end

      local keys = require("lazyvim.plugins.lsp.keymaps").get()
      keys[#keys + 1] = { "<C-k>", false, mode = { "i" } }
      return opts
    end,
  },
}
