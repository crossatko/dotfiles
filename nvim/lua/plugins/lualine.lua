local function get_hl_color(group, attr)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group })
  if ok and hl[attr] then
    return string.format("#%06x", hl[attr])
  end
  return nil
end

return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  opts = {
    options = {
      theme = function()
        local colors = {
          darkgray = get_hl_color("StatusLineNC", "bg") or "#16161d",
          gray = get_hl_color("Comment", "fg") or "#727169",
          innerbg = get_hl_color("StatusLine", "bg"),
          outerbg = get_hl_color("Normal", "bg"),
          normal = get_hl_color("Function", "fg"),
          insert = get_hl_color("String", "fg"),
          visual = get_hl_color("Visual", "bg"),
          replace = get_hl_color("ErrorMsg", "fg"),
          command = get_hl_color("Keyword", "fg"),
        }

        return {
          inactive = {
            a = { fg = colors.gray, bg = colors.outerbg, gui = "bold" },
            b = { fg = colors.gray, bg = colors.outerbg },
            c = { fg = colors.gray, bg = colors.innerbg },
          },
          visual = {
            a = { fg = colors.darkgray, bg = colors.visual, gui = "bold" },
            b = { fg = colors.gray, bg = colors.outerbg },
            c = { fg = colors.gray, bg = colors.innerbg },
          },
          replace = {
            a = { fg = colors.darkgray, bg = colors.replace, gui = "bold" },
            b = { fg = colors.gray, bg = colors.outerbg },
            c = { fg = colors.gray, bg = colors.innerbg },
          },
          normal = {
            a = { fg = colors.darkgray, bg = colors.normal, gui = "bold" },
            b = { fg = colors.gray, bg = colors.outerbg },
            c = { fg = colors.gray, bg = colors.innerbg },
          },
          insert = {
            a = { fg = colors.darkgray, bg = colors.insert, gui = "bold" },
            b = { fg = colors.gray, bg = colors.outerbg },
            c = { fg = colors.gray, bg = colors.innerbg },
          },
          command = {
            a = { fg = colors.darkgray, bg = colors.command, gui = "bold" },
            b = { fg = colors.gray, bg = colors.outerbg },
            c = { fg = colors.gray, bg = colors.innerbg },
          },
        }
      end,
    },
  },
}
