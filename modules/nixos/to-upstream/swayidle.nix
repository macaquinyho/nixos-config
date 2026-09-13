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

  cfg = config.services.swayidle;

in
{

  options.services.swayidle = {
    enable = lib.mkEnableOption "idle manager for Wayland";

    package = lib.mkPackageOption pkgs "swayidle" { };

    systemd.target = mkOption {
      type = types.str;
      default = "graphical-session.target";
      description = ''
        The systemd target that will automatically start the Kanshi service.
      '';
    };

  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [ cfg.package ];

    systemd.user.services.swayidle = {
      unitConfig = {
        Description = "Idle manager for Wayland";
        Documentation = "man:swayidle(1)";
        ConditionEnvironment = "WAYLAND_DISPLAY";
        PartOf = [ cfg.systemd.target ];
        After = [ cfg.systemd.target ];
      };

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        # swayidle executes commands using "sh -c", so the PATH needs to contain a shell.
        Environment = [ "PATH=${lib.makeBinPath [ pkgs.bash ]}" ];
        ExecStart = "${lib.getExe cfg.package}";
      };

      wantedBy = [ cfg.systemd.target ];
    };
  };
}
