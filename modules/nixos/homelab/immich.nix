{
  pkgs,
  lib,
  config,
  ...
}:
let
  immichRoot = "${config.custom.homelab.serviceDataDir}/immich";
  cfg = config.custom.immich;
  hostname = "immich.${config.custom.homelab.primaryDomain}";
in
{
  options.custom.immich.enable = lib.mkEnableOption "immich stuff";

  config = lib.mkIf cfg.enable {
    services.immich = {
      enable = true;
      mediaLocation = immichRoot;
      accelerationDevices = [ "/dev/dri/renderD128" ];
    };

    services.postgresql = {
      dataDir = "${config.custom.homelab.serviceDataDir}/postgresql/${config.services.postgresql.package.psqlSchema}";
      identMap = ''
        # ArbitraryMapName systemUser DBUser
        superuser_map      root      postgres
        superuser_map      postgres  postgres
      '';
      authentication = ''
        #type database  DBuser  auth-method optional_ident_map
        local all  postgres     peer        map=superuser_map
      '';
    };

    systemd.services.borgmatic = {
      path = [ config.services.postgresql.package ];
      # serviceConfig.CapabilityBoundingSet = "CAP_SETUID CAP_SETGID";
    };

    services.borgmatic = {
      enable = true;
      configurations.immich = {
        archive_name_format = "immich-{hostname}-{now}";
        source_directories = [ "${immichRoot}" ];
        repositories = [
          {
            path = "/zstorage/backup";
            label = "local";
          }
          # {
          #   label = "rpi3";
          #   path = "ssh://borg@${secrets.hosts.rpi3.dns}/./";
          # }
        ];
        postgresql_databases = [
          {
            name = "immich";
            format = "custom";
            username = "postgres";
          }
        ];
        ssh_command = "${pkgs.openssh}/bin/ssh -i ${config.age.secrets.borgnextcloud.path}";
        keep_daily = 7;
        keep_weekly = 4;
        encryption_passcommand = "cat ${config.age.secrets.borgnextcloud_repokey.path}";
      };
    };

    # programs.ssh.knownHosts = {
    #   ${secrets.hosts.rpi3.dns}.publicKey = secrets.hosts.rpi3.pubkey;
    # };

    age.secrets.borgnextcloud = {
      owner = "root";
      group = "root";
    };

    age.secrets.borgnextcloud_repokey = {
      owner = "root";
      group = "root";
    };

    systemd.tmpfiles.rules = [
      "d ${immichRoot} 0750 ${config.services.immich.user} ${config.services.immich.group} - -"
    ];

    services.caddy.virtualHosts."${hostname}" = {
      extraConfig = ''
        reverse_proxy http://${config.services.immich.host}:${builtins.toString config.services.immich.port}
      '';
    };
  };
}
