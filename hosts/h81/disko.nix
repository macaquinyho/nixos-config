{
  disko.devices = {
    disk = {
      vdb = {
        device = "/dev/disk/by-id/ata-CT500MX500SSD1_1822E14161FB";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              name = "ESP";
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              name = "nixos";
              size = "100%";
              content = {
                type = "filesystem";
                format = "btrfs";
                mountpoint = "/";
              };
            };
          };
        };
      };
      # disko is a bit buggy with zfs, maybe in a few years hehe
      #wd0 = {
      #  type = "disk";
      #  device = "/dev/disk/by-id/ata-WDC_WD1003FZEX-00K3CA0_WD-WCC6Y0FY88S0";
      #  content = {
      #    type = "gpt";
      #    partitions = {
      #      zfs = {
      #        size = "100%";
      #        content = {
      #          type = "zfs";
      #          pool = "zstorage";
      #        };
      #      };
      #    };
      #  };
      #};
      #wd1 = {
      #  type = "disk";
      #  device = "/dev/disk/by-id/ata-WDC_WD1003FZEX-00K3CA0_WD-WCC6Y1JRYHZU";
      #  content = {
      #    type = "gpt";
      #    partitions = {
      #      zfs = {
      #        size = "100%";
      #        content = {
      #          type = "zfs";
      #          pool = "zstorage";
      #        };
      #      };
      #    };
      #  };
      #};
    };
    #zpool = {
    #  zstorage = {
    #    type = "zpool";
    #    mode = "mirror";
    #    rootFsOptions = {
    #      compression = "zstd";
    #      mountpoint = "none";
    #    };

    #    datasets = {
    #      data = {
    #        type = "zfs_fs";
    #        options.mountpoint = "/zstorage/data";
    #      };
    #      share = {
    #        type = "zfs_fs";
    #        options.mountpoint = "/zstorage/share";
    #      };
    #      backup = {
    #        type = "zfs_fs";
    #        options.mountpoint = "/zstorage/backup";
    #      };
    #    };
    #  };
    #};
  };
}
