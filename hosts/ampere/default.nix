{
  config,
  pkgs,
  lib,
  nixpkgs,
  modulesPath,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    # Minimal stuff
    (modulesPath + "/profiles/minimal.nix")
    # ./minecraft.nix
    ./disko.nix
  ];

  networking.hostName = "ampere";

  # zfs required stuff
  services.zfs.autoScrub.enable = true;
  networking.hostId = "ba6f9367";
  boot.loader.systemd-boot.netbootxyz.enable = true;

  custom.common.enable = true;
  custom.common.cloud.enable = true;
  custom.gitlab-runner.enable = true;
  custom.vm.podman.enable = true;
  security.polkit.enable = true;

  wirenix = {
    enable = true;
    configurer = "networkd"; # defaults to "static", could also be "networkd"
    keyProviders = [ "agenix-rekey" ]; # could also be ["agenix-rekey"] or ["acl" "agenix-rekey"]
  };
  custom.monitoring.enable = true;
  services.prometheus.exporters.node.enable = true;

  services.caddy = {
    enable = true;
    virtualHosts = {
      "metrics.avalls.dev" = {
        extraConfig = ''
          reverse_proxy localhost:${lib.removePrefix ":" config.services.victoriametrics.listenAddress}
        '';
      };
      "alerts.avalls.dev" = {
        extraConfig = ''
          reverse_proxy localhost:${toString config.services.prometheus.alertmanager.port}
        '';
      };
    };
  };

  services.silverbullet = {
    enable = true;
    package = nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.silverbullet;
  };

  services.tailscale = {
    openFirewall = true;
    enable = true;
    extraUpFlags = [
      "--accept-dns=false"
      "--accept-routes=false"
      "--login-server=${config.services.headscale.settings.server_url}"
    ];
    authKeyFile = config.age.secrets.tailscale.path;
    # authKeyParameters = {
    #   preauthorized = true;
    #   # baseURL = config.services.headscale.settings.server_url;
    # };
    useRoutingFeatures = "both";
  };

  age.secrets.tailscale = {
    owner = "root";
    group = "root";
  };

  services.immich = {
    enable = true;
    openFirewall = true;
    host = "0.0.0.0";
  };
  services.ollama = {
    enable = true;
    package = nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.ollama;
  };

  # services.caddy.virtualHosts."silverbullet.${config.custom.homelab.primaryDomain}" = {
  #   extraConfig = ''
  #     reverse_proxy localhost:${config.services.silverbullet.listenPort}
  #   '';
  # };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
