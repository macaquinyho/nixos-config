# Adds a vmalert-style `settings` option to services.vmagent, rendered into extraArgs.
{ config, lib, ... }:
let
  cfg = config.services.vmagent;

  confType =
    with lib.types;
    let
      valueType = oneOf [
        bool
        int
        path
        str
      ];
    in
    attrsOf (either valueType (listOf valueType));

  # no shell escaping: the vmagent module escapes extraArgs itself
  mkFlag =
    key: value:
    if value == true then
      [ "-${key}" ]
    else if lib.isList value then
      lib.map (v: "-${key}=${toString v}") value
    else
      [ "-${key}=${toString value}" ];

  mkFlags =
    settings: lib.flatten (lib.mapAttrsToList mkFlag (lib.filterAttrs (_: v: v != false) settings));
in
{
  options.services.vmagent.settings = lib.mkOption {
    type = confType;
    default = { };
    example = {
      "remoteWrite.url" = [ "http://127.0.0.1:8428/api/v1/write" ];
      enableTCP6 = true;
    };
    description = ''
      `vmagent` configuration, passed via command line flags like
      {option}`services.vmalert.instances.<name>.settings`.
    '';
  };

  config = {
    services.vmagent.extraArgs = mkFlags cfg.settings;
  };
}
