-- Keymaps

local fzf = require("fzf-lua")

-- Helper to set multiple keymaps
local function set(maps)
  for _, m in ipairs(maps) do
    local opts = m[4] or {}
    vim.keymap.set(m[1], m[2], m[3], opts)
  end
end

set {
  -- FZF
  { "n", "<leader>fd", function() fzf.grep_curbuf() end },
  { "n", "<leader>ff", function() fzf.files() end },
  { "n", "<leader>fg", function() fzf.grep_project() end },

  -- Clipboard & delete
  { "", "<leader>p", '"_dP' },
  { "", "<leader>d", '"_d' },
  { "", "<leader>y", '"+y' },

  -- Disable arrow keys
  { "", "<Down>",  "<Nop>" },
  { "", "<Left>",  "<Nop>" },
  { "", "<Right>", "<Nop>" },
  { "", "<Up>",    "<Nop>" },

  -- Git (fugitive)
  { "", "<leader>gs", ":Ge:<CR>",           { desc = "Git status" } },
  { "", "<leader>gd", ":set nosplitright<CR>:execute 'Gvdiff ' .. g:git_base<CR>:set splitright<CR>", { desc = "Git diff" } },
  { "", "<leader>gb", ":Git blame<CR>",     { desc = "Git blame" } },
  { "", "<leader>gc", ":0Gclog<CR>",        { desc = "Git log-pick" } },
  { "", "<leader>gp", ":Git push<CR>",      { desc = "Git push" } },
  { "", "<leader>gP", ":Git pull<CR>",      { desc = "Git pull" } },

  -- Tmux navigation
  { "", "<M-h>",  ":TmuxNavigateLeft<CR>" },
  { "", "<M-j>",  ":TmuxNavigateDown<CR>" },
  { "", "<M-k>",  ":TmuxNavigateUp<CR>" },
  { "", "<M-l>",  ":TmuxNavigateRight<CR>" },
  { "", "<M-\\>", ":TmuxNavigatePrevious<CR>" },

  -- Center cursor on scroll
  { "", "<C-d>", "<C-d>zz" },
  { "", "<C-u>", "<C-u>zz" },

  -- Oil
  { "", "-", ":Oil<CR>" },
}
