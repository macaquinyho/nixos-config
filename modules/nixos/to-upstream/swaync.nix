{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    ;

  cfg = config.services.swaync;

in
{

  options.services.swaync = {
    enable = lib.mkEnableOption "Swaync notification daemon";

    package = lib.mkPackageOption pkgs "swaynotificationcenter" { };

    systemd.target = mkOption {
      type = types.str;
      default = "graphical-session.target";
      description = ''
        The systemd target that will automatically start the Swaync service.
      '';
    };

  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [ cfg.package ];

    systemd.user.services.swaync = {
      unitConfig = {
        Description = "Swaync notification daemon";
        Documentation = "https://github.com/ErikReider/SwayNotificationCenter";
        PartOf = [ cfg.systemd.target ];
        After = [ cfg.systemd.target ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };

      serviceConfig = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = "${lib.getExe cfg.package}";
        Restart = "on-failure";
      };

      wantedBy = [ cfg.systemd.target ];
    };
  };
}
