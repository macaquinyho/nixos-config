{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.remote-builder;
  flakeHosts = config.custom.flake.nixosConfigurations;
in
{
  options.custom.remote-builder = {
    server = {
      enable = lib.mkEnableOption "accepting builds from other hosts of the flake";
      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Public keys of the clients. They can only start nix-daemon, but they
          are trusted nix users, which is what building input-addressed
          derivations requires.
        '';
      };
    };

    client = {
      enable = lib.mkEnableOption "offloading builds to other hosts of the flake";
      machines = lib.mkOption {
        default = { };
        description = "Builders by flake host name. A builder that is off is skipped and the build runs locally.";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                hostName = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                  description = "Address ssh connects to.";
                };
                publicKey = lib.mkOption {
                  type = lib.types.str;
                  default = flakeHosts.${name}.config.age.rekey.hostPubkey;
                  description = "ssh host key of the builder.";
                };
                system = lib.mkOption {
                  type = lib.types.str;
                  default = "x86_64-linux";
                };
                maxJobs = lib.mkOption {
                  type = lib.types.int;
                  default = 4;
                };
                speedFactor = lib.mkOption {
                  type = lib.types.int;
                  default = 4;
                };
                supportedFeatures = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ "big-parallel" ];
                };
              };
            }
          )
        );
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.server.enable {
      users.groups.builder = { };
      users.users.builder = {
        isSystemUser = true;
        group = "builder";
        useDefaultShell = true;
        openssh.authorizedKeys.keys = map (
          key: ''restrict,command="${config.nix.package}/bin/nix-daemon --stdio" ${key}''
        ) cfg.server.authorizedKeys;
      };
      nix.settings.trusted-users = [ "builder" ];
    })

    (lib.mkIf cfg.client.enable {
      # the daemon runs as root, which is who opens the connection
      age.secrets.remote-builder-key = { };

      nix.distributedBuilds = true;
      # the builder fetches from the caches itself, not through this host
      nix.settings.builders-use-substitutes = true;
      nix.buildMachines = lib.mapAttrsToList (_: m: {
        inherit (m)
          hostName
          system
          maxJobs
          speedFactor
          supportedFeatures
          ;
        protocol = "ssh-ng";
        sshUser = "builder";
        sshKey = config.age.secrets.remote-builder-key.path;
      }) cfg.client.machines;

      programs.ssh.knownHosts = lib.mapAttrs' (
        name: m:
        lib.nameValuePair "remote-builder-${name}" {
          hostNames = [ m.hostName ];
          inherit (m) publicKey;
        }
      ) cfg.client.machines;

      # nix tries the builder for every derivation, so a host that is off must fail quickly
      programs.ssh.extraConfig = lib.concatMapStrings (m: ''
        Host ${m.hostName}
          ConnectTimeout 5
      '') (lib.attrValues cfg.client.machines);
    })
  ];
}
