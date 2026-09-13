{
  config,
  pkgs,
  lib,
  self,
  ...
}:
let
  # deadnix: skip
  nvidia-offload = pkgs.writeShellScriptBin "nvidia-offload" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec "$@"
  '';
  inherit (self.inputs) wrappers;
in
{
  imports = [ ./hardware-configuration.nix ];

  config = lib.mkMerge [
    {
      networking.hostName = "ps42"; # Define your hostname.

      specialisation = {
        kde = {
          configuration = {
            custom.desktop.blacklistnvidia.enable = true;
            custom.desktop.kde.enable = true;
            custom.desktop.flatpak.enable = true;
            environment.systemPackages = with pkgs; [
              kdePackages.kpat
              kdePackages.kio-gdrive
              x2goclient
              gimp
            ];
            i18n.defaultLocale = lib.mkDefault "ca_ES.UTF-8";
          };
        };
        # disabled
        # nvidia = {
        #   configuration = {
        #     desktop.regreet.enable = true;
        #     desktop.sway.enable = true;
        #     environment.systemPackages = [ nvidia-offload ];
        #     desktop.hyprland.enable = false;
        #     # Power management
        #     services.tlp = {
        #       enable = true;
        #       settings = {
        #         SOUND_POWER_SAVE_ON_AC = 1;
        #         SOUND_POWER_SAVE_ON_BAT = 1;
        #         RUNTIME_PM_ON_AC = "auto";
        #         PCIE_ASPM_ON_AC = "powersave";
        #         PCIE_ASPM_ON_BAT = "powersupersave";
        #       };
        #     };
        #     services.xserver.videoDrivers = [ "nvidia" ];
        #     environment.sessionVariables.WLR_DRM_DEVICES = "/dev/dri/card1";
        #     hardware.nvidia.package =
        #       config.boot.kernelPackages.nvidiaPackages.stable;
        #     hardware.nvidia = {
        #       # Modesetting is required.
        #       modesetting.enable = true;
        #       powerManagement.enable = true;
        #       nvidiaSettings = true;
        #       prime = {
        #         intelBusId = "PCI:0:2:0";
        #         nvidiaBusId = "PCI:3:0:0";
        #         offload = {
        #           enable = true;
        #          enableOffloadCmd = true;
        #        };
        #      };
        #    };
        #  };
        #};
      };

      environment.systemPackages = with pkgs; [
        powertop
        prismlauncher
      ];

      custom.common.enable = true;
      custom.desktop.enable = true;
      custom.desktop.arctis9.enable = false;
      custom.desktop.matlab.enable = false;
      custom.vm.podman.enable = true;
      #vm.libvirtd.enable = false;

      # Enable VAAPI hardware acceleration
      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          intel-media-driver
        ];
      };
      programs.firefox = {
        enable = true;
        preferences = {
          "media.ffmpeg.vaapi.enabled" = true;
        };
      };

      boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

      # Undervolt
      services.undervolt = {
        enable = true;
        coreOffset = -77;
        uncoreOffset = -20;
        gpuOffset = -30;
        analogioOffset = -20;
      };

      # Enable the IOMMU
      boot.kernelParams = [ "intel_iommu=on" ];

      virtualisation.waydroid.enable = false;

      # LTS Kernel
      #boot.kernelPackages = pkgs.linuxPackages_latest;

      # This value determines the NixOS release from which the default
      # settings for stateful data, like file locations and database versions
      # on your system were taken. It‘s perfectly fine and recommended to leave
      # this value at the release version of the first install of this system.
      # Before changing this value read the documentation for this option
      # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
      system.stateVersion = "22.11"; # Did you read the comment?
    }
    (lib.mkIf (config.specialisation != { }) {

      custom.desktop.blacklistnvidia.enable = true;
      custom.desktop.enable = true;

      # set kanshi config
      services.kanshi.package =
        let
          internal_name = "Chimei Innolux Corporation 0x14D5 Unknown";
          home_name = "Samsung Electric Company SyncMaster H1AK500000";
          ultrawide_hdmi_name = "LG Electronics LG ULTRAWIDE 0x0003BECD";
          lg_22inch_name = "LG Electronics 2D FHD LG TV 0x01010101";
        in
        (wrappers.wrapperModules.kanshi.apply {
          inherit pkgs;
          configFile.content = ''
            profile laptop {
              output "${internal_name}" enable scale 1.000000
            }

            profile desk_lid_down {
              output "${ultrawide_hdmi_name}" enable mode 2560x1080@100Hz position 0,0 adaptive_sync on
              output "${internal_name}" disable
            }

            profile home {
              output "${home_name}" enable position 280,0
              output "${internal_name}" enable position 0,768
            }

            profile home2 {
              output "${lg_22inch_name}" enable position 0,0
              output "${internal_name}" enable position 0,1080
            }

            profile desk_lid_down_2 {
              output "Ancor Communications Inc ASUS VP228 J7LMTF119528" enable position 0,0
              output "${internal_name}" disable
            }
          '';
        }).wrapper;

      users.users.arnau.packages = [ pkgs.discord ];
      custom.desktop.wm = {
        enable = true;
        greeter = "regreet";
        sway.enable = true;
        hyprland.enable = false;
        niri.enable = true;
      };
      boot.extraModprobeConfig = "options hid_apple swap_opt_cmd=1";

      custom.dev.enable = true;
      custom.vm.libvirtd.enable = true;
      custom.vm.docker.enable = true;
      custom.vfio = {
        enable = true;
        devices = [ "10de:1d10" ];
      };
      services.tlp = {
        enable = true;
        settings = {
          SOUND_POWER_SAVE_ON_AC = 1;
          SOUND_POWER_SAVE_ON_BAT = 1;
          RUNTIME_PM_ON_AC = "auto";
          PCIE_ASPM_ON_AC = "powersave";
          PCIE_ASPM_ON_BAT = "powersupersave";
        };
      };
    })
  ];

}
