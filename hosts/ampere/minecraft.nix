{
  config,
  pkgs,
  lib,
  self,
  ...
}:
{
  imports = [ self.inputs.nix-minecraft.nixosModules.minecraft-servers ];
  nixpkgs.overlays = [ self.inputs.nix-minecraft.overlay ];

  # Minecraft server settings
  users.users.arnau.extraGroups = [ config.services.minecraft-servers.group ];
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;
    servers.fabric = {
      enable = true;
      # Specify the custom minecraft server package
      package = pkgs.fabricServers.fabric-1_21_4;

      symlinks = {
        mods = pkgs.linkFarmFromDrvs "mods" (
          builtins.attrValues {
            FerriteCore = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/uXXizFIs/versions/IPM0JlHd/ferritecore-7.1.1-fabric.jar";
              sha512 = "f41dc9e8b28327a1e29b14667cb42ae5e7e17bcfa4495260f6f851a80d4b08d98a30d5c52b110007ee325f02dac7431e3fad4560c6840af0bf347afad48c5aac";
            };
            FabricAPI = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/UnrycCWP/fabric-api-0.115.1%2B1.21.4.jar";
              sha512 = "d5e9f87679b5edc9786e651fc481f8861a9cf53ed381890a1cb5e129222d6c5fa99f06045007f8e1fba02da686cdb6db2d99b334a1d23881cb56dfa199932eea";
            };
            Lithium = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/QCuodIia/lithium-fabric-0.14.7%2Bmc1.21.4.jar";
              sha512 = "7acb62dca4879ed665c81e81ccbaa6b26a73a0862dfcae5f6f8b1b0f89fd63554712c596fb235902b4359c0baed23d56bd36f2f4bdd81a7c1680a22c168ba8b9";
            };
            C2ME = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/VSNURh3q/versions/Qgg5mpR6/c2me-fabric-mc1.21.4-0.3.2%2Balpha.0.33.jar";
              sha512 = "7987368136c098844366c03da077b91df404b092c5ef6c2f91c199a3555dcb4d20b1e4bfb469b9a09343665aed9d34c8a48d5fb963f14eaa79c5e306d6d424e3";
            };
            NoChatReports = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/qQyHxfxd/versions/9xt05630/NoChatReports-FABRIC-1.21.4-v2.11.0.jar";
              sha512 = "d343b05c8e50f1de15791ff622ad44eeca6cdcb21e960a267a17d71506c61ca79b1c824167779e44d778ca18dcbdebe594ff234fbe355b68d25cdb5b6afd6e4f";
            };
            Krypton = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/fQEb0iXm/versions/Acz3ttTp/krypton-0.2.8.jar";
              sha512 = "5f8cf96c79bfd4d893f1d70da582e62026bed36af49a7fa7b1e00fb6efb28d9ad6a1eec147020496b4fe38693d33fe6bfcd1eebbd93475612ee44290c2483784";
            };
          }
        );
      };
    };
  };
}
