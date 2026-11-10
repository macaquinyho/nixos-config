{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.homelab;
in
{
  options.custom.homelab = {
    enable = lib.mkEnableOption "homelab stuff";
    serviceDataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib";
      description = "Base directory for service data";
    };
    primaryDomain = lib.mkOption {
      type = lib.types.str;
      description = "Domain that points to this host. Used to expose web services.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = "podman";

    networking.firewall.allowedTCPPorts = [
      80 # caddy
      443 # caddy
    ];

    services.caddy = {
      enable = true;
      package = pkgs.callPackage ../../../packages/caddy { };
    };
  };
}
