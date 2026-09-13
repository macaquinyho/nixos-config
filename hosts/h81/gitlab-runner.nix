{
  private,
  config,
  pkgs,
  lib,
  ...
}:
{

  # age.secrets.gitlab-runner = {
  #   rekeyFile = /${private}/secrets/age/runner-h81.age;
  #   owner = "gitlab-runner";
  #   group = "gitlab-runner";
  # };
  #
  # users.users."gitlab-runner" = {
  #   group = "gitlab-runner";
  #   isSystemUser = true;
  # };
  #
  # users.groups."gitlab-runner" = { };
  #
  # systemd.services.gitlab-runner.serviceConfig = {
  #   DynamicUser = lib.mkForce false;
  #   User = "gitlab-runner";
  #   Group = "gitlab-runner";
  # };
  #
  # services.gitlab-runner = {
  #   enable = true;
  #   services = {
  #     nix = {
  #       authenticationTokenConfigFile = config.age.secrets.gitlab-runner.path;
  #       executor = "shell";
  #     };
  #
  #   };
  # };
  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.nix = {
      enable = true;
      name = config.networking.hostName;
      labels = [
        "debian-latest:docker://trixie-slim"
        "nix-x86_64-linux:host"
      ];
      url = "https://codeberg.org";
      tokenFile = config.age.secrets.gitea-actions.path;
      hostPackages = lib.mkOptionDefault [ pkgs.nix ];
    };
  };
  age.secrets.gitea-actions = {
    rekeyFile = /${private}/secrets/age/codeberg-runner-h81.age;
    owner = "root";
    group = "root";
  };
}
