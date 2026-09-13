{
  config,
  lib,
  pkgs,
  private,
  self,
  ...
}:
let
  cfg = config.custom.deployment;
in
{
  options.custom.deployment = {
    enable = lib.mkEnableOption "module for host metadata";

    hostname = lib.mkOption {
      type = lib.types.str;

      description = "IP/DNS for accesing this host via SSH";

    };
    port = lib.mkOption {
      type = lib.types.int;

      default = builtins.elemAt config.services.openssh.ports 0;
      description = "External SSH port";

    };
    publicKey = lib.mkOption {
      type = lib.types.str;
      description = "Public SSH key of this host";
      default = config.age.rekey.hostPubkey;
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "arnau";

      description = "Username for accesing this host via SSH";

    };
  };

  config = lib.mkIf cfg.enable {

    # home-manager.users.arnau.config.
    # users.users.arnau.openssh.authorizedKeys =
    #   let
    #     enabledHosts = lib.filterAttrs (
    #       name: value:
    #       (value.config.custom.host.enable or false)
    #       && value.config.custom.host.authorized
    #       && name != config.networking.hostName
    #     ) self.nixosConfigurations;
    #   in
    #   lib.mapAttrsToList (name: value: value.config.custom.host.publicKey) enabledHosts;
    #
  };
}
