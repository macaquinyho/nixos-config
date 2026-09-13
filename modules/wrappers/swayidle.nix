{ wlib, lib }:

wlib.wrapModule (
  { config, wlib, ... }:
  {
    options = {
      configFile = lib.mkOption {
        type = wlib.types.file config.pkgs;
        description = ''
          swayidle configuration settings file.
          See swayidle(1)
        '';
        example.content = ''
          timeout ${toString (15 * 60)} '${lib.getExe config.pkgs.swaylock} -fF'
          before-sleep '${lib.getExe config.pkgs.swaylock} -fF'
        '';
      };
    };

    config.package = lib.mkDefault config.pkgs.swayidle;
    config.flags = {
      "-C" = builtins.toString config.configFile.path;
      "-w" = true;
    };
  }
)
