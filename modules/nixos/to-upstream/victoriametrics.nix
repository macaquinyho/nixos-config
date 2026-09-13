# Adds a vmalert-style `settings` option to services.victoriametrics, rendered into extraOptions.
{ config, lib, ... }:
let
  cfg = config.services.victoriametrics;

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

  # no shell escaping: the victoriametrics module escapes extraOptions itself
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
  options.services.victoriametrics.settings = lib.mkOption {
    type = confType;
    default = { };
    example = {
      "dedup.minScrapeInterval" = "30s";
      enableTCP6 = true;
    };
    description = ''
      VictoriaMetrics configuration, passed via command line flags like
      {option}`services.vmalert.instances.<name>.settings`.
    '';
  };

  config = {
    services.victoriametrics.extraOptions = mkFlags cfg.settings;
  };
}
