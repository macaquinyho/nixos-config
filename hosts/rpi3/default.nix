{
  config,
  nixpkgs,
  pkgs,
  lib,
  self,
  modulesPath,
  ...
}:
let

in
{
  imports = [
    #./hardware-configuration.nix
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    # Minimal stuff
    (modulesPath + "/profiles/minimal.nix")
    ./hass.nix
  ];

  networking.hostName = "rpi3"; # Define your hostname.
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  environment.systemPackages = [
    pkgs.libraspberrypi
    pkgs.borgbackup
  ];

  custom.common.enable = true;
  boot.loader.systemd-boot.enable = false;
  hardware.enableRedistributableFirmware = true;
  boot.supportedFilesystems.zfs = lib.mkForce false;
  services.tailscale = {
    openFirewall = true;
    enable = true;
    extraUpFlags = [
      "--accept-dns=false"
      "--accept-routes=false"
      "--login-server=${self.nixosConfigurations.potato.config.services.headscale.settings.server_url}"
      "--advertise-exit-node"
      "--advertise-routes=10.1.0.0/21"
    ];
    authKeyFile = config.age.secrets.tailscale.path;
    useRoutingFeatures = "both";
  };
  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = [ "routable" ];
      script = ''
        #!${pkgs.runtimeShell}
        DEV="$(${pkgs.iproute2}/bin/ip --json route show default | ${lib.getExe pkgs.jq} .[0].dev -r)"
        ${lib.getExe pkgs.ethtool} -K "$DEV" rx-udp-gro-forwarding on rx-gro-list off
      '';
    };
  };

  # Use the extlinux boot loader.
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  zramSwap.enable = true;

  networking.useDHCP = lib.mkDefault true;

  services.prometheus.exporters = {
    node = {
      enable = true;
    };
  };

  custom.monitoring = {
    enable = true;
    retentionPeriod = "30d";
    vmMemoryAllowedPercent = 50;
    remoteWriteMaxDiskUsage = "256MB";
  };
  # keep victoriametrics from starving the 1GB Pi
  systemd.services.victoriametrics.serviceConfig = {
    MemoryHigh = "384M";
    MemoryMax = "512M";
  };
  # spare the SD card
  fileSystems."/".options = [
    "defaults"
    "noatime"
  ];
  zramSwap.memoryPercent = 100;

  wirenix = {
    enable = true;
    configurer = "networkd"; # defaults to "static", could also be "networkd"
    keyProviders = [ "agenix-rekey" ]; # could also be ["agenix-rekey"] or ["acl" "agenix-rekey"]
  };

  # ACT LED off between 23:00 and 07:00
  systemd.services.act-led-night = {
    description = "Set ACT LED state based on time of day";
    path = [ pkgs.coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      h=$(date +%H)
      if [ "$h" -ge 23 ] || [ "$h" -lt 7 ]; then
        echo none > /sys/class/leds/ACT/trigger
        echo 0    > /sys/class/leds/ACT/brightness
      else
        echo heartbeat > /sys/class/leds/ACT/trigger
      fi
    '';
    wantedBy = [ "multi-user.target" ];
  };
  services.netbird = {
    clients = {
      wt0.port = 51825;
    };
  };
  systemd.timers.act-led-night = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = [
        "*-*-* 23:00:00"
        "*-*-* 07:00:00"
      ];
      Persistent = true;
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
