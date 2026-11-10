{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.gitlab-runner;

  gitconfig = pkgs.writeText "gitlab-runner-gitconfig" ''
    [filter "lfs"]
    	clean = git-lfs clean -- %f
    	smudge = git-lfs smudge -- %f
    	process = git-lfs filter-process
    	required = true
  '';
in
{
  options.custom.gitlab-runner.enable = lib.mkEnableOption "GitLab Runner with the shell executor";

  config = lib.mkIf cfg.enable {
    age.secrets.gitlab-runner = {
      owner = "gitlab-runner";
      group = "gitlab-runner";
    };
    age.secrets.ci-deploy-ssh-key = {
      owner = "gitlab-runner";
      generator.script =
        { pkgs, file, ... }:
        ''
          tmp=$(mktemp -d)
          ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C gitlab-ci-deploy -f "$tmp/key"
          cp "$tmp/key.pub" ${lib.escapeShellArg (lib.removeSuffix ".age" file + ".pub")}
          cat "$tmp/key"
          rm -r "$tmp"
        '';
    };

    # the deploy job's ssh pins each target's key under its name
    programs.ssh.knownHosts =
      lib.mapAttrs
        (name: c: {
          hostNames = [ name ];
          inherit (c.config.custom.deployment) publicKey;
        })
        (lib.filterAttrs (_: c: c.config.custom.deployment.enable) config.custom.flake.nixosConfigurations);

    users.users.gitlab-runner = {
      group = "gitlab-runner";
      isSystemUser = true;
      home = "/var/lib/gitlab-runner";
      createHome = true;
      # System users default to nologin, and the executor logs in as this user.
      shell = pkgs.bashInteractive;
      # Jobs run in a login shell, so tooling comes from here, not the unit PATH.
      packages = with pkgs; [
        git
        git-lfs
      ];
    };
    users.groups.gitlab-runner = { };

    # Without the lfs filters this user's checkouts leave pointer files on disk.
    systemd.tmpfiles.settings.gitlab-runner = {
      "/var/lib/gitlab-runner/.gitconfig"."L+".argument = "${gitconfig}";
    };

    systemd.services.gitlab-runner.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "gitlab-runner";
      Group = "gitlab-runner";
    };

    services.gitlab-runner = {
      enable = true;
      services.nix = {
        authenticationTokenConfigFile = config.age.secrets.gitlab-runner.path;
        executor = "shell";
      };
    };
  };
}
