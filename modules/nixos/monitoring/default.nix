{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.monitoring;
  yamlFormat = pkgs.formats.yaml { };

  supportedExporters = [
    "node"
    "smartctl"
  ];

  wgIpOf =
    host:
    lib.removeSuffix "/64" (
      builtins.elemAt host.config.systemd.network.networks."50-metrics".address 0
    );

  vmPortOfCfg = hostConfig: lib.removePrefix ":" hostConfig.services.victoriametrics.listenAddress;

  siteHost = site: config.custom.flake.nixosConfigurations.${site};
  siteIps = lib.genAttrs cfg.sites (site: wgIpOf (siteHost site));
  ownWgIp = siteIps.${cfg.siteName};
  otherSites = lib.filter (site: site != cfg.siteName) cfg.sites;

  blackboxCfg = config.services.prometheus.exporters.blackbox;
  blackboxAddress = "${blackboxCfg.listenAddress}:${toString blackboxCfg.port}";
  vmalertListenAddr = config.services.vmalert.instances."".settings."httpListenAddr";

  # scrape configs for exporters enabled on this site's hosts, reached over the wirenix mesh
  autogenScrapeConfigs = lib.flatten (
    lib.map (
      exporterName:
      let
        staticConfigs = lib.filter (sc: sc != null) (
          lib.mapAttrsToList (
            hostname: host:
            let
              exporterConfig = host.config.services.prometheus.exporters.${exporterName};
            in
            if exporterConfig.enable or false then
              {
                targets = [ "[${wgIpOf host}]:${toString exporterConfig.port}" ];
                labels = {
                  instance = hostname;
                };
              }
            else
              null
          ) (lib.filterAttrs (name: _: lib.elem name cfg.siteHosts) config.custom.flake.nixosConfigurations)
        );
      in
      lib.optional (staticConfigs != [ ]) {
        job_name = exporterName;
        static_configs = staticConfigs;
      }
    ) supportedExporters
  );

  mkProbeJob = jobName: module: targets: {
    job_name = jobName;
    metrics_path = "/probe";
    params.module = [ module ];
    static_configs = lib.mapAttrsToList (site: addr: {
      targets = [ addr ];
      labels = {
        target_site = site;
      };
    }) targets;
    relabel_configs = [
      {
        source_labels = [ "__address__" ];
        target_label = "__param_target";
      }
      {
        source_labels = [ "__param_target" ];
        target_label = "instance";
      }
      {
        target_label = "__address__";
        replacement = blackboxAddress;
      }
    ];
  };

  probeScrapeConfigs = [
    # public reachability of the other sites, seen from this site
    (mkProbeJob "blackbox_public" "icmp4" (
      lib.filterAttrs (site: _: site != cfg.siteName) cfg.probeTargets
    ))
    # wireguard tunnel health towards the other sites
    (mkProbeJob "blackbox_wg" "icmp6" (lib.genAttrs otherSites (site: siteIps.${site})))
  ];

  localExporterPorts = lib.map (e: config.services.prometheus.exporters.${e}.port) (
    lib.filter (e: config.services.prometheus.exporters.${e}.enable) supportedExporters
  );
in
{
  options.custom.monitoring = {
    enable = lib.mkEnableOption "multi-site monitoring stack (vmagent + vmsingle + vmalert + alertmanager + blackbox)";

    siteName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Name of this monitoring site, must be one of `sites`.";
    };

    sites = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "h81"
        "ampere"
        "rpi3"
      ];
      description = "Hostnames (= nixosConfigurations attribute names = wirenix peer names) of all monitoring sites.";
    };

    siteHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ config.networking.hostName ];
      description = "Hosts whose exporters this site's vmagent scrapes. Each host must be scraped by exactly one site.";
    };

    probeTargets = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Site name -> publicly reachable IP/hostname, ICMP-probed by the other sites. Values live in the private flake.";
    };

    retentionPeriod = lib.mkOption {
      type = lib.types.str;
      default = "1y";
      description = "VictoriaMetrics retention period.";
    };

    vmMemoryAllowedPercent = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Value for VictoriaMetrics -memory.allowedPercent, for low-memory hosts.";
    };

    remoteWriteMaxDiskUsage = lib.mkOption {
      type = lib.types.str;
      default = "1GB";
      description = "vmagent on-disk buffer limit per remote write URL while a peer is unreachable.";
    };

    extraScrapeConfigs = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Extra prometheus scrape_configs for this site's vmagent.";
    };

    telegram.chatId = lib.mkOption {
      type = lib.types.int;
      description = "Telegram chat id for alert notifications. Value lives in the private flake.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.elem cfg.siteName cfg.sites;
        message = "custom.monitoring.siteName (${cfg.siteName}) must be one of custom.monitoring.sites";
      }
      {
        assertion = lib.all (site: cfg.probeTargets ? ${site}) otherSites;
        message = "custom.monitoring.probeTargets must have an entry for every other site (${lib.concatStringsSep ", " otherSites})";
      }
    ];

    # vmsingle: one full copy of the data at every site, written by all three vmagents.
    # Dedup collapses the identical samples; each series has exactly one producing vmagent.
    services.victoriametrics = {
      enable = true;
      retentionPeriod = cfg.retentionPeriod;
      settings = {
        enableTCP6 = true;
        "dedup.minScrapeInterval" = "30s";
        "vmalert.proxyURL" = "http://${vmalertListenAddr}";
      }
      // lib.optionalAttrs (cfg.vmMemoryAllowedPercent != null) {
        "memory.allowedPercent" = cfg.vmMemoryAllowedPercent;
      };
    };

    services.prometheus.exporters.blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      configFile = yamlFormat.generate "blackbox.yml" {
        modules = {
          icmp4 = {
            prober = "icmp";
            timeout = "5s";
            icmp = {
              preferred_ip_protocol = "ip4";
              ip_protocol_fallback = true;
            };
          };
          icmp6 = {
            prober = "icmp";
            timeout = "5s";
            icmp = {
              preferred_ip_protocol = "ip6";
              ip_protocol_fallback = false;
            };
          };
        };
      };
    };

    services.vmagent = {
      enable = true;
      settings = {
        # remoteWrite.url only takes one URL through the module option, and the module
        # only sets tmpDataPath together with it, hence both live here
        "remoteWrite.url" = lib.map (
          site: "http://[${siteIps.${site}}]:${vmPortOfCfg (siteHost site).config}/api/v1/write"
        ) cfg.sites;
        "remoteWrite.tmpDataPath" = "/var/cache/vmagent/remote_write_tmp";
        "remoteWrite.maxDiskUsagePerURL" = cfg.remoteWriteMaxDiskUsage;
        "remoteWrite.label" = "site=${cfg.siteName}";
        httpListenAddr = "127.0.0.1:8429";
        enableTCP6 = true;
      };
      prometheusConfig = {
        global = {
          scrape_interval = "30s";
          scrape_timeout = "10s";
        };
        scrape_configs = autogenScrapeConfigs ++ probeScrapeConfigs ++ cfg.extraScrapeConfigs;
      };
    };

    services.vmalert.instances."" = {
      enable = true;
      settings = {
        "datasource.url" = "http://127.0.0.1:${vmPortOfCfg config}";
        # all alertmanagers, so any single site can deliver the notification
        "notifier.url" = lib.map (
          site:
          "http://[${siteIps.${site}}]:${toString (siteHost site).config.services.prometheus.alertmanager.port}"
        ) cfg.sites;
        "httpListenAddr" = "127.0.0.1:8880";
        enableTCP6 = true; # notifier.url and datasource dial IPv6 mesh addresses
      };
      # No -external.label: all sites hold identical data, so identical alerts
      # dedup to a single notification in the alertmanager cluster.
      rules = {
        groups = [
          {
            name = "availability";
            interval = "30s";
            rules = [
              {
                alert = "SiteDown";
                expr = ''min by (target_site) (probe_success{job="blackbox_public"}) == 0'';
                for = "3m";
                labels.severity = "critical";
                annotations.summary = "Site {{ $labels.target_site }} is unreachable from all external probers";
              }
              {
                alert = "InstanceDown";
                expr = "up == 0";
                for = "3m";
                labels.severity = "warning";
                annotations.summary = "Target {{ $labels.instance }} (job {{ $labels.job }}) is down";
              }
              {
                alert = "WireguardTunnelDown";
                expr = ''probe_success{job="blackbox_wg"} == 0'';
                for = "3m";
                labels.severity = "warning";
                annotations.summary = "WireGuard tunnel {{ $labels.site }} -> {{ $labels.target_site }} is down";
              }
            ];
          }
        ];
      };
    };

    services.prometheus.alertmanager = {
      enable = true;
      webExternalUrl = "https://alerts.avalls.dev";
      settings = {
        # the default cluster listener is IPv4-only; the mesh is IPv6
        "cluster.listen-address" = "[::]:9094";
        "cluster.advertise-address" = "[${ownWgIp}]:9094";
      };
      # the nixos module appends the (upstream-fixed) :9094 gossip port itself
      clusterPeers = lib.map (site: "[${siteIps.${site}}]") otherSites;
      configuration = {
        # defines telegram.default.message, picked up by the telegram receiver
        templates = [ "${./telegram.tmpl}" ];
        route = {
          receiver = "telegram";
          group_by = [
            "alertname"
            "target_site"
            "instance"
          ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "6h";
        };
        receivers = [
          {
            name = "telegram";
            telegram_configs = [
              {
                bot_token_file = "/run/credentials/alertmanager.service/telegram-bot-token";
                chat_id = cfg.telegram.chatId;
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };

    systemd.services.alertmanager.serviceConfig.LoadCredential = [
      "telegram-bot-token:${config.age.secrets.telegram-bot-token.path}"
    ];

    # inter-site traffic only rides the wirenix mesh; nothing is opened publicly
    networking.firewall.interfaces.${config.systemd.network.netdevs."50-metrics".netdevConfig.Name} = {
      allowedTCPPorts = [
        (lib.toInt (vmPortOfCfg config)) # vmsingle: remote-write from the other sites
        config.services.prometheus.alertmanager.port # vmalert notifications from all sites
        9094 # alertmanager gossip (fixed upstream port)
      ]
      ++ localExporterPorts;
      allowedUDPPorts = [ 9094 ]; # alertmanager gossip
    };
  };
}
