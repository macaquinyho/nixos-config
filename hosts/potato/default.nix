{
  config,
  pkgs,
  lib,
  nixpkgs,
  modulesPath,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    # Minimal stuff
    (modulesPath + "/profiles/minimal.nix")
    ./disko.nix
    (modulesPath + "/profiles/qemu-guest.nix") # Do NOT remove, for some reason nixos-generate-config doesn't detect qemu-guest in gcloud e2 micro
  ];

  networking.hostName = "potato";

  custom.common.enable = true;
  custom.common.cloud.enable = true;
  boot.kernelParams = [ "console=ttyS0,115200n8" ];
  zramSwap.enable = true;
  environment.systemPackages = [ pkgs.cloud-utils ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
