{
  config,
  lib,
  pkgs,
  flake-root,
  private,
  ...
}:
let
  hostname = config.networking.hostName;
  cfg = config.custom.secrets;
in
{
  options.custom.secrets.enable = lib.mkEnableOption "Enable secrets";
  config = lib.mkIf cfg.enable {
    age.rekey = {
      masterIdentities = [
        {
          identity = /${private}/secrets/masterident/age-yubikey-identity-key.age;
          pubkey = /${private}/secrets/masterident/age-yubikey-identity-key.pub;
        }
        {
          identity = /${private}/secrets/masterident/age-yubikey-identity-fort.age;
          pubkey = /${private}/secrets/masterident/age-yubikey-identity-fort.pub;
        }
      ];
      storageMode = "local";
      localStorageDir = flake-root + "/private/secrets/rekeyed/${hostname}";
      generatedSecretsDir = flake-root + "/private/secrets/generated";
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
    };
    environment.systemPackages = [ pkgs.agenix-rekey ];

  };
}
