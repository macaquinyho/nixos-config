# Adds a vmalert-style `settings` option to services.prometheus.alertmanager,
# rendered into extraFlags (GNU-style --flags).
{ config, lib, ... }:
let
  cfg = config.services.prometheus.alertmanager;

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

  # escaped: the alertmanager module splices extraFlags into ExecStart unescaped
  mkFlag =
    key: value:
    if value == true then
      [ "--${key}" ]
    else if lib.isList value then
      lib.map (v: "--${key}=${lib.escapeShellArg (toString v)}") value
    else
      [ "--${key}=${lib.escapeShellArg (toString value)}" ];

  mkFlags =
    settings: lib.flatten (lib.mapAttrsToList mkFlag (lib.filterAttrs (_: v: v != false) settings));
in
{
  options.services.prometheus.alertmanager.settings = lib.mkOption {
    type = confType;
    default = { };
    example = {
      "cluster.listen-address" = "[::]:9094";
    };
    description = ''
      Alertmanager configuration, passed via command line flags like
      {option}`services.vmalert.instances.<name>.settings`.
    '';
  };

  config = {
    services.prometheus.alertmanager.extraFlags = mkFlags cfg.settings;
  };
}
