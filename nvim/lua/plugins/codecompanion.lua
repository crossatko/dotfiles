-- lua/plugins/codecompanion.lua

return {
  "olimorris/codecompanion.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },

  keys = {
    -- Toggle the main CodeCompanion window
    { "<leader>cc", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "Toggle CodeCompanion" },

    -- Quick actions
    { "<leader>ce", "<cmd>CodeCompanionExplain<cr>", mode = "v", desc = "[C]ompanion [E]xplain" },
    { "<leader>ct", "<cmd>CodeCompanionTests<cr>", mode = "v", desc = "[C]ompanion [T]ests" },
    { "<leader>cd", "<cmd>CodeCompanionDoc<cr>", mode = "v", desc = "[C]ompanion [D]ocumentation" },
    { "<leader>cr", "<cmd>CodeCompanionRefactor<cr>", mode = "v", desc = "[C]ompanion [R]efactor" },
  },

  opts = {
    default_provider = "copilot",

    providers = {
      copilot = {
        provider = "copilot",
      },
    },
  },
}
