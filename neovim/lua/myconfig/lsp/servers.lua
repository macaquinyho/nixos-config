-- LSP server configurations

local cache_dir = vim.uv.os_homedir() .. '/.cache/gitlab-ci-ls'

local mod_cache = nil
local std_lib = nil

--- @class go_dir_custom_args
---
--- @field envvar_id string
---
--- @field custom_subdir string?

---@param custom_args go_dir_custom_args
---@param on_complete fun(dir: string | nil)
local function identify_go_dir(custom_args, on_complete)
  local cmd = { 'go', 'env', custom_args.envvar_id }
  vim.system(cmd, { text = true }, function(output)
    local res = vim.trim(output.stdout or '')
    if output.code == 0 and res ~= '' then
      if custom_args.custom_subdir and custom_args.custom_subdir ~= '' then
        res = res .. custom_args.custom_subdir
      end
      on_complete(res)
    else
      vim.schedule(function()
        vim.notify(
          ('[gopls] identify ' .. custom_args.envvar_id .. ' dir cmd failed with code %d: %s\n%s'):format(
            output.code,
            vim.inspect(cmd),
            output.stderr
          )
        )
      end)
      on_complete(nil)
    end
  end)
end

---@return string?
local function get_std_lib_dir()
  if std_lib and std_lib ~= '' then
    return std_lib
  end

  identify_go_dir({ envvar_id = 'GOROOT', custom_subdir = '/src' }, function(dir)
    if dir then
      std_lib = dir
    end
  end)
  return std_lib
end

---@return string?
local function get_mod_cache_dir()
  if mod_cache and mod_cache ~= '' then
    return mod_cache
  end

  identify_go_dir({ envvar_id = 'GOMODCACHE' }, function(dir)
    if dir then
      mod_cache = dir
    end
  end)
  return mod_cache
end

---@param fname string
---@return string?
local function get_root_dir(fname)
  if mod_cache and fname:sub(1, #mod_cache) == mod_cache then
    local clients = vim.lsp.get_clients({ name = 'gopls' })
    if #clients > 0 then
      return clients[#clients].config.root_dir
    end
  end
  if std_lib and fname:sub(1, #std_lib) == std_lib then
    local clients = vim.lsp.get_clients({ name = 'gopls' })
    if #clients > 0 then
      return clients[#clients].config.root_dir
    end
  end
  return vim.fs.root(fname, 'go.work') or vim.fs.root(fname, 'go.mod') or vim.fs.root(fname, '.git')
end


---@type table<string, vim.lsp.Config>
local servers = {
  ansiblels = {
    cmd = { 'ansible-language-server', '--stdio' },
    settings = {
      ansible = {
        python = {
          interpreterPath = 'python',
        },
        ansible = {
          path = 'ansible',
        },
        executionEnvironment = {
          enabled = false,
        },
        validation = {
          enabled = true,
          lint = {
            enabled = true,
            path = 'ansible-lint',
          },
        },
      },
    },
    filetypes = { 'yaml.ansible' },
    root_markers = { 'ansible.cfg', '.ansible-lint' },
  },
  -- clangd (C/C++)
  clangd = {
    cmd = { 'clangd', '--background-index' },
    root_markers = { 'compile_commands.json', 'compile_flags.txt' },
    filetypes = { 'c', 'cpp' },
  },

  -- gitlab-ci-ls
  gitlab_ci_ls = {
    cmd = { 'gitlab-ci-ls' },
    cmd_env = { CI_SERVER_FQDN = 'gitlab.smd.dev' },
    filetypes = { 'yaml.gitlab' },
    root_markers = { '.git', '.gitlab-ci.yml' },
    init_options = {
      cache_path = cache_dir,
      log_path = cache_dir .. '/log/gitlab-ci-ls.log',
    },
  },

  -- bashls
  bashls = {
    cmd = { 'bash-language-server', 'start' },
    settings = {
      bashIde = {
        globPattern = vim.env.GLOB_PATTERN or '*@(.sh|.inc|.bash|.command)',
      },
    },
    filetypes = { 'bash', 'sh' },
    root_markers = { '.git' },
  },

  -- lua_ls
  lua_ls = {
    cmd = { 'lua-language-server' },
    filetypes = { 'lua' },
    root_markers = {
      '.luarc.json', '.luarc.jsonc', '.luacheckrc',
      '.stylua.toml', 'stylua.toml', 'selene.toml', 'selene.yml', '.git',
    },
    settings = {
      Lua = {
        workspace = { library = vim.api.nvim_get_runtime_file("lua", true) },
        diagnostics = {
          unusedLocalExclude = { "_*" },
          globals = { 'vim' }
        }
      }
    }
  },

  -- yamlls
  yamlls = {
    cmd = { 'yaml-language-server', '--stdio' },
    filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab', 'yaml.helm-values' },
    root_markers = { '.git' },
    settings = {
      redhat = { telemetry = { enabled = false } },
      yaml = { format = { enable = true }, customTags = { '!unsafe scalar' } },
    },
    on_init = function(client)
      client.server_capabilities.documentFormattingProvider = true
    end,
  },

  -- nixd
  nixd = {
    cmd = { 'nixd' },
    filetypes = { 'nix' },
    root_markers = { 'flake.nix', '.git' },
  },

  -- ty (Python)
  ty = {
    cmd = { 'ty', 'server' },
    filetypes = { 'python' },
    root_markers = { 'ty.toml', 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git' },
  },

  -- ruff (Python)
  ruff = {
    cmd = { 'ruff', 'server' },
    filetypes = { 'python' },
    root_markers = { 'pyproject.toml', 'ruff.toml', '.ruff.toml', '.git' },
    settings = {},
  },

  -- rust_analyzer
  rust_analyzer = {
    cmd = { 'rust-analyzer' },
    filetypes = { 'rust' },
    root_markers = { '.git', 'Cargo.lock' },
    capabilities = { experimental = { serverStatusNotification = true } },
  },

  -- tombi (TOML)
  tombi = {
    cmd = { 'tombi', 'lsp' },
    filetypes = { 'toml' },
    root_markers = { '.git', 'tombi.toml', 'pyproject.toml' },
  },

  -- jsonls
  jsonls = {
    cmd = { 'vscode-json-language-server', '--stdio' },
    filetypes = { 'json', 'jsonc' },
    init_options = { provideFormatter = true },
    root_markers = { '.git' },
  },

  -- jinja-lsp
  jinja = {
    cmd = { 'jinja-lsp' },
    filetypes = { 'jinja' },
    root_markers = { '.git' },
  },

  gopls = {
    cmd = { 'gopls' },
    filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
    root_dir = function(bufnr, on_dir)
      local fname = vim.api.nvim_buf_get_name(bufnr)
      get_mod_cache_dir()
      get_std_lib_dir()
      -- see: https://github.com/neovim/nvim-lspconfig/issues/804
      on_dir(get_root_dir(fname))
    end,
  },
  systemd = {
    cmd = { 'systemd-lsp' },
    filetypes = { 'systemd' },
  }
}

-- Register all configs and enable all servers
for name, config in pairs(servers) do
  vim.lsp.config[name] = config
end
vim.lsp.enable(vim.tbl_keys(servers))
