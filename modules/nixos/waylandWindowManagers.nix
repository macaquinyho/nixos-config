{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.custom.desktop.wm;

  inherit (self.inputs) wrappers;
  userName = "arnau";

  desktopPackages = with pkgs; [
    (wrappers.wrapperModules.foot.apply {
      inherit pkgs;
      settings = {
        main = {
          font = "monospace:size=12";
          dpi-aware = "yes";
        };
        colors = {
          background = "242424";
          foreground = "ffffff";
        };
      };
    }).wrapper
    (wrappers.wrapperModules.mpv.apply {
      inherit pkgs;
      scripts = [ pkgs.mpvScripts.mpris ];
      "mpv.conf".content = ''
        vo=gpu
        hwdec=auto
      '';
      "input.conf".content = ''
        WHEEL_UP seek 10
        WHEEL_DOWN seek -10
      '';
    }).wrapper
    (wrappers.wrapperModules.alacritty.apply {
      inherit pkgs;
      settings = {
        window.opacity = 1;
        font = {
          normal = {
            family = "monospace";
            style = "Regular";
          };
          size = 13;
        };
      };
    }).wrapper
    gnome-disk-utility
    pwvucontrol
    gnome-calculator
    scrcpy
    virt-manager
    # (ungoogled-chromium.override {
    #   commandLineArgs = [ "--enable-features=TouchpadOverscrollHistoryNavigation" ];
    #   enableWideVine = true;
    # })
    resources
    localsend
    masterpdfeditor4
    wireshark
    numbat
    wayvnc
    wl-clipboard
    brightnessctl
  ];
  fuzzelWrapped =
    (wrappers.wrapperModules.fuzzel.apply {
      inherit pkgs;
      settings = {
        main = {
          font = "sans";
          dpi-aware = "auto";
          icon-theme = "Papirus-Dark";
          terminal = "alacritty --class xdgterminal -e";
        };
        colors = {
          background = "00000080";
          text = "ffffffff";
          match = "cb4b16ff";
          selection = "00fffaff";
          selection-text = "000000ff";
          border = "00fffaff";
        };
      };
    }).wrapper;
  swaylockWrapped =
    (wrappers.wrapperModules.swaylock.apply {
      inherit pkgs;
      settings = {
        daemonize = true;
        show-failed-attempts = true;
      };
    }).wrapper;
  swayidleWrapped =
    (
      (import ../../modules/wrappers/swayidle.nix {
        inherit lib;
        wlib = wrappers.lib;
      }).apply
        {
          inherit pkgs;
          configFile.content = ''
            timeout ${toString (15 * 60)} '${lib.getExe swaylockWrapped}'
            before-sleep '${lib.getExe swaylockWrapped}'
            lock '${lib.getExe swaylockWrapped}'
          '';
        }
    ).wrapper;
  set-wallpaper = pkgs.writeShellApplication {
    name = "set-wallpaper";
    text = ''
      ${lib.getExe pkgs.swaybg} -i ${../../wallpapers/fuji.png} -o "*" &
    '';
  };
  fuzzelPowerMenu = pkgs.writeShellApplication {
    name = "fuzzelpowermenu";
    runtimeInputs = [
      fuzzelWrapped
    ];
    text = ''
      options="  Power Off
        Reboot
        Suspend
        Log Out
        Lock
        Reboot to UEFI
        Reboot to Windows"

      chosen=$(echo -e "$options" | fuzzel --no-exit-on-keyboard-focus-loss --dmenu --font="mono:size=20")

      case "$chosen" in
      "  Power Off")
              systemctl poweroff
              ;;
      "  Reboot")
              systemctl reboot
              ;;
      "  Suspend")
              systemctl suspend
              ;;
      "  Log out")
              loginctl terminate-session "$XDG_SESSION_ID"
              ;;
      "  Lock")
              loginctl lock-session
              ;;
      "  Reboot to UEFI")
              systemctl reboot --firmware-setup
              ;;
      "  Reboot to Windows")
              systemctl reboot --boot-loader-entry=auto-windows
              ;;
      *) ;;
      esac
    '';

  };
  niri-wrapped =
    (wrappers.wrapperModules.niri.apply {
      inherit pkgs;
      "config.kdl".content = builtins.readFile ./niri.kdl;
    }).wrapper;
  waybar-wrapped =
    (wrappers.wrapperModules.waybar.apply {
      inherit pkgs;
      "style.css".content = builtins.readFile ./waybar-style.css;
      settings = {
        layer = "top";
        height = 30;
        spacing = 1;
        modules-left = [
          "niri/workspaces"
          "niri/window"
        ];
        modules-center = [ ];
        modules-right = [
          "tray"
          "pulseaudio"
          "network"
          "cpu"
          "memory"
          "temperature"
          "backlight"
          "battery"
          "clock"
          "custom/power"
        ];
        "keyboard-state" = {
          "numlock" = true;
          "capslock" = true;
          "format" = "{name} {icon}";
          "format-icons" = {
            "locked" = "";
            "unlocked" = "";
          };
        };
        "sway/mode" = {
          "format" = ''<span style="italic">{}</span>'';
        };
        "sway/window" = {
          "format" = "{title}";
          "max-length" = 50;
          "icon" = true;
        };
        "niri/window" = {
          "format" = "{title}";
          "max-length" = 50;
          "icon" = true;
        };
        "river/window" = {
          "max-length" = 50;
        };
        "hyprland/window" = {
          "format" = "{}";
          "separate-outputs" = true;
          "max-length" = 200;
        };
        "tray" = {
          "spacing" = 10;
        };
        "clock" = {
          "format" = "{:%d/%m/%y %H:%M}  ";
          "format-alt" = "{:%A, %B %d, %Y (%R)}";
          "tooltip-format" = "<tt><small>{calendar}</small></tt>";
          "calendar" = {
            "mode" = "year";
            "mode-mon-col" = 3;
            "weeks-pos" = "right";
            "on-scroll" = 1;
            "format" = {
              "months" = "<span color='#ffead3'><b>{}</b></span>";
              "days" = "<span color='#ecc6d9'><b>{}</b></span>";
              "weeks" = "<span color='#99ffdd'><b>W{}</b></span>";
              "weekdays" = "<span color='#ffcc66'><b>{}</b></span>";
              "today" = "<span color='#ff6699'><b><u>{}</u></b></span>";
            };
          };
          "actions" = {
            "on-click-right" = "mode";
            "on-click-forward" = "tz_up";
            "on-click-backward" = "tz_down";
            "on-scroll-up" = "shift_up";
            "on-scroll-down" = "shift_down";
          };
        };
        "cpu" = {
          "format" = " {usage}% ";
        };
        "memory" = {
          "format" = "{}% ";
        };
        "temperature" = {
          "critical-threshold" = 80;
          "format" = "{temperatureC}°C {icon}";
          "format-icons" = [
            ""
            ""
            ""
          ];
        };
        "backlight" = {
          "format" = "{percent}% {icon}";
          "format-icons" = [
            ""
            ""
          ];
        };
        "battery" = {
          "states" = {
            "warning" = 30;
            "critical" = 15;
          };
          "format" = "{capacity}% {icon}";
          "format-charging" = "{capacity}% ";
          "format-plugged" = "{capacity}% ";
          "format-alt" = "{time} {icon}";
          "format-icons" = [
            ""
            ""
            ""
            ""
            ""
          ];
        };
        "network" = {
          "format-wifi" = "{essid} ({signalStrength}%) ";
          "format-ethernet" = "{ipaddr}/{cidr} ";
          "tooltip-format" = "{ifname} via {gwaddr} ";
          "format-linked" = "{ifname} (No IP) ";
          "format-disconnected" = "Disconnected ⚠";
          "format-alt" = "{ifname}: {ipaddr}/{cidr}";
        };
        "pulseaudio" = {
          "format" = "{volume}% {icon} {format_source}";
          "format-bluetooth" = "{volume}% {icon} {format_source}";
          "format-bluetooth-muted" = " {icon} {format_source}";
          "format-muted" = " {format_source}";
          "format-source" = "{volume}% ";
          "format-source-muted" = "";
          "format-icons" = {
            "headphone" = "";
            "hands-free" = "";
            "headset" = "";
            "phone" = "";
            "portable" = "";
            "car" = "";
            "default" = [
              ""
              ""
              ""
            ];
          };
          "on-click" = "${lib.getExe pkgs.pwvucontrol}";
        };
        "custom/power" = {
          "format" = "";
          "on-click" = "${lib.getExe fuzzelPowerMenu}";
        };
      };
    }).wrapper;
