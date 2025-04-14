vim.filetype.add({
  extension = {
    conf = "conf",
    env = "dotenv",
  },
  filename = {
    [".env"] = "dotenv",
    [".env.example"] = "dotenv",
    [".yamlfmt"] = "yaml",
    [".*/hypr/.*%.conf"] = "hyprlang",
    [".*/hypr/.*%.conf.example"] = "hyprlang",
  },
  pattern = {
    ["%.env%.[%w_.-]+"] = "dotenv",
  },
})

-- check ../plugins/treesitter.lua to enable ts highlighting for new filetypes
