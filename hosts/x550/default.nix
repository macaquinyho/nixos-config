{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "x550";

  environment.systemPackages = with pkgs; [
    onlyoffice-desktopeditors
    vlc
    tenacity
    kdePackages.ark
    kdePackages.skanpage
    kdePackages.krfb
    kdePackages.kpat
    libreoffice-qt
    hunspell
    hunspellDicts.es-es
    lmms
    chromium
    kdePackages.okular
    mpv
    kdePackages.spectacle
    kdePackages.elisa
    kdePackages.dragon
    virt-manager
  ];

  # aliza ms

  i18n.defaultLocale = lib.mkForce "ca_ES.UTF-8";

  custom.common.enable = true;
  custom.desktop.enable = true;
  custom.desktop.kde.enable = true;
  custom.desktop.flatpak.enable = true;
  custom.vm.libvirtd.enable = true;

  # Enable VAAPI hardware acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-vaapi-driver ];
  };

  # Undervolt
  services.undervolt = {
    enable = true;
    coreOffset = -50;
    gpuOffset = -10;
    uncoreOffset = 0;
    analogioOffset = 0;
  };

  virtualisation.vmVariant = {
    # following configuration is added only when building VM with build-vm
    virtualisation = {
      memorySize = 8096; # Use 2048MiB memory.
      cores = 4;
    };
  };
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
