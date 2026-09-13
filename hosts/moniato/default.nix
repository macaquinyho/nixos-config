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
  ];

  networking.hostName = "moniato";

  custom.common.enable = true;
  custom.common.cloud.enable = true;
  zramSwap.enable = true;

  boot.loader.systemd-boot.enable = false;
  boot.loader.grub.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
