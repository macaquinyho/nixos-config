{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.custom.smb;
  # deadnix: skip
  mkUserShares =
    baseDir: users:
    builtins.listToAttrs (
      builtins.map (userName: {
        name = userName;
        value = {
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          path = "${baseDir}/${userName}";
        };
      }) users
    );

  mkUserSharesFolders =
    baseDir: users: map (userName: "d ${baseDir}/${userName} 0700 ${userName} users - -") users;

  mkUsers =
    users:
    builtins.listToAttrs (
      builtins.map (userName: {
        name = userName;
        value = {
          isNormalUser = true;
        };
      }) users
    );

in
{
  options.custom.smb = {
    enable = lib.mkEnableOption "homelab stuff";
    userShares = {
      enable = lib.mkEnableOption "user shares homelab stuff";
      baseDir = lib.mkOption {
        type = lib.types.path;
        default = null;
        description = "Base directory for all the user shares";
      };
      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = null;
        description = "User to create shares for";
      };
    };
  };

  # manually add the passwords with smbpasswd -a my_user

  config = lib.mkIf cfg.enable {
    networking = {
      firewall.enable = true;
    };

    systemd.tmpfiles.rules =
      lib.optionals cfg.userShares.enable mkUserSharesFolders cfg.userShares.baseDir
        cfg.userShares.users;

    users.users = lib.optionalAttrs cfg.userShares.enable mkUsers cfg.userShares.users;

    services = {
      # Network shares
      samba = {
        package = pkgs.samba4Full;
        enable = true;
        openFirewall = true;
        settings = lib.optionalAttrs cfg.userShares.enable {
          personal = {
            browseable = "yes";
            path = cfg.userShares.baseDir;
            writable = "true";
          };
        };
      };
      avahi = {
        publish.enable = true;
        publish.userServices = true;
        nssmdns4 = true;
        enable = true;
        openFirewall = true;
      };
      samba-wsdd = {
        enable = true;
        openFirewall = true;
      };
    };
  };
}
