{ lib, ... }:
let
  mkValue =
    description:
    lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      visible = false;
      inherit description;
    };
in
{
  # Values of the flake that defines the hosts, so modules can reach its inputs,
  # packages and the other hosts without specialArgs.
  options.custom.flake = {
    inputs = mkValue "inputs of the flake defining the hosts";
    packages = mkValue "packages of the flake defining the hosts, by system";
    overlays = mkValue "overlays of the flake defining the hosts";
    nixosConfigurations = mkValue "all hosts of the flake defining them, for reading their config";
  };
}
