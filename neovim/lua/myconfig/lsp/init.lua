-- LSP configurations

-- Configure LSP servers
require("myconfig.lsp.servers")

-- LSP keymaps and autocmds
local on_attach = function(_client, bufnr)
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end
    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('gd', vim.lsp.buf.definition, 'Go to Definition')
  nmap('gi', vim.lsp.buf.implementation, 'Go to Implementation')
  nmap('gD', vim.lsp.buf.references, 'Go to References')
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  nmap('<leader>ca', vim.lsp.buf.code_action, 'Code Actions')
  nmap('<leader>lf', vim.lsp.buf.format, 'Format Buffer')
  nmap('<leader>k', function() vim.diagnostic.jump({ count = -1, float = true }) end, 'Previous Diagnostic')
  nmap('<leader>j', function() vim.diagnostic.jump({ count = 1, float = true }) end, 'Next Diagnostic')
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    local bufnr = args.buf
    on_attach(client, bufnr)
  end,
})

-- Load texlab-specific setup
require("myconfig.lsp.texlab")
