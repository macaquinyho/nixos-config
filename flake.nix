{
  description = "Arnau NixOS configs";

  inputs = {
    self.submodules = true;
    self.lfs = true;

    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nixpkgs-stable.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
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

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      deploy-rs,
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
    }:
    let
      # specialArgs
      flake-root = ./.;
      private = flake-root + "/private";

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

      hosts = [
        {
          host = "oracle1";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "ps42";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "h81";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "b450";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "rpi3";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "ampere";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "potato";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "moniato";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "x550";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "smdltp451";
          branch = stable;
          privateConfigs = true;
        }
        {
          host = "vm";
          branch = stable;
        }
      ];

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
          help-blog = pkgs.callPackage ./packages/blog.nix { };
          nvim-mnw = mnw.lib.wrap pkgs ./modules/neovim.nix;
          mcp-victoriametrics = pkgs.callPackage ./packages/mcp-victoriametrics.nix { };
          claude-code = pkgs.callPackage ./packages/claude-code.nix {
            claude-code = llm-agents.packages.${system}.claude-code;
            mcp-victoriametrics = self.packages.${system}.mcp-victoriametrics;
          };
        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          claude-sandbox = pkgs.callPackage ./packages/claude-sandbox.nix {
            inherit private;
            jail = jail-nix.lib.init pkgs;
            claude-code = self.packages.${system}.claude-code;
            mcp-victoriametrics = self.packages.${system}.mcp-victoriametrics;
          };
        }
      ) nixpkgs;

      checks = forAllSystems (pkgs: system: {
        pre-commit-check = git-hooks.lib.${system}.run {
          src = ./.;
          package = pkgs.prek;
          hooks = {
            nixfmt.enable = true;
            deadnix.enable = true;
            deadnix.settings.noLambdaPatternNames = true;
            deadnix.settings.noLambdaArg = true;
            flake-checker.enable = true;
          };
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
      nixosModules.private = private + "/modules/nixos";
      overlays = import ./overlays;

      nixosConfigurations =
        let
          defaultModules = host: branch: [
            self.nixosModules.common
            self.nixosModules.private
            branch.disko.nixosModules.disko
            branch.agenix.nixosModules.default
            agenix-rekey.nixosModules.default
            wirenix.nixosModules.default
            preservation.nixosModules.default
            ./hosts/${host}
            {
              nix.registry.nixpkgs-unstable.flake = nixpkgs;
            }
          ];

          mkHostConfig =
            {
              host,
              branch,
              privateConfigs ? false,
              ...
            }:
            {
              name = host;
              value =
                let
                  specialArgs = {
                    inherit
                      flake-root
                      private
                      self
                      nixpkgs
                      nixpkgs-unfree
                      ;
                  };
                in
                branch.nixpkgs.lib.nixosSystem {
                  inherit specialArgs;
                  modules =
                    defaultModules host branch
                    ++ branch.nixpkgs.lib.optional privateConfigs (private + "/hosts/${host}");
                  # Include private host config
                };
            };

        in
        builtins.listToAttrs (map mkHostConfig hosts);

      agenix-rekey = agenix-rekey.configure {
        userFlake = self;
        nixosConfigurations = self.nixosConfigurations;
      };

      # deploy-rs node configuration stolen from https://github.com/LongerHV/nixos-configuration
      deploy.nodes =
        let
          mkDeployConfig = hostname: configuration: interactiveSudo: remoteBuild: {
            inherit hostname interactiveSudo remoteBuild;
            profiles.system =
              let
                inherit (configuration.config.nixpkgs.hostPlatform) system;
              in
              {
                path = deploy-rs.lib."${system}".activate.nixos configuration;
                sshUser = "arnau";
                user = "root";
                #interactiveSudo = true;
                #sshOpts = ["-A"];
                sshOpts = [
                  "-o"
                  "ProxyCommand=none"
                ];
                magicRollback = true;
              };
          };
        in
        {
          h81 = mkDeployConfig "h81" self.nixosConfigurations.h81 false true;
          rpi3 = mkDeployConfig "rpi3" self.nixosConfigurations.rpi3 false false;
          oracle1 = mkDeployConfig "oracle1" self.nixosConfigurations.oracle1 false false;
          ampere = mkDeployConfig "ampere" self.nixosConfigurations.ampere false true;
        };
      # checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
