{
  # checkout the example folder for how to configure different disko layouts
  disko.devices = {
    disk.sda = {
      device = "/dev/disk/by-id/ata-CT500MX500SSD1_2048E4D353BD";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            type = "EF00";
            size = "1G";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          swap = {
            type = "8200";
            size = "2G";
            content.type = "swap";
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
