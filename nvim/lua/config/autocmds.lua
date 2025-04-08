-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
return {
  config = function()
    vim.cmd("hi Normal ctermbg=NONE guibg=NONE")

    -- @l creates console log with selected text
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, true, true)
    vim.api.nvim_create_augroup("JSLogMacro", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group = "JSLogMacro",
      pattern = { "javascript", "typescript", "vue" },
      callback = function()
        vim.fn.setreg("l", "yoconsole.log('" .. esc .. "pa:" .. esc .. "la, " .. esc .. "pl")
      end,
    })
  end,
}
