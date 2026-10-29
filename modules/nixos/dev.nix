{
  self,
  pkgs,
  config,
  lib,
  ...
}:
let

  cfg = config.custom.dev;
  inherit (self.inputs) wrappers;

  tmuxsessionizer = pkgs.writeShellScriptBin "sessionizer" (
    builtins.readFile ./dotfiles/tmux-sessionizer.sh
  );
  sopsPlugins = pkgs.sops.withAgePlugins (p: [ p.age-plugin-fido2-hmac ]);
  claudeMdFile = pkgs.writeText "CLAUDE.md" cfg.claudeMd;
  claudeSettingsFile = (pkgs.formats.json { }).generate "claude-settings.json" cfg.claudeSettings;
  devPackages = with pkgs; [
    tmuxsessionizer
    libclang
    nixfmt
    shellcheck
    shfmt
    gnumake
    rage
    age-plugin-fido2-hmac
    sopsPlugins
    uv
    sshpass
    just
    tio
    pandoc
    glab
    gh
    tldr
    python313
    file
    self.packages.${pkgs.stdenv.hostPlatform.system}.nvim-mnw
    jq
    repomix
    ripgrep
    git-lfs
    self.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
  ];

  gitBase = (
    wrappers.wrapperModules.git.apply {
      inherit pkgs;

      settings = {
        alias = {
          co = "checkout";
          ci = "commit";
          a = "add";
          aa = "add --all";
          r = "restore";
          rs = "restore --staged";
          s = "status";
          l = "log --graph --all --decorate";
          d = "diff";
          ds = "diff --staged";
          home = "rev-parse --show-toplevel";
        };

        user.name = "Toomoch";
        user.email = "vallsfustearnau@gmail.com";
        color = {
          ui = true;
        };

        # https://git-scm.com/docs/git-rebase#Documentation/git-rebase.txt---autosquash
        rebase = {
          autosquash = true;
        };

        core = {
          editor = "nvim";
          # NOTE: you can invoke your editor with a different config
          #   editor = nvim -u /path/to/your/config

          # https://git-scm.com/docs/git-diff#Documentation/git-diff.txt---abbrevltngt
          abbrev = 12;

          excludesFile = pkgs.writeText "gitignore-global" ''
            .claude/settings.local.json
            .claude/agent-memory-local/
          '';
        };

        # List branches and tags from newest to oldest
        branch = {
          sort = "-committerdate";
        };
        tag = {
          sort = "-taggerdate";
        };

        column = {
          ui = "auto";
        };

        push = {
          # https://git-scm.com/docs/git-config#Documentation/git-config.txt-pushautoSetupRemote
          autoSetupRemote = true;
          # Push tags automatically
          followtags = true;
        };

        # https://wiki.smd.dev/en/GitGuidelines#conflict-presentation
        merge = {
          conflictstyle = "zdiff3";
          # https://git-scm.com/docs/git-config#Documentation/git-config.txt-mergelog
          log = true;
        };

        commit = {
          # verbose means that when you are writing the commit message, you will also see
          # the diff introduced by the commit.
          verbose = true;
          #   template = /path/to/your/commit/template.txt
        };

        diff = {
          #   algorithm = histogram
          # Colors moved text differently
          colorMoved = "plain";
          #   compactionHeuristic = true
        };

        # https://git-scm.com/book/en/v2/Git-Tools-Rerere
        # https://git-scm.com/docs/git-rerere
        rerere = {
          enabled = true;
          autoUpdate = true;
        };

        # Useful to link fixed commits in your commit descriptions
        # https://docs.kernel.org/process/submitting-patches.html#describe-your-changes
        pretty = {
          fixes = ''Fixes: %h ("%s")'';
        };

        # Equivalent to `programs.git.lfs.enable = true` — git-lfs must be on PATH.
        filter."lfs" = {
          clean = "git-lfs clean -- %f";
          smudge = "git-lfs smudge -- %f";
          process = "git-lfs filter-process";
          required = true;
        };
      };
    }
  );

