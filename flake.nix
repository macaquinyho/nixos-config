{
  description = "Arnau NixOS configs";

  inputs = {
    self.lfs = true;

    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    nixpkgs-stable.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
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
  # the private flake and gets published on its own. The private flake consumes
  # it as a relative path input and assembles the nixosConfigurations.
  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      disko-stable,
      disko,
      agenix,
      agenix-rekey,
      wirenix,
      mnw,
      nixpkgs-unfree,
      llm-agents,
      preservation,
      git-hooks,
      treefmt-nix,
      jail-nix,
      ...
    }@inputs:
    let
      # specialArgs
      flake-root = ./.;

      stable = {
        nixpkgs = nixpkgs-stable;
        disko = disko-stable;
        agenix = agenix;
      };

      # deadnix: skip
      unstable = {
        nixpkgs = nixpkgs;
        disko = disko;
        agenix = agenix;
      };

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
          claude-code = pkgs.callPackage ./packages/claude-code.nix {
            claude-code = llm-agents.packages.${system}.claude-code;
            mcp-victoriametrics = self.packages.${system}.mcp-victoriametrics;
          };
        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          claude-sandbox = pkgs.callPackage ./packages/claude-sandbox.nix {
            jail = jail-nix.lib.init pkgs;
            claude-code = self.packages.${system}.claude-code;
            mcp-victoriametrics = self.packages.${system}.mcp-victoriametrics;
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
            git
            git-lfs
            glab
            gnused
            jq
            nix
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

      lib = {
        inherit stable unstable;

        mkPreCommitCheck =
          {
            pkgs,
            system,
            src,
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
            };
          };

        # The blog content lives in the private tree, so the caller passes it in.
        mkBlog = pkgs: src: pkgs.callPackage ./packages/blog.nix { inherit src; };

        # specialArgs has to carry `private` (the tree holding the secrets and
        # the host overrides) and `self` (the flake defining the resulting
        # nixosConfigurations), both of which modules here reach for.
        mkNixosSystem =
          {
            host,
            branch ? stable,
            modules ? [ ],
            specialArgs,
          }:
          branch.nixpkgs.lib.nixosSystem {
            specialArgs = {
              inherit
                flake-root
                nixpkgs
                nixpkgs-unfree
                ;
            } // specialArgs;
            modules = [
              self.nixosModules.common
              branch.disko.nixosModules.disko
              branch.agenix.nixosModules.default
              agenix-rekey.nixosModules.default
              wirenix.nixosModules.default
              preservation.nixosModules.default
              ./hosts/${host}
              {
                nix.registry.nixpkgs-unstable.flake = nixpkgs;
              }
            ]
            ++ modules;
          };
      };
    };
}
