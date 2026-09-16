# This file defines overlays
{

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # symlinkJoin instead of overrideAttrs so the rust package isn't rebuilt
    numbat =
      let
        assets = final.runCommand "${prev.numbat.pname}-assets" { } ''
          # The source files are in a directory named 'assets' at the root
          # of the unpacked source code. The destination paths are relative
          # to $out, which points to the package's output directory in the Nix store.
          src=${prev.numbat.src}/assets

          # Create the applications directory and install the .desktop file
          install -Dm644 $src/numbat.desktop $out/share/applications/numbat.desktop

          # Install the scalable SVG icon
          install -Dm644 $src/numbat.svg $out/share/icons/hicolor/scalable/apps/numbat.svg

          # Loop through the specified sizes and install the PNG icons
          for s in 16 22 24 32 48 64 128 256 512; do
            install -Dm644 "$src/numbat-''${s}x''${s}.png" "$out/share/icons/hicolor/''${s}x''${s}/apps/numbat.png"
          done
        '';
      in
      final.symlinkJoin {
        pname = "${prev.numbat.pname}-wrapped";
        paths = [
          prev.numbat
          assets
        ];
        inherit (prev.numbat) version meta;
      };
    # home-assistant-custom-components.tuya_local =
    #   prev.home-assistant-custom-components.tuya_local.overrideAttrs
    #     (
    #       finalAttrs: previousAttrs: rec {
    #         version = "2025.12.3";
    #         src = final.fetchFromGitHub {
    #           inherit (previousAttrs.src) owner repo;
    #           tag = version;
    #           hash = "sha256-KKBon2SC7rW7Vgr/8r77mRvb+ii/ZnuJLHW9DQoqN5o=";
    #         };
    #
    #         # postInstall = (previousAttrs.postInstall or "") + ''
    #         #   install -Dm444 ${./airmart.yaml} $out/custom_components/tuya_local/devices/airmart.yaml
    #         # '';
    #       }
    #     );
  };

}
