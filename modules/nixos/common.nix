{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.custom.common;
  ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
in
{
  options.custom.common = {
    enable = lib.mkEnableOption "common stuff";
    cloud.enable = lib.mkEnableOption "minimal setup for cloud vms";
    wol.enable = lib.mkEnableOption "Enable Wake On LAN via udev rules";
    trustedUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether arnau is a trusted nix user. When off, the claude sandbox gets the nix daemon.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # populate branch name/commit hash
      system.configurationRevision = toString (
        self.rev or self.shortRev or self.dirtyShortRev or self.lastModified or "unknown"
      );
      nix = {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          builders-use-substitutes = true;
        };
        optimise = {
          dates = "03:00";
          automatic = true;
        };
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 15d";
          persistent = true;
        };
      };
      nixpkgs.overlays = [
        self.overlays.modifications
        self.inputs.agenix-rekey.overlays.default
      ];
      nixpkgs.flake.setNixPath = !cfg.cloud.enable;
      nixpkgs.flake.setFlakeRegistry = !cfg.cloud.enable;

      systemd.network.enable = true;
      networking.useNetworkd = true;

      # Set your time zone.
      time.timeZone = "Europe/Madrid";

      # enabling chrony disables systemd-timesyncd
      services.chrony.enable = true;

      # Select internationalisation properties.
      i18n = {
        supportedLocales = [
          "ca_ES.UTF-8/UTF-8"
          "en_US.UTF-8/UTF-8"
        ];
        defaultLocale = "en_US.UTF-8";
        extraLocaleSettings = {
          LC_NUMERIC = "ca_ES.UTF-8";
          LC_TIME = "ca_ES.UTF-8";
          LC_MONETARY = "ca_ES.UTF-8";
          LC_PAPER = "ca_ES.UTF-8";
          LC_NAME = "ca_ES.UTF-8";
          LC_ADDRESS = "ca_ES.UTF-8";
          LC_TELEPHONE = "ca_ES.UTF-8";
          LC_MEASUREMENT = "ca_ES.UTF-8";
        };
      };

      # Configure keymap in X11
      services.xserver = {
        xkb.layout = "es";
        xkb.variant = "cat";
      };
      # Configure console keymap
      # https://github.com/NixOS/nixpkgs/issues/257904
      # console = {
      #   font = "${pkgs.terminus_font}/share/consolefonts/ter-124b.psf.gz";
      #   useXkbConfig = true;
      #   # packages = with pkgs; [ terminus_font ];
      # };

      # Allow unfree packages
      nixpkgs.config.allowUnfree = true;

      # List packages installed in system profile. To search, run:
      # $ nix search wget
      environment.systemPackages = with pkgs; [
        vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
        wget
        pciutils
        fastfetch.minimal
        usbutils
        htop
        just
        dig
        iperf3
        tree
        unzip
        borgbackup
        rsync
        tmux
        traceroute
        mtr
      ];

      # Enable the OpenSSH daemon.
      services.openssh.enable = true;
      programs.ssh.startAgent = true;

      #Allow all VPN traffic routing
      networking.firewall.checkReversePath = "loose";

      boot.loader.systemd-boot.enable = lib.mkDefault true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.systemd-boot.configurationLimit = 10;
      boot.loader.grub.configurationLimit = 10;
      boot.loader.generic-extlinux-compatible.configurationLimit = 10;

      users.groups.users.gid = 100;
      users.users.arnau = {
        uid = 1000;
        group = "users";
        isNormalUser = true;
        description = "Arnau";
        extraGroups = ifTheyExist [
          "networkmanager"
          "wheel"
          "adbusers"
          "libvirtd"
          "docker"
          "dialout"
        ];

        shell = pkgs.bash;
      };
      programs.starship.enable = !cfg.cloud.enable;
      programs.fzf.fuzzyCompletion = !cfg.cloud.enable;
      programs.fzf.keybindings = !cfg.cloud.enable;

      security.pam = {
        services = {
          sudo.u2fAuth = true;
          login.u2fAuth = true;
          greetd.u2fAuth = true;
          sudo.rssh = true;
        };
        u2f.settings = {
          enable = true;
          cue = true;
          origin = "pam://arnau";
        };
      };

      # pam_rssh
      security.pam.rssh.enable = true;

      nix.settings.trusted-users = lib.mkIf cfg.trustedUser [ "arnau" ];
    })
    (lib.mkIf cfg.cloud.enable {
      services.fail2ban = {
        enable = true;
        maxretry = 5;
        bantime-increment.enable = true;
      };
      networking.firewall.logRefusedConnections = false;
      # Harden SSH
      services.openssh = {
        settings = {
          X11Forwarding = false;
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
          MaxSessions = 2;
          MaxAuthTries = 3;
          ClientAliveCountMax = 2;
          # AllowTcpForwarding = "no";
          AllowAgentForwarding = "yes";
          AllowStreamLocalForwarding = "no";
          AuthenticationMethods = "publickey";
          TCPKeepAlive = "no";
        };
      };
      boot.kernelParams = [
        # Disable auditing
        "audit=0"
        # Do not generate NIC names based on PCIe addresses (e.g. enp1s0, useless for VPS)
        # Generate names based on orders (e.g. eth0)
        "net.ifnames=0"
      ];
    })
    (lib.mkIf cfg.wol.enable {
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="net", NAME=="en*",, RUN+="${lib.getExe pkgs.ethtool} -s $name wol g"
      '';
    })
    (lib.mkIf config.wirenix.enable {
      # wg CLI for inspecting the mesh (handshakes, endpoints, transfer)
      environment.systemPackages = [ pkgs.wireguard-tools ];
      # open each wirenix listen port so public peers can reach us; NAT'd
      # peer-to-peer links survive on conntrack, but a public peer's handshake
      # arrives as a fresh inbound and is dropped otherwise
      networking.firewall.allowedUDPPorts = lib.pipe config.systemd.network.netdevs [
        (lib.filterAttrs (_: nd: (nd.netdevConfig.Kind or null) == "wireguard"))
        (lib.mapAttrsToList (_: nd: nd.wireguardConfig.ListenPort or null))
        (lib.filter (p: p != null))
      ];
    })

  ];
}
