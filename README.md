# nixos-config

NixOS modules, packages and overlays. This is a subtree of a private repo that
holds the host configurations, so there are no `nixosConfigurations` here: what
is exposed is meant to be usable on its own.

## What is in here

| output | |
| --- | --- |
| `nixosModules.common` | the module set, everything under `custom.*` |
| `packages` | `claude-code`, `claude-sandbox`, `mcp-victoriametrics`, `nvim-mnw` |
| `overlays` | package overrides and additions |
| `lib.mkPreCommitCheck` | the nixfmt/deadnix/flake-checker hook set |
| `devShells`, `formatter`, `checks` | |

## Using the modules

`nixosModules.common` reads the flake that defines your hosts through the
read-only `custom.flake.{inputs,packages,overlays,nixosConfigurations}`
options, so set them to your flake's values. Options live under `custom.*` and
everything is off by default.

```nix
nixpkgs.lib.nixosSystem {
  modules = [
    inputs.nixos-config.nixosModules.common
    { custom.flake = { inherit (self) inputs packages overlays nixosConfigurations; }; }
    ./configuration.nix
  ];
}
```

## Setting up the environment

### Flakes
```bash
nix develop
```
### No flakes
```bash
nix-shell
```
