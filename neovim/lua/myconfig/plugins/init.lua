-- Plugin setups

-- Theme
require("kanagawa").setup({ background = { dark = "wave" } })
vim.cmd.colorscheme("kanagawa")

-- Simple plugin setups
require("lualine").setup({})
require("oil").setup()
require("fzf-lua").setup({})

-- Treesitter
vim.api.nvim_create_autocmd("FileType", {
  -- not every filetype has a parser
  callback = function() pcall(vim.treesitter.start) end,
})

-- Render markdown
require('render-markdown').setup({
  enabled = true,
  heading = {
    enabled = false,
  },
  code = {
    highlight = "RenderMarkdownCode",
    highlight_inline = "RenderMarkdownCodeInline",
    style = "full",
  }
})

-- Diagnostics
vim.diagnostic.config({ virtual_text = true })

-- Load completion setup
require("myconfig.plugins.completion")
