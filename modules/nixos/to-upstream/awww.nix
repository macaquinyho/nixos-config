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
    exec ${lib.getExe cfg.package} img ${lib.escapeShellArgs cfg.imageArgs} ${cfg.image}
  '';
in
{
  options.services.awww = {
    enable = lib.mkEnableOption "awww, a Wayland wallpaper daemon";
    package = lib.mkPackageOption pkgs "awww" { };
    image = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Image shown on every output once the daemon is up.";
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
        ExecStartPost = lib.mkIf (cfg.image != null) "${setImage}";
        Restart = "always";
      };

      wantedBy = [ cfg.systemd.target ];
    };
  };
}
