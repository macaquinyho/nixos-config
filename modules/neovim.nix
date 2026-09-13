{ pkgs, ... }:
{
  appName = "nvim-mnw";
  neovim = pkgs.neovim-unwrapped;
  initLua = ''
    require('myconfig')
  '';
  extraBinPath = with pkgs; [
    clang
    gitlab-ci-ls
    lua-language-server
    bash-language-server
    yaml-language-server
    ruff
    ty
    rust-analyzer
    tombi
    vscode-langservers-extracted
    jinja-lsp
    nixd
    texlab
    systemd-lsp
    ansible-language-server
  ];
  plugins = {
    start = with pkgs.vimPlugins; [
      oil-nvim
      fzf-lua
      vim-tmux-navigator
      luasnip
      nvim-treesitter-legacy.withAllGrammars
      vim-fugitive
      kanagawa-nvim
      nvim-web-devicons
      nvim-cmp
      cmp-buffer
      cmp-path
      cmp-nvim-lsp
      lualine-nvim
      render-markdown-nvim
    ];
    dev.myconfig = {
      pure = ../neovim;
      impure = "~/projects/nixos-config/neovim";
    };

  };
}
