-- Options and globals

vim.opt.expandtab = true
vim.opt.number = true
vim.opt.smartindent = true
vim.opt.wrap = true
vim.opt.exrc = true

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- OSC52 clipboard for SSH sessions
if vim.env.SSH_CONNECTION then
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = {
      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
      ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
      ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
    },
  }
end
