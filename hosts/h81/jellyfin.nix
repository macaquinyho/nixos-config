{ config, pkgs, ... }: {

  services.caddy.virtualHosts."jellyfin.${config.custom.homelab.primaryDomain}" = {
    extraConfig = ''
      reverse_proxy localhost:8096
    '';
  };
  services.jellyfin.enable = true;
  environment.systemPackages = [
    pkgs.jellyfin
    pkgs.jellyfin-web
    pkgs.jellyfin-ffmpeg
  ];
}
