#!/usr/bin/env -S just --justfile
set unstable
commonRemoteOpts := "--use-substitutes"

gitadd:
  git add . && cd private && git add . && cd -

default:
  @just --list

deploy HOSTNAME: gitadd
  deploy .#{{HOSTNAME}} --skip-checks

deployremote HOSTNAME: gitadd
  deploy .#{{HOSTNAME}} --skip-checks --remote-build

switch hostname="" buildhost=hostname: gitadd
  nixos-rebuild switch --flake .#{{hostname && hostname }} \
    {{ hostname && ("--target-host " + hostname) }} \
    {{ buildhost  && ("--build-host " + buildhost) }} \
    {{ hostname && commonRemoteOpts }} --sudo

boot hostname="" buildhost=hostname: gitadd
  nixos-rebuild boot --flake .#{{hostname && hostname }} \
    {{ hostname && ("--target-host " + hostname) }} \
    {{ buildhost  && ("--build-host " + buildhost) }} \
    {{ hostname && commonRemoteOpts }} --sudo

test hostname="" buildhost=hostname: gitadd
  nixos-rebuild test --flake .#{{hostname && hostname }} \
    {{ hostname && ("--target-host " + hostname) }} \
    {{ buildhost  && ("--build-host " + buildhost) }} \
    {{ hostname && commonRemoteOpts }} --sudo

build hostname="" buildhost=hostname: gitadd
  nixos-rebuild build --flake .#{{hostname && hostname }} \
    {{ hostname && ("--target-host " + hostname) }} \
    {{ buildhost  && ("--build-host " + buildhost) }} \
    {{ hostname && commonRemoteOpts }}

dry-build hostname="": gitadd
  nixos-rebuild dry-build --flake .#{{hostname}}

dry-activate hostname="" buildhost=hostname: gitadd
  nixos-rebuild dry-activate --flake .#{{hostname && hostname }} \
    {{ hostname && ("--target-host " + hostname) }} \
    {{ buildhost  && ("--build-host " + buildhost) }} \
    {{ hostname && commonRemoteOpts }} --sudo

droid: gitadd
  nix-on-droid switch --flake .

update:
  nix flake update

cleangen:
  sudo nix-collect-garbage -d && nix-collect-garbage -d

repl HOSTNAME="": gitadd
  nixos-rebuild repl --flake .#{{HOSTNAME}}


revision:
  nixos-version --configuration-revision

show HOSTNAME="":
  if [[ -n "{{ HOSTNAME }}" ]]; then HASH="$(ssh {{HOSTNAME}} 'nixos-version --configuration-revision')"; else HASH="$(nixos-version --configuration-revision)"; fi && \
  if git cat-file -e ${HASH} &>/dev/null; then git show ${HASH}; else echo unknown revison \""${HASH}"\"; fi;

size HOSTNAME="$(hostname)":
  nix path-info -Sh  .#nixosConfigurations.{{HOSTNAME}}.config.system.build.toplevel
