{
  config,
  pkgs,
  lib,
  self,
  ...
}:
let
  inherit (self.inputs) wrappers;
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "smdltp451";
  networking.hostId = "91e31b44";

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.kernelParams = [ "nohibernate" ];

  services.envfs.enable = lib.mkForce false;

  # /etc/machine-id is a symlink into /persistent point the commit
  # service at the persistent location instead of the bind-mount default
  systemd.services.systemd-machine-id-commit = {
    unitConfig.ConditionPathIsMountPoint = [
      ""
      "/persistent/etc/machine-id"
    ];
    serviceConfig.ExecStart = [
      ""
      "systemd-machine-id-setup --commit --root /persistent"
    ];
  };

  boot = {

    plymouth = {
      enable = true;
    };

    initrd = {
      # required in initrd for cryptsetup FIDO2 unlock
      systemd.enable = true;
      # Enable "Silent boot"
      verbose = false;
      # wipe / by rolling back to the empty @blank snapshot before mount
      systemd.services.rollback = {
        description = "Rollback root to blank snapshot";
        wantedBy = [ "initrd.target" ];
        after = [ "zfs-import-zroot.service" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = "zfs rollback -r zroot/root@blank";
      };
    };
    # Hide the OS choice for bootloaders.
    # It's still possible to open the bootloader list by pressing any key
    # It will just not appear on screen unless a key is pressed
    loader.timeout = 0;

  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  preservation = {
    enable = true;
    preserveAt."/persistent" = {
      directories = [
        "/var/log"
        "/var/lib/bluetooth"
        "/var/lib/systemd"
        "/var/lib/NetworkManager"
        "/etc/NetworkManager/system-connections"
        "/etc/ceph"
        "/var/lib/docker"
        "/var/lib/containers"
        "/var/lib/libvirt"
        "/var/lib/systemd/pstore"
        "/var/lib/tailscale"
        "/var/db/sudo/lectured"
        {
          directory = "/var/lib/nixos";
          inInitrd = true;
        }
        "/var/lib/systemd/timers"
        {
          directory = "/var/log/journal";
          inInitrd = true;
        }
        "/var/lib/systemd/coredump"
      ];
      files = [
        {
          file = "/etc/machine-id";
          inInitrd = true;
          configureParent = true;
        }
        {
          file = "/etc/ssh/ssh_host_ed25519_key";
          mode = "0600";
        }
        {
          file = "/etc/ssh/ssh_host_ed25519_key.pub";
          mode = "0644";
        }
        {
          file = "/etc/ssh/ssh_host_rsa_key";
          mode = "0600";
        }
        {
          file = "/etc/ssh/ssh_host_rsa_key.pub";
          mode = "0644";
        }
      ];

      users.arnau = {
        files = [
          ".claude.json"
          ".bash_history"
          ".git-credentials"
          ".viminfo"
          ".zsh_history"
        ];
        directories = [
          # XDG base dirs
          ".cache"
          ".local/share"
          ".local/state"
          ".local/bin"

          # XDG_CONFIG_HOME (selective)
          ".config/mozilla"
          ".config/chromium"
          ".config/Code"
          ".config/gh"
          ".config/glab-cli"
          ".config/gitlab"
          ".config/sops"
          # ".config/git"            # programs.git already manages this
          # ".config/github-copilot"
          # ".config/libvirt"
          # ".config/obs-studio"
          # ".config/remmina"
          # ".config/keepassxc"
          # ".config/Signal"
          # ".config/discord"
          # ".config/systemd/user"

          # non-XDG
          ".ssh"
          "projects"
          "Documents"
          "Pictures"
          "Videos"
          "Downloads"
          "Music"
          ".claude"
          # ".gnupg"
          # ".mozilla"              # Firefox < 147
        ];
      };
    };
  };

  custom.desktop.enable = true;
  custom.desktop.wm = {
    enable = true;
    greeter = "regreet";
    niri.enable = true;
  };
  custom.dev.enable = true;

  services.greetd.settings.initial_session = {
    command = "${config.programs.niri.package}/bin/niri-session";
    user = "arnau";
  };

  custom.vm.podman.enable = true;
  custom.vm.docker.enable = false;
  custom.vm.libvirtd.enable = true;

  programs.winbox = {
    enable = true;
    package = pkgs.winbox4;
    openFirewall = true;
  };

  services.auto-cpufreq.enable = true;

  # Enable VAAPI hardware acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };
  programs.firefox = {
    enable = true;
    preferences = {
      "media.ffmpeg.vaapi.enabled" = true;
    };
  };

  zramSwap = {
    enable = true;
    priority = 200;
  };

  #boot.kernelPackages = pkgs.linuxPackages_latest;

  users.users.arnau.packages = with pkgs; [
    tigervnc
    xpra
  ];
  programs.wireshark.enable = true;
  users.users.arnau = {
    extraGroups = [
      "wireshark"
    ];
  };

  services.kanshi.package =
    let

      home_name = "Samsung Electric Company SyncMaster H1AK500000";
      ultrawide_hdmi_name = "LG Electronics LG ULTRAWIDE 0x0003BECD";
      internal_name = "Samsung Display Corp. 0x417B Unknown";
      workplace_name = "ASUSTek COMPUTER INC VG34VQEL1A S4LMDW002954";
      # Output "Samsung Display Corp. 0x417B Unknown" (eDP-1)
      #   Current mode: 2880x1800 @ 60.001 Hz (preferred)
      #   Variable refresh rate: not supported
      #   Physical size: 290x190 mm
      #   Logical position: 3640, 0
      #   Logical size: 1440x900
      #   Scale: 2
      #   Transform: normal
      #   Available modes:
      #     2880x1800@60.001 (current, preferred)
    in
    (wrappers.wrapperModules.kanshi.apply {
      inherit pkgs;
      configFile.content = ''
        profile laptop {
          output "${internal_name}" enable scale 2.000000
        }

        profile workplace {
          output "${workplace_name}" enable mode 3440x1440@75Hz position 1440,0 scale 1.25
          output "${internal_name}" enable position 0,540 scale 2.0
          exec ${lib.getExe config.programs.niri.package} msg action move-workspace-to-monitor --reference "" "${internal_name}"
          exec ${lib.getExe config.programs.niri.package} msg action move-workspace-to-monitor --reference "" "${workplace_name}"
          exec ${lib.getExe config.programs.niri.package} msg action move-workspace-to-monitor --reference "" "${workplace_name}"
        }

        profile workspace {
          output "${ultrawide_hdmi_name}" enable mode 2560x1080@100Hz position 1440,0 adaptive_sync on
          output "${internal_name}" enable position 0,540 scale 2.0
          exec ${lib.getExe config.programs.niri.package} msg action move-workspace-to-monitor --reference "" "${internal_name}"
          exec ${lib.getExe config.programs.niri.package} msg action move-workspace-to-monitor --reference "" "${ultrawide_hdmi_name}"
          exec ${lib.getExe config.programs.niri.package} msg action move-workspace-to-monitor --reference "" "${ultrawide_hdmi_name}"
        }

        profile home {
          output "${home_name}" enable position 280,0
          output "${internal_name}" enable position 0,768
          exec ${lib.getExe config.programs.niri.package} msg action move-workspace-to-monitor --reference "" "${home_name}"
        }
      '';
    }).wrapper;

  system.stateVersion = "24.05";
}
