{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop;
  g29init = pkgs.writeShellScriptBin "g29init" ''
    ${pkgs.coreutils-full}/bin/sleep 8
    ${pkgs.oversteer}/bin/oversteer --range 300
  '';
  # deadnix: skip
  matlab-wrapped = pkgs.writeShellScriptBin "matlab" ''
    exec env MESA_GL_VERSION_OVERRIDE=3.0 ${pkgs.matlab}/bin/matlab
  '';
in
{
  options.custom.desktop = {
    enable = lib.mkEnableOption "common stuff for desktop systems";
    arctis9.enable = lib.mkEnableOption "Arctis9 support";
    flatpak.enable = lib.mkEnableOption "Flatpak support";
    gaming.enable = lib.mkEnableOption "gaming stuff";
    gaming.g29.enable = lib.mkEnableOption "G29 wheel support";
    matlab.enable = lib.mkEnableOption "MATLAB";
    blacklistnvidia.enable = lib.mkEnableOption "Whether to disable and hide all detected Nvidia GPUs";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      programs.appimage = {
        enable = true;
        binfmt = true;
      };

      programs.ssh = {
        enableAskPassword = true;
        askPassword = "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";
      };

      services.fwupd.enable = true;
      fonts = {
        fontconfig.defaultFonts = {
          emoji = [ "Noto Color Emoji" ];
          sansSerif = [ "Noto Sans" ];
          serif = [ "Noto Serif" ];
          monospace = [ "Noto Sans Mono" ];
        };

        packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
        ];
      };

      programs.nix-ld.enable = true;
      services.envfs.enable = true;

      # qt = {
      #   enable = true;
      #   style = "adwaita-dark";
      # };
      # environment.sessionVariables = {
      #   QT_STYLE_OVERRIDE = "adwaita-dark";
      # };

      environment.systemPackages =
        with pkgs;
        [
          vulkan-tools
          mesa-demos
          libva-utils
          yt-dlp
          xdg-utils
          lm_sensors
          android-tools
        ]
        ++ [
          pkgs.adw-gtk3
          pkgs.papirus-icon-theme
          pkgs.adwaita-icon-theme
        ];

      environment.etc =
        let
          themeAttr = {
            Settings = {
              gtk-cursor-theme-name = "Adwaita";
              gtk-font-name = "sans 11";
              gtk-icon-theme-name = "Papirus-Dark";
              gtk-theme-name = "adw-gtk3-dark";
            };
          };
        in
        {
          "xdg/gtk-2.0/gtkrc".text = ''
            gtk-cursor-theme-name = "Adwaita"
            gtk-font-name = "sans 11"
            gtk-icon-theme-name = "Papirus-Dark"
            gtk-theme-name = "adw-gtk3-dark
          '';
          "xdg/gtk-3.0/settings.ini".text = lib.generators.toINI { } themeAttr;
          "xdg/gtk-4.0/settings.ini".text = lib.generators.toINI { } themeAttr;
        };

      programs.localsend.enable = true;

      # Enable networking
      systemd.network.enable = lib.mkForce false;
      networking.useNetworkd = lib.mkForce false;
      # Use NetworkManager + resolved for desktop systems
      networking.networkmanager.enable = true;
      services.resolved.enable = true;

      # Printing
      services.printing.enable = true;
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };

      # Tailscale
      services.tailscale.enable = true;
      # tailscale remembers the last state
      systemd.services.tailscaled.preStop = ''
        ${config.services.tailscale.package}/bin/tailscale down
      '';

      systemd.user.services.tailscale-systray = {
        unitConfig = {
          Description = "Official Tailscale systray application for Linux";
          After = [
            "graphical-session.target"
          ];
          PartOf = [ "graphical-session.target" ];
        };
        wantedBy = [ "graphical-session.target" ];
        serviceConfig.ExecStart = "${lib.getExe config.services.tailscale.package} systray";
      };

      # OpenGL
      hardware.graphics.enable = true;

      # PipeWire
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
        wireplumber.enable = true;
      };
      services.pulseaudio.enable = false;

      # Bluetooth
      hardware.bluetooth.enable = true;
      hardware.bluetooth.powerOnBoot = false;

      # Firefox
      programs.firefox = {
        enable = true;
        preferences = {
          "browser.fullscreen.autohide" = false;
          "pdfjs.defaultZoomValue" = "page-fit";
        };
      };
      programs.chromium = {
        enable = false;
        # doesn't work with chromium
        # extensions = [
        #   "alhmbbnlcggfcjjfihglopfopcbigmil;https://clients2.google.com/service/update2/crx" # waincognito
        #   "cjpalhdlnbpafiamejdnhcphjbkeiagm;https://clients2.google.com/service/update2/crx" # ublock origin
        #   "mdjildafknihdffpkfmmpnpoiajfjnjd;https://clients2.google.com/service/update2/crx" # consent O matic
        #   "gbkeegbaiigmenfmjfclcdgdpimamgkj;https://clients2.google.com/service/update2/crx" # docs offline
        #   "nngceckbapebfimnlniiiahkandclblb;https://clients2.google.com/service/update2/crx" # bitwarden
        # ];
        defaultSearchProviderEnabled = true;
        defaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}&{google:RLZ}{google:originalQueryForSuggestion}{google:assistedQueryStats}{google:searchFieldtrialParameter}{google:searchClient}{google:sourceId}{google:instantExtendedEnabledParameter}ie={inputEncoding}";
        defaultSearchProviderSuggestURL = "https://www.google.com/complete/search?output=chrome&q={searchTerms}";
        extraOpts = {
          "SearchSuggestEnabled" = true;
          "RestoreOnStartup" = 1;
          "PasswordManagerEnabled" = false;
          "SpellcheckEnabled" = false;
          "WebAppInstallForceList" = [
            {
              "custom_name" = "WhatsApp";
              "create_desktop_shortcut" = true;
              "default_launch_container" = "window";
              "url" = "https://web.whatsapp.com";
            }
            {
              "custom_name" = "Google Chat";
              "create_desktop_shortcut" = true;
              "default_launch_container" = "window";
              "url" = "https://mail.google.com";
            }
          ];
        };
      };

    })
    (lib.mkIf cfg.arctis9.enable {
      # Arctis 9
      services.udev.extraRules = ''
        KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1038", ATTRS{idProduct}=="12c2", TAG+="uaccess"
      '';
      environment.systemPackages = with pkgs; [ headsetcontrol ];

    })
    (lib.mkIf cfg.flatpak.enable {
      services.flatpak.enable = true;
      # Ugly hack to add remote
      systemd.user.services."flatpak-remote-add" =
        let
          name = "flathub";
          location = builtins.fetchurl {
            url = "https://dl.flathub.org/repo/flathub.flatpakrepo";
            sha256 = "sha256:0fm0zvlf4fipqfhazx3jdx1d8g0mvbpky1rh6riy3nb11qjxsw9k";
          };
        in
        {
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/run/current-system/sw/bin/flatpak remote-add --user --if-not-exists ${name} ${location}";
          };
        };

    })
    (lib.mkIf cfg.gaming.enable {
      environment.systemPackages = with pkgs; [
        legendary-gl
        dxvk
        heroic
        gamescope
        obs-studio
        protonup-qt
        prismlauncher
      ];

      programs.gamemode.enable = true;
      #Steam
      programs.steam = {
        enable = true;
        gamescopeSession.enable = true;
        remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
        dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      };

    })
    (lib.mkIf cfg.gaming.g29.enable {
      environment.systemPackages = [
        pkgs.oversteer
        pkgs.at
        g29init
      ];
      services.atd.enable = true;

      hardware.new-lg4ff.enable = true;
      services.udev.packages = with pkgs; [ oversteer ];
      #TODO try with a systemd service, https://unix.stackexchange.com/questions/436666/run-service-after-ttyusb0-becomes-available
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="hid", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c24f", RUN+="${pkgs.at}/bin/at -M -f ${g29init}/bin/g29init now"
      '';

    })
    (lib.mkIf cfg.blacklistnvidia.enable {
      boot.extraModprobeConfig = ''
        blacklist nouveau
        options nouveau modeset=0
      '';

      services.udev.extraRules = ''
        # Remove NVIDIA USB xHCI Host Controller devices, if present
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
        # Remove NVIDIA USB Type-C UCSI devices, if present
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
        # Remove NVIDIA Audio devices, if present
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
        # Remove NVIDIA VGA/3D controller devices
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
      '';
      boot.blacklistedKernelModules = [
        "nouveau"
        "nvidia"
        "nvidia_drm"
        "nvidia_modeset"
      ];
    })
  ];
}
