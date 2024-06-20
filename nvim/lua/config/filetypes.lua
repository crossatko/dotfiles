vim.filetype.add({
  extension = {
    conf = "conf",
    env = "dotenv",
  },
  filename = {
    [".env"] = "dotenv",
    [".env.example"] = "dotenv",
    [".yamlfmt"] = "yaml",
  },
  pattern = {
    ["%.env%.[%w_.-]+"] = "dotenv",
  },
})

-- check ../plugins/treesitter.lua to enable ts highlighting for new filetypes
