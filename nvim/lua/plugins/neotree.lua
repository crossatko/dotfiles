return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    sources = { "filesystem", "buffers", "git_status", "document_symbols" },
    open_files_do_not_replace_types = { "terminal", "Trouble", "trouble", "qf", "Outline" },
    filesystem = {
      bind_to_cwd = false,
      follow_current_file = { enabled = true },
      use_libuv_file_watcher = true,
    },
    window = {
      position = "left",
      width = 40,
      mappings = {
        ["<space>"] = "none",

        -- Keybinding to copy image dimensions
        ["<leader>di"] = function(state)
          local node = state.tree:get_node()
          if not node then
            vim.notify("No node selected", vim.log.levels.ERROR)
            return
          end

          local filepath = node.path
          if not filepath then
            vim.notify("No file path", vim.log.levels.ERROR)
            return
          end

          local ext = filepath:match("^.+%.([^.]+)$")
          ext = ext and ext:lower()

          local valid_exts = { png = true, jpg = true, jpeg = true, gif = true, bmp = true, webp = true }

          if not ext or not valid_exts[ext] then
            vim.notify("Not an image file: " .. tostring(ext), vim.log.levels.WARN)
            return
          end

          local handle = io.popen('identify -format "%w %h" ' .. vim.fn.shellescape(filepath))
          if not handle then
            vim.notify("Failed to run identify", vim.log.levels.ERROR)
            return
          end

          local result = handle:read("*a")
          handle:close()

          if result == "" then
            vim.notify("Could not get image dimensions", vim.log.levels.ERROR)
            return
          end

          local width, height = result:match("^(%d+)%s+(%d+)$")
          if not width or not height then
            vim.notify("Unexpected format from identify", vim.log.levels.ERROR)
            return
          end

          local html_dims = string.format('width="%s" height="%s"', width, height)
          vim.fn.setreg("+", html_dims)
          vim.notify("Copied to clipboard: " .. html_dims)
        end,
      },
    },
    default_component_configs = {
      indent = {
        with_expanders = true,
        expander_collapsed = "",
        expander_expanded = "",
        expander_highlight = "NeoTreeExpander",
      },
    },
  },
}
