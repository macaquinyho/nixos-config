{
  description = "Arnau NixOS configs";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    nixpkgs-stable.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";
    nixpkgs-small.url = "https://channels.nixos.org/nixos-unstable-small/nixexprs.tar.zst";
    nixpkgs-unfree.url = "github:numtide/nixpkgs-unfree";
    nixpkgs-unfree.inputs.nixpkgs.follows = "nixpkgs";

    # up to date claude-code
    llm-agents.url = "github:numtide/llm-agents.nix";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko-stable = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    preservation.url = "github:nix-community/preservation";

    jail-nix.url = "sourcehut:~alexdavid/jail.nix";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix-rekey = {
      url = "github:oddlama/agenix-rekey";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "";
    };

    wirenix.url = "sourcehut:~msalerno/wirenix";
    mnw.url = "github:Gerg-L/mnw";
    wrappers.url = "github:lassulus/wrappers";

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Nothing here may reference the private tree: this directory is a subtree of
  # the private flake and gets published on its own. Host configurations are
  # assembled there, so what this flake exposes is usable on its own.
  outputs =
    {
      self,
      nixpkgs,
      mnw,
      llm-agents,
      git-hooks,
      treefmt-nix,
      jail-nix,
      nixpkgs-stable,
      ...
    }:
    let
      forAllSystems =
        function: nixpkgs':
        nixpkgs'.lib.genAttrs nixpkgs'.lib.systems.flakeExposed (
          system: function (nixpkgs'.legacyPackages.${system}) system
        );

    in
    {
      packages = forAllSystems (
        pkgs: system:
        {
          nvim-mnw = mnw.lib.wrap pkgs ./modules/neovim.nix;
          mcp-victoriametrics = pkgs.callPackage ./packages/mcp-victoriametrics.nix { };
          nixos-ci-update = pkgs.callPackage ./packages/nixos-ci-update { };
          claude-sandbox-proxy = pkgs.callPackage ./packages/claude-sandbox-proxy { };
          # the hosts are on stable, and the plugin hash depends on caddy's version
          caddy-with-plugins = nixpkgs-stable.legacyPackages.${system}.callPackage ./packages/caddy { };
          claude-code = pkgs.callPackage ./packages/claude-code.nix {
            claude-code = llm-agents.packages.${system}.claude-code;
            mcp-victoriametrics = self.packages.${system}.mcp-victoriametrics;
          };
        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          claude-sandbox = pkgs.callPackage ./packages/claude-sandbox.nix {
            jail = jail-nix.lib.init pkgs;
            claude-sandbox-proxy = self.packages.${system}.claude-sandbox-proxy;
            claude-code = self.packages.${system}.claude-code;
            mcp-victoriametrics = self.packages.${system}.mcp-victoriametrics;
          };
          pi-sandbox = pkgs.callPackage ./packages/pi-sandbox.nix {
            jail = jail-nix.lib.init pkgs;
            claude-sandbox-proxy = self.packages.${system}.claude-sandbox-proxy;
            pi = llm-agents.packages.${system}.pi;
          };
          claude-desktop = pkgs.callPackage ./packages/claude-desktop-jail.nix {
            jail = jail-nix.lib.init pkgs;
            claude-desktop = llm-agents.packages.${system}.claude-desktop;
          };
        }
      ) nixpkgs;

      checks = forAllSystems (pkgs: system: {
        pre-commit-check = self.lib.mkPreCommitCheck {
          inherit pkgs system;
          src = ./.;
        };
      }) nixpkgs;

      devShells = forAllSystems (pkgs: system: {
        default = pkgs.mkShell {
          inherit (self.checks.${system}.pre-commit-check) shellHook;
          buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
        };

        ci = pkgs.mkShellNoCC {
          packages = with pkgs; [
            dix
            git
            git-lfs
            glab
            gnused
            jq
            nix
            nix-eval-jobs
            nix-update
            openssh
          ];
        };
      }) nixpkgs;

      formatter = forAllSystems (
        pkgs: system:
        (treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }).config.build.wrapper
      ) nixpkgs;

      # do not use import keyword for pointing to modules, use the path
      nixosModules.common = ./modules/nixos;
      overlays = import ./overlays;

      lib.mkPreCommitCheck =
        {
          pkgs,
          system,
          src,
          extraHooks ? { },
        }:
        git-hooks.lib.${system}.run {
          inherit src;
          package = pkgs.prek;
          hooks = {
            nixfmt.enable = true;
            deadnix.enable = true;
            deadnix.settings.noLambdaPatternNames = true;
            deadnix.settings.noLambdaArg = true;
            flake-checker.enable = true;
          }
          // extraHooks;
        };
    };
}
