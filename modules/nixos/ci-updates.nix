{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.ci-updates;
  package = pkgs.callPackage ../../packages/nixos-ci-update { };
  exe = lib.getExe package;

  configFile = pkgs.writeText "nixos-ci-update.json" (
    builtins.toJSON {
      inherit (cfg) repoUrl branch tokenUser;
      host = config.networking.hostName;
      tokenFile = config.age.secrets.gitlab-read-token.path;
      nixStore = lib.getExe' config.nix.package "nix-store";
      dix = lib.getExe pkgs.dix;
      terminal = lib.getExe config.xdg.terminal-exec.package;
      iconThemePath = "${pkgs.nixos-icons}/share/icons";
    }
  );
in
{
  options.custom.ci-updates = {
    enable = lib.mkEnableOption "a tray icon to update to the latest commit of this flake";
    user = lib.mkOption {
      type = lib.types.str;
      default = "arnau";
      description = "User that runs the tray";
    };
    repoUrl = lib.mkOption {
      type = lib.types.str;
      description = "git+https URL of this flake";
    };
    tokenUser = lib.mkOption {
      type = lib.types.str;
      default = "oauth2";
      description = "Username for the token, a GitLab deploy token has its own";
    };
    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch to follow";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.gitlab-read-token.owner = cfg.user;
    xdg.terminal-exec.enable = true;

    systemd.user.services.nixos-ci-tray = {
      unitConfig.ConditionUser = cfg.user;
      # inherit the session's PATH, which the terminals it opens need
      environment.PATH = lib.mkForce null;
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${exe} tray ${configFile}";
        Restart = "on-failure";
      };
    };

    systemd.services."nixos-ci-switch@" = {
      # it's still running while the switch it started compares units
      restartIfChanged = false;
      path = [
        config.nix.package
        config.system.build.nixos-rebuild
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${exe} switch %i";
      };
    };

    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("verb") == "start" &&
            action.lookup("unit").indexOf("nixos-ci-switch@") == 0 &&
            subject.isInGroup("wheel")) {
          return polkit.Result.AUTH_ADMIN;
        }
        return polkit.Result.NOT_HANDLED;
      });
    '';
  };
}
