{
  lib,
  inputs,
  packages,
}:
let
  staticArgs = { inherit inputs packages; };

  # key keeps double imports deduplicated, safe since every file gets the same args
  curried = file: {
    key = toString file;
    imports = [ (lib.modules.importApply file staticArgs) ];
  };
in
{ lib, ... }:
{
  imports = [
    ./desktop.nix
    ./de.nix
    ./virtualisation.nix
    ./common.nix
    ./homelab
    ./vfio.nix
    ./waylandWindowManagers.nix
    ./deployment.nix
    ./ci-updates.nix
    (curried ./dev.nix)
    ./gitlab-runner.nix
    ./monitoring
    ./to-upstream
    ./hetzner.nix
  ];
  custom.common.enable = lib.mkDefault true;

}