in
{
  options.custom.desktop.wm = {
    enable = lib.mkEnableOption "opinionated wms";
    sway.enable = lib.mkEnableOption "Sway and common desktop services";
    niri.enable = lib.mkEnableOption "niri";
    hyprland.enable = lib.mkEnableOption "Hyprland";

    greeter = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "regreet"
          "tuigreet"
          "cosmic"
        ]
      );
      default = null;
      description = "Which greeter to enable.";
    };
  };

  config = lib.mkIf cfg.enable {
    #fonts

    fonts = {
      fontconfig.defaultFonts = {
        monospace = [ "Iosevka Nerd Font Mono" ];
        sansSerif = [ "Rubik" ];
      };

      packages = with pkgs; [
        rubik
        font-awesome
        nerd-fonts.iosevka
      ];
    };
    xdg.portal = lib.optionalAttrs cfg.sway.enable {
      enable = true;
      # gtk portal needed to make gtk apps happy
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-wlr
      ];
    };
    environment.etc."xdg/user-dirs.defaults".text = ''
      DESKTOP=Desktop
      DOCUMENTS=Documents
      DOWNLOAD=Downloads
      MUSIC=Music
      PICTURES=Pictures
      PUBLICSHARE=Public
      TEMPLATES=Templates
      VIDEOS=Videos
    '';
    xdg.mime = {

      defaultApplications = {
        "application/pdf" = "firefox.desktop";
        "inode/directory" = "thunar.desktop";
        "application/zip" = "org.gnome.FileRoller.desktop";
        "text/html" = [ "firefox.desktop" ];
        "x-scheme-handler/http" = [ "firefox.desktop" ];
        "x-scheme-handler/https" = [ "firefox.desktop" ];
        "x-scheme-handler/about" = [ "firefox.desktop" ];
        "x-scheme-handler/unknown" = [ "firefox.desktop" ];
        "video/x-matroska" = "mpv.desktop";
        "image/png" = "firefox.desktop";
        "x-scheme-handler/terminal" = "Alacritty.desktop";
      };

      addedAssociations = {
        "image/png" = "firefox.desktop";
        "video/x-matroska" = "mpv.desktop";
        "application/pdf" = "firefox.desktop";
        "x-scheme-handler/terminal" = "Alacritty.desktop";
      };
    };

    programs.hyprland.enable = cfg.hyprland.enable;
    programs.niri.enable = cfg.niri.enable;
    programs.niri.package = niri-wrapped;

    # niri attaches to xdg-desktop-autostart.target and this masks it
    systemd.user.targets.xdg-desktop-autostart.enable = true;

    # Sway
    programs.sway = {
      enable = cfg.sway.enable;
      wrapperFeatures.gtk = true;
      extraOptions = [ "--unsupported-gpu" ];
      extraPackages = [ ];
    };

    services.kanshi.enable = true;

    programs.dconf = {
      enable = true;
      profiles.user.databases = [
        {
          lockAll = true;
          settings = {
            # removes close button from gtk apps
            "org/gnome/desktop/wm/preferences" = {
              button-layout = "appmenu";
            };

            "org/gnome/desktop/interface" = {
              color-scheme = "prefer-dark";
              gtk-theme = "adw-gtk3-dark";
              icon-theme = "Papirus-Dark";
              cursor-theme = "Adwaita";
              font-name = "sans 11";
            };
          };
        }
      ];
    };
    environment.systemPackages =
      with pkgs;
      [
        wayland
        xwininfo
        sway
        adw-gtk3
        adwaita-icon-theme
        waypipe
        nautilus
        file-roller
        fuzzelWrapped
        set-wallpaper
        swaylockWrapped
      ]
      ++ desktopPackages
      ++ lib.optional (cfg.niri.enable) pkgs.xwayland-satellite;

    programs.nm-applet.enable = true;
    programs.waybar = {
      enable = true;
      package = waybar-wrapped;
    };
    # replaces polkit gnome
    security.soteria = {
      enable = true;
    };

    services.swayidle = {
      enable = true;
      package = swayidleWrapped;
    };
    services.swaync.enable = true;

    programs.thunar = {
      enable = true;
      plugins = with pkgs; [
        thunar-archive-plugin
        thunar-volman
        thunar-media-tags-plugin
      ];
    };
    # Enable wayland in electron apps
    environment.sessionVariables.NIXOS_OZONE_WL = "1";
    # Enable wayland in firefox
    environment.sessionVariables.MOZ_ENABLE_WAYLAND = "1";
    # Fix Java apps in WMs
    environment.sessionVariables._JAVA_AWT_WM_NONREPARENTING = "1";

    # For Gnome Disks
    services.udisks2.enable = true;

    services.gnome.gcr-ssh-agent.enable = false;

    # For auto mounting in Nautilus and Thunar
    services.gvfs.enable = true;
    services.dbus.enable = true;

    # Don’t shutdown when power button is short-pressed
    services.logind.settings.Login = {
      HandlePowerKey = "ignore";
    };
    services.blueman.enable = true;

    security.pam.services.gtklock = { };
    security.pam.services.hyprlock = { };
    security.pam.services.waylock = { };
    security.pam.services.swaylock = { };

    services.displayManager.cosmic-greeter.enable = cfg.greeter == "cosmic";

    # buggy https://github.com/rharish101/ReGreet/issues/45
    programs.regreet = {
      enable = cfg.greeter == "regreet";
      cageArgs = [
        "-s"
        "-m"
        "last"
      ];
      font = {
        package = pkgs.rubik;
        name = "Rubik";
        size = 12;
      };
      settings = {
        background = {
          fit = "Cover";
          path = ../../assets/lockscreen.png;

        };
        GTK = {
          application_prefer_dark_theme = true;
        };
      };
    };

    # Stolen from https://github.com/sjcobb2022/nixos-config/blob/aa74d65ebb9ec49316b1f3a693176ae37381712e/hosts/common/optional/greetd.nix
    services.greetd = {
      enable = (cfg.greeter != null);
      settings = lib.optionalAttrs (cfg.greeter == "tuigreet") {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --remember-session";
          user = "greeter";
        };
      };
    };

    systemd.services.greetd.serviceConfig = lib.mkIf (cfg.greeter == "tuigreet") {
      Type = "idle";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "journal"; # Without this errors will spam on screen
      # Without these bootlogs will spam on screen
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
    };

    # silverbullet socket
    systemd.user.sockets.ssh-tunnel-proxy = {
      unitConfig = {
        Description = "Socket-activation for SSH-tunnel";
        ConditionUser = userName;
      };
      socketConfig.ListenStream = [
        "127.0.0.1:3000"
        "[::1]:3000"
      ];
      wantedBy = [ "sockets.target" ];
    };
    systemd.user.services =
      let
        silverbulletPort = toString self.nixosConfigurations.ampere.config.services.silverbullet.listenPort;
        inherit (self.nixosConfigurations.ampere.config.custom.deployment) port user hostname;
        remoteHost = "${user}@${hostname} -p ${toString port}";
      in
      {
        ssh-tunnel = {
          unitConfig = {
            Description = "Tunnel to SSH server";
            ## Stop-when-idle is controlled by `--exit-idle-time=` in proxy.service
            #  (from `man systemd-socket-proxyd`)
            StopWhenUnneeded = true;
            ConditionUser = userName;
          };
          serviceConfig = {
            Type = "notify";
            NotifyAccess = "all";
            ## Prefixed with `-` not to mark service as failed on net-fails;
            #  will be restarted on-demand by socket-activation.
            ExecStart = ''-${pkgs.openssh}/bin/ssh -kaxNT  -o ExitOnForwardFailure=yes -o ControlMaster=no -o StreamLocalBindUnlink=yes -o PermitLocalCommand=yes -o LocalCommand="systemd-notify --ready" ${remoteHost} -L ''${XDG_RUNTIME_DIR}/ssh-tunnel-proxy:localhost:${silverbulletPort}'';

          };
        };

        ssh-tunnel-proxy = {
          unitConfig = {
            Description = "Socket-activation proxy for SSH tunnel";
            ConditionUser = userName;
            ## Stop also when stopped listening for socket-activation.
            ## Stop also when ssh-tunnel stops/breaks
            #  (otherwise, could not restart).
            BindsTo = [
              "ssh-tunnel-proxy.socket"
              "ssh-tunnel.service"
            ];
            After = [
              "ssh-tunnel-proxy.socket"
              "ssh-tunnel.service"
            ];
          };
          serviceConfig = {
            ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=500s \${XDG_RUNTIME_DIR}/ssh-tunnel-proxy";
          };
        };
      };
  };
}
