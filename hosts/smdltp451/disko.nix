{
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/persistent".neededForBoot = true;

  disko.devices = {
    disk.main = {
      device = "/dev/disk/by-id/nvme-INTEL_SSDPEKNW010T8_PHNH211502W31P0B";
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
              mountOptions = [ "umask=0077" ];
            };
          };
          swap = {
            size = "16G";
            content = {
              type = "swap";
              randomEncryption = true;
              resumeDevice = false;
              priority = 100;
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              # passphrase from install stays in slot 0 as fallback
              enrollFido2 = true;
              enrollRecovery = false;
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };

    zpool.zroot = {
      type = "zpool";
      options.ashift = "12";
      rootFsOptions = {
        mountpoint = "none";
        compression = "zstd";
        atime = "off";
        xattr = "sa";
        acltype = "posixacl";
      };

      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
          options = {
            atime = "off";
            compression = "zstd";
            xattr = "sa";
            acltype = "posixacl";
          };
          postCreateHook = ''
            zfs list -t snapshot -H -o name | grep -qE '^zroot/root@blank$' \
              || zfs snapshot zroot/root@blank
          '';
        };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options = {
            atime = "off";
            compression = "zstd";
            xattr = "sa";
            acltype = "posixacl";
          };
        };
        persistent = {
          type = "zfs_fs";
          mountpoint = "/persistent";
          options = {
            atime = "off";
            compression = "zstd";
            xattr = "sa";
            acltype = "posixacl";
          };
        };
      };
    };
  };
}
