{ config, lib, ... }:

let
  cfg = config.custom.networking.hcloud;
in
{
  options.custom.networking.hcloud = {
    enable = lib.mkEnableOption "Hetzner Cloud networking";
    ipv6Address = lib.mkOption {
      type = lib.types.str;
      description = "Public IPv6 address with prefix (e.g. fdf4:9a90:3fca:f482::1/64)";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.useDHCP = false;
    systemd.network.enable = true;

    # Map PCI paths to stable interface names (wan, net0, net1, net2)
    systemd.network.links = {
      "10-hcloud-wan" = {
        matchConfig.Path = [
          "pci-0000:00:03.0"
          "pci-0000:01:00.0"
        ];
        linkConfig.Name = "wan";
      };
      "10-hcloud-net0" = {
        matchConfig.Path = [
          "pci-0000:00:0a.0"
          "pci-0000:07:00.0"
        ];
        linkConfig.Name = "net0";
      };
      "10-hcloud-net1" = {
        matchConfig.Path = [
          "pci-0000:00:0b.0"
          "pci-0000:08:00.0"
        ];
        linkConfig.Name = "net1";
      };
      "10-hcloud-net2" = {
        matchConfig.Path = [
          "pci-0000:00:0c.0"
          "pci-0000:09:00.0"
        ];
        linkConfig.Name = "net2";
      };
    };

    systemd.network.networks = {
      "10-wan" = {
        matchConfig.Name = "wan";
        # Hetzner does not support DHCPv6, so we always only request DHCPv4
        networkConfig.DHCP = "ipv4";

        # Apply static IPv6 config
        address = [ cfg.ipv6Address ];
        routes = [
          {
            Gateway = "fe80::1";
            GatewayOnLink = true;
          }
        ];
      };

      # Match all private networks
      "20-lan" = {
        matchConfig.Name = "net*";
        # Private networks are ipv4 only
        networkConfig.DHCP = "ipv4";
        linkConfig.MTUBytes = 1450;
      };
    };
  };
}
