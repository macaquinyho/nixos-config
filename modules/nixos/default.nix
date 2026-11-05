{ lib, ... }:
{
  imports = [
    ./flake-values.nix
    ./desktop.nix
    ./de.nix
    ./virtualisation.nix
    ./common.nix
    ./homelab
    ./vfio.nix
    ./waylandWindowManagers.nix
    ./deployment.nix
    ./ci-updates.nix
    ./dev.nix
    ./gitlab-runner.nix
    ./remote-builder.nix
    ./monitoring
    ./to-upstream
    ./hetzner.nix
  ];
  custom.common.enable = lib.mkDefault true;

}
