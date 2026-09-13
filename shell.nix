{
  pkgs ?
    let
      # If pkgs is not defined, instantiate nixpkgs from locked commit
      lock = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked;
      nixpkgs = fetchTarball {
        url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
        sha256 = lock.narHash;
      };
      system = builtins.currentSystem;
      overlays = [ ]; # Explicit blank overlay to avoid interference
    in
    import nixpkgs { inherit system overlays; },
  ...
}:
pkgs.mkShell {
  # Enable experimental features without having to specify the argument
  name = "nixosbuildshell";
  NIX_CONFIG = "experimental-features = nix-command flakes";
  nativeBuildInputs = with pkgs; [
    nix
    git
    git-crypt
    nixVersions.stable
    gnumake
    tmux
    vim
    deploy-rs
    openssh
    just
  ];

  shellHook = ''
    echo "Shell prepared for deploying nixos"
  '';
}
