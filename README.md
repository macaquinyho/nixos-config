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

`nixosModules.common` expects a few specialArgs: `self` (the flake defining
your `nixosConfigurations`, used for `self.packages`, `self.overlays` and
`self.inputs`), plus `nixpkgs` and `nixpkgs-unfree`. Options live under
`custom.*` and everything is off by default.

```nix
nixpkgs.lib.nixosSystem {
  specialArgs = { inherit self nixpkgs nixpkgs-unfree; };
  modules = [
    inputs.nixos-config.nixosModules.common
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
