{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  # deadnix: skip
  jmusicbot = "${config.custom.homelab.serviceDataDir}/jmusicbot";
  tgtg_volume = "${config.custom.homelab.serviceDataDir}/tgtg";

  cfg = config.custom.homelab;
in
{
  options.custom.homelab = {
    enable = lib.mkEnableOption "homelab stuff";
    enablevps = lib.mkEnableOption "VPS homelab stuff";
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

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      virtualisation.oci-containers.backend = "podman";
      environment.systemPackages = [ ];
      systemd.tmpfiles.rules = [ ];

      networking.firewall.allowedTCPPorts = [
        80 # caddy
        443 # caddy
      ];

      #Caddy reverse proxy
      services.caddy = {
        enable = true;
        package = pkgs.callPackage ../../../packages/caddy { };
      };

      systemd.services.caddy.serviceConfig = {
        EnvironmentFile = "${config.age.secrets.duckdns.path}";
      };
    })
    (lib.mkIf cfg.enablevps {
      virtualisation.oci-containers.backend = "docker";
      virtualisation.oci-containers.containers = {
        tgtg = {
          image = "derhenning/tgtg:latest-alpine";

          environment = {
            TZ = "Europe/Madrid";
            LOCALE = "es_ES";
            SLEEP_TIME = "60";
            TELEGRAM = "true";
          };
          environmentFiles = [ "${config.age.secrets.tgtg.path}" ];
          extraOptions = [ "--pull=always" ];
          volumes = [ "${tgtg_volume}:/tokens" ];
        };
      };
    })
  ];
}
