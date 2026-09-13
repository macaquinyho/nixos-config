{
  config,
  pkgs,
  lib,
  flake-root,
  private,
  self,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./hass.nix
    ./jellyfin.nix
    ./gitlab-runner.nix
  ];

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "h81";

  virtualisation.vmVariant = {
    # following configuration is added only when building VM with build-vm
    virtualisation = {
      memorySize = 4096;
      cores = 4;
    };
  };

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "zstorage" ];
  boot.zfs.forceImportRoot = false;
  networking.hostId = "e0684fdb";
  programs.dconf.enable = true;

  custom.dev.enable = true;
  custom.gitlab-runner.enable = true;
  custom.homelab = {
    enable = true;
    serviceDataDir = "/zstorage/data";
  };
  custom.immich.enable = true;
  custom.smb = {
    enable = true;
    userShares = {
      enable = true;
      baseDir = "/zstorage/share/personal";
    };
  };
  # custom.vm.docker.enable = true;
  custom.vm.libvirtd.enable = true;
  custom.vm.podman.enable = true;

  # enable sanoid templates
  custom.homelab.sanoid.enable = true;
  services.sanoid.datasets = {
    "zstorage/share".use_template = [ "storage" ];
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
  };
  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = [ "routable" ];
      script = ''
        #!${pkgs.runtimeShell}
        ${lib.getExe pkgs.ethtool} -K enp3s0 rx-udp-gro-forwarding on rx-gro-list off
      '';
    };
  };

  wirenix = {
    enable = true;
    configurer = "networkd"; # defaults to "static", could also be "networkd"
    keyProviders = [ "agenix-rekey" ]; # could also be ["agenix-rekey"] or ["acl" "agenix-rekey"]
  };

  services.prometheus.exporters = {
    node = {
      enable = true;
    };
    smartctl = {
      enable = true;
    };
  };

  custom.monitoring.enable = true;

  environment.systemPackages = [ pkgs.yt-dlp ];

  networking.firewall.allowedUDPPorts = [ 25826 ];
  networking.firewall.allowedTCPPorts = [ 5201 ];

  security.polkit.enable = true;

  services.silverbullet = {
    enable = true;

  };

  services.caddy.virtualHosts."silverbullet.${config.custom.homelab.primaryDomain}" = {
    extraConfig = ''
      reverse_proxy localhost:${toString config.services.silverbullet.listenPort}
    '';
  };

  nixpkgs.config.packageOverrides = pkgs: {
    intel-vaapi-driver = pkgs.intel-vaapi-driver.override {
      enableHybridCodec = true;
    }; # i5-4590 is Haswell Refresh, supports intel-hybrid-driver
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-vaapi-driver # LIBVA_DRIVER_NAME=i965 Haswell does not support intel-media-driver
    ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
