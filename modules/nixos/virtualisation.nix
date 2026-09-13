{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.custom.vm;
in
{
  options.custom.vm = {
    podman.enable = lib.mkEnableOption "podman";
    docker.enable = lib.mkEnableOption "Docker";
    libvirtd.enable = lib.mkEnableOption "libvirtd";
  };

  config = {
    environment.systemPackages =
      lib.optional cfg.podman.enable pkgs.podman-compose
      ++ lib.optional cfg.libvirtd.enable pkgs.virtio-win
      ++ lib.optional cfg.docker.enable pkgs.docker-compose;
    virtualisation = {
      podman = {
        enable = cfg.podman.enable;
        dockerCompat = false;
        defaultNetwork.settings.dns_enabled = true;
      };
      docker.enable = cfg.docker.enable;
    };

    virtualisation = {
      libvirtd = {
        enable = cfg.libvirtd.enable;
        qemu = {
          swtpm.enable = true;
        };
      };
    };
  };

}
