{ lib, buildGoModule }:
buildGoModule {
  pname = "nixos-ci-update";
  version = "0";
  src = ./.;
  vendorHash = "sha256-sT8RPm2jbRPCP8eC66TVrxfsZONiGEPgv7kc1iBbPmY=";
  meta.mainProgram = "nixos-ci-update";
}
