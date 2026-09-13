-- Plugin setups

-- Theme
require("kanagawa").setup({ background = { dark = "wave" } })
vim.cmd.colorscheme("kanagawa")

-- Simple plugin setups
require("lualine").setup({})
require("oil").setup()
require("fzf-lua").setup({})

-- Treesitter
require("nvim-treesitter.configs").setup({
  highlight = { enable = true },
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