in
{

  options.custom.dev = {
    enable = lib.mkEnableOption "Whther to enable arnau specific dev stuff";

    gitBasePackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = gitBase.wrapper;
      defaultText = lib.literalExpression "gitBase.wrapper";
      description = ''
        Read-only base git wrapper (arnau's defaults). Derive a host-specific
        variant from its wrapper configuration and assign it to
        custom.dev.gitPackage, e.g.:

          custom.dev.gitPackage = lib.mkForce
            (config.custom.dev.gitBasePackage.passthru.configuration.apply {
              settings.user.email = lib.mkForce "you@example.com";
            }).wrapper;
      '';
    };

    gitPackage = lib.mkOption {
      type = lib.types.package;
      default = cfg.gitBasePackage;
      defaultText = lib.literalExpression "config.custom.dev.gitBasePackage";
      description = "git wrapper package installed for arnau; override per host.";
    };

    claudeMd = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = "Contents of the global ~/.claude/CLAUDE.md. Value lives in the private flake.";
    };

    claudeSettings = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
      default = null;
      description = ''
        Contents of the global ~/.claude/settings.json, linked into ~/.claude.
        Value lives in the private flake. The link is read-only, so /config and
        /plugin cannot persist changes: edit them here and rebuild instead.
      '';
    };

    claudeMcpServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = "MCP servers added to the claude sandbox's built-in ones.";
    };

    claudeAllowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "gitlab.example.com:443" ];
      description = "HOST:PORT entries added to the claude sandbox's egress allowlist.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.arnau.packages = devPackages ++ [ cfg.gitPackage ];

    # global CLAUDE.md and settings.json
    systemd.tmpfiles.rules =
      lib.optional (
        cfg.claudeMd != null
      ) "L+ ${config.users.users.arnau.home}/.claude/CLAUDE.md - - - - ${claudeMdFile}"
      ++ lib.optional (
        cfg.claudeSettings != null
      ) "L+ ${config.users.users.arnau.home}/.claude/settings.json - - - - ${claudeSettingsFile}";

    # dev
    programs.direnv.enable = true;
    programs.direnv.nix-direnv.enable = true;
    programs.tmux = {
      enable = true;
      clock24 = true;
      extraConfig = builtins.readFile ./dotfiles/tmux.conf;
    };
    programs.starship.enable = true;
    programs.fzf.keybindings = true;
    environment.shellAliases = {
      ls = "ls --human-readable --color=auto -la";
      ip = "ip -c";
      ".." = "cd ..";
      lsperms = "stat --format '%a'";
      sshgen = "ssh-keygen -t ed25519 -C $USER@$(hostname)";
      tiomenu = ''tio -b 115200 $(FZF_DEFAULT_COMMAND='find /dev/serial/by-id | tail -n +2 ' fzf --header="Pick a serial port")'';
      agenix = "agenix --extra-flake-params \\?submodules=1";
      vim = "nvim";
      vimdiff = "nvim -d";
      aspm = "sudo lspci -vv | awk '/ASPM/{print $0}' RS= | grep --color -P '(^[a-z0-9:.]+|ASPM )'";
      grep = "grep --color=auto";
      vimdev = "${self.packages.${pkgs.stdenv.hostPlatform.system}.nvim-mnw.devMode}/bin/nvim";
      claude = lib.getExe (
        self.packages.${pkgs.stdenv.hostPlatform.system}.claude-sandbox.override {
          inherit (cfg) gitPackage claudeSettings;
          extraMcpServers = cfg.claudeMcpServers;
          extraAllowedHosts = cfg.claudeAllowedHosts;
          nixDaemon = !config.custom.common.trustedUser;
          nixPackage = config.nix.package;
        }
      );
      pi = lib.getExe (
        self.packages.${pkgs.stdenv.hostPlatform.system}.pi-sandbox.override {
          inherit (cfg) gitPackage;
          nixDaemon = !config.custom.common.trustedUser;
          nixPackage = config.nix.package;
        }
      );
    };
    environment.sessionVariables = {
      UV_PYTHON_DOWNLOADS = "never";
      UV_NO_MANAGED_PYTHON = "1";
      EDITOR = "nvim";
      MANPAGER = "nvim +Man!";
    };
    programs.ssh =
      let
        isValidHost = name: hostConfig: (hostConfig.config.custom.deployment.enable or false);

        mkHostBlock =
          name: hostConfig:
          let
            deploy = hostConfig.config.custom.deployment;
          in
          ''
            Host ${name}
              Hostname ${deploy.hostname}
              User ${deploy.user}
              Port ${toString deploy.port}
              ForwardAgent yes
          '';

        validHosts = lib.filterAttrs isValidHost self.nixosConfigurations;

        dynamicHostConfig = lib.concatStringsSep "\n" (lib.mapAttrsToList mkHostBlock validHosts);

        globalConfig = ''
          Host *
            SetEnv TERM="xterm-256color"
            AddKeysToAgent yes
            Compression no
            ForwardAgent no
            HashKnownHosts no
            ServerAliveCountMax 3
            ServerAliveInterval 0
            UserKnownHostsFile ~/.ssh/known_hosts
        '';
      in
      {

        extraConfig = ''
          ${dynamicHostConfig}

          ${globalConfig}
        '';
      };

  };
}
