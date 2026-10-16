{ rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "claude-sandbox-proxy";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta.mainProgram = "claude-sandbox-proxy";
}
