{
  disko.devices = {
    disk = {
      root = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };
    zpool = {
      zroot = {
        type = "zpool";
        rootFsOptions = {
          acltype = "posixacl";
          atime = "off";
          compression = "zstd";
          encryption = "aes-256-gcm";
          keyformat = "passphrase";
          # keylocation = "file:///tmp/secret.key";
          keylocation = "prompt";
          recordsize = "64k";
          xattr = "sa";
          mountpoint = "none";
        };
        options = {
          ashift = "12";
        };
        postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot/root@blank$' || zfs snapshot zroot/root@blank";
        datasets = {

          "root" = {
            type = "zfs_fs";
            # options = {
            #   "com.sun:auto-snapshot" = "false";
            # };
            mountpoint = "/";
          };

          "root/nix" = {
            type = "zfs_fs";
            # options = {
            #   "com.sun:auto-snapshot" = "false";
            # };
            mountpoint = "/nix";
          };

          "root/home" = {
            type = "zfs_fs";
            # options = {
            #   "com.sun:auto-snapshot" = "true";
            # };
            mountpoint = "/home";
          };

          "root/var" = {
            type = "zfs_fs";
            # options = {
            #   "com.sun:auto-snapshot" = "true";
            # };
            mountpoint = "/var";
          };

        };
      };
    };
  };
}
