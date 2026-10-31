{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.awww;

  setImage = pkgs.writeShellScript "awww-set-image" ''
    until ${lib.getExe cfg.package} query >/dev/null 2>&1; do
      sleep 0.1
    done
    ${
      if cfg.directory != null then
        "image=$(${pkgs.findutils}/bin/find ${cfg.directory} -type f | ${pkgs.coreutils}/bin/shuf -n 1)"
      else
        "image=${cfg.image}"
    }
    exec ${lib.getExe cfg.package} img ${lib.escapeShellArgs cfg.imageArgs} "$image"
  '';
  hasImage = cfg.image != null || cfg.directory != null;
in
{
  options.services.awww = {
    enable = lib.mkEnableOption "awww, a Wayland wallpaper daemon";
    package = lib.mkOption {
      type = lib.types.package;
      # JPEG XL decoding is an optional cargo feature that nixpkgs leaves off.
      # The build hook reads cargoBuildFeatures, buildFeatures is only copied into it by buildRustPackage.
      default = pkgs.awww.overrideAttrs (old: {
        cargoBuildFeatures = (old.cargoBuildFeatures or [ ]) ++ [ "jxl" ];
      });
      defaultText = lib.literalExpression ''pkgs.awww with the "jxl" feature'';
      description = "The awww package to use.";
    };
    image = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Image shown on every output once the daemon is up.";
    };
    directory = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Directory of images. One is picked at random at startup and again every
        `interval`. Takes precedence over `image`.
      '';
    };
    interval = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "Time between wallpaper changes when `directory` is set, as a systemd time span.";
    };
    imageArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--transition-type"
        "none"
      ];
      description = "Extra arguments for `awww img`.";
    };
    systemd.target = lib.mkOption {
      type = lib.types.str;
      description = ''
        The systemd target that will automatically start the awww service.
      '';
      default = "graphical-session.target";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.user.services.awww = {
      unitConfig = {
        Description = "Wayland wallpaper daemon";
        Documentation = "https://codeberg.org/LGFae/awww";
        ConditionEnvironment = "WAYLAND_DISPLAY";
        PartOf = cfg.systemd.target;
        Requires = cfg.systemd.target;
        After = cfg.systemd.target;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe' cfg.package "awww-daemon";
        ExecStartPost = lib.mkIf hasImage "${setImage}";
        Restart = "always";
      };

      wantedBy = [ cfg.systemd.target ];
    };

    systemd.user.services.awww-rotate = lib.mkIf (cfg.directory != null) {
      unitConfig = {
        Description = "Pick the next wallpaper";
        ConditionEnvironment = "WAYLAND_DISPLAY";
        Requisite = "awww.service";
        After = "awww.service";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${setImage}";
      };
    };

    systemd.user.timers.awww-rotate = lib.mkIf (cfg.directory != null) {
      unitConfig.Description = "Rotate the wallpaper";
      timerConfig = {
        OnActiveSec = cfg.interval;
        OnUnitActiveSec = cfg.interval;
      };
      wantedBy = [ cfg.systemd.target ];
    };
  };
}
