{
  config,
  pkgs,
  lib,
  self,
  ...
}:
let
  DP_ultrawide = "LG Electronics LG ULTRAWIDE 0x0003BECD";
  inherit (self.inputs) wrappers;
in
{
  networking.hostName = "b450"; # Define your hostname.

  imports = [ ./hardware-configuration.nix ];

  specialisation = {
    gnome = {
      configuration = {
        custom.desktop.gnome.enable = true;
        services.gnome.gcr-ssh-agent.enable = false;
      };
    };
  };

  # Enable VAAPI hardware acceleration
  programs.firefox = {
    enable = true;
    preferences = {
      "media.ffmpeg.vaapi.enabled" = true;
    };
  };
  programs.wireshark.enable = true;

  nix.settings = {
    substituters = [
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false; # see the note above
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  services.llama-cpp = {
    enable = true;
    package = pkgs.pkgsForCudaArch.sm_70.llama-cpp;
    host = "0.0.0.0";
    openFirewall = true;
    modelsPreset = {
      "Qwen3.8-27B" = {
        hf-repo = "unsloth/Qwen3.8-27B-GGUF";
        hf-file = "Qwen3.8-27B-UD-IQ4_XS.gguf";
        alias = "unsloth/Qwen3.8-27B-GGUF";
        parallel = "1";
        ctx-size = "8192";
        n-gpu-layers = "99";
        temp = "1.0";
        top-k = "20";
        top-p = "0.95";
        min-p = "0.0";
        repeat-penalty = "1.0";
        presence-penalty = "0.0";
      };
    };
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
  };
  programs.steam.gamescopeSession.args = [
    "--adaptive-sync"
    "-R 100"
  ];
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];

  custom.common.enable = true;

  custom.vm.podman.enable = true;
  custom.vm.libvirtd.enable = true;
  custom.vm.docker.enable = false;
  custom.dev.enable = true;
  virtualisation.waydroid.enable = true;

  custom.desktop = {
    enable = true;
    wm = lib.mkIf (config.specialisation != { }) {
      enable = true;
      greeter = "regreet";
      sway.enable = true;
      hyprland.enable = false;
      niri.enable = true;
    };
    flatpak.enable = true;
    gaming = {
      enable = true;
      g29.enable = true;
    };
    arctis9.enable = true;
  };

  # programs.singularity = {
  #   enable = true;
  #   package = pkgs.apptainer;
  #   enableSuid = true;
  #   enableFakeroot = true;
  # };
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # OpenRGB
  services.hardware.openrgb.enable = true;

  # Enable the IOMMU
  boot.kernelParams = [ "amd_iommu=on" ];
  boot.loader.systemd-boot.windows = {
    "10".efiDeviceHandle = "HD1b65535a1";
  };

  custom.common.wol.enable = true;
  # LTS Kernel
  #boot.kernelPackages = pkgs.linuxPackages_latest;

  # set kanshi config
  services.kanshi.package =
    (wrappers.wrapperModules.kanshi.apply {
      inherit pkgs;
      configFile.content = ''
        profile desk_flat {
          output "${DP_ultrawide}" enable mode 2560x1080@99.943Hz position 0,0 adaptive_sync off
        }
      '';
    }).wrapper;

  users.users.arnau.packages = [ pkgs.discord ];
  users.users.arnau = {
    extraGroups = [
      "wireshark"
    ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?

}
