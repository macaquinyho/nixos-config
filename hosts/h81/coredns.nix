{ ... }:
{

  # Disable stub resolver to not conflict with coredns
  services.resolved.enable = false;
  networking.resolvconf.useLocalResolver = true;

  services.coredns = {
    enable = true;
  };

  virtualisation.containers = {
    containersConf.settings = {
      network = {
        dns_bind_port = 1153;
      };
    };
  };
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];
}
