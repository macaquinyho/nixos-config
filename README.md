# nixos-config

NixOS modules, packages and overlays. This is a subtree of a private repo that
holds the host configurations, so there are no `nixosConfigurations` here: what
is exposed is meant to be usable on its own.

## What is in here

| output | |
| --- | --- |
| `lib.mkCommonModule` | builds the module set from your `inputs` and `packages`, everything under `custom.*` |
| `packages` | `claude-code`, `claude-sandbox`, `mcp-victoriametrics`, `nvim-mnw` |
| `overlays` | package overrides and additions |
| `lib.mkPreCommitCheck` | the nixfmt/deadnix/flake-checker hook set |
| `devShells`, `formatter`, `checks` | |

## Using the modules

`lib.mkCommonModule` takes the `inputs` and `packages` the modules should see
(the ones of the flake defining your `nixosConfigurations`, so its overrides
apply). Modules that have not been migrated yet still read `self` from
specialArgs. Options live under `custom.*` and everything is off by default.

```nix
nixpkgs.lib.nixosSystem {
  specialArgs = { inherit self; };
  modules = [
    (inputs.nixos-config.lib.mkCommonModule {
      inherit (self) inputs packages;
    })
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
