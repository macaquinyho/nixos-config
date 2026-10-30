{
  lib,
  jail,
  claude-desktop,
  symlinkJoin,
  writeShellScriptBin,
  xdg-utils,
}:
# Claude Desktop for chat only: no host files, store paths limited to its closure,
# downloads and uploads go through ~/Downloads/Claude
let
  xdg-open = writeShellScriptBin "xdg-open" ''exec hostopen "$1"'';

  jailed = jail "claude-desktop" claude-desktop (
    with jail.combinators;
    [
      network
      gui
      gpu
      notifications
      (dbus {
        talk = [
          "org.freedesktop.portal.Desktop"
          "org.kde.StatusNotifierWatcher"
        ];
      })
      (try-fwd-env "NIXOS_OZONE_WL")
      (try-fwd-env "ELECTRON_OZONE_PLATFORM_HINT")

      (jail-to-host-channel "hostopen" ''
        if [[ "$1" =~ ^https?:// ]]; then
          ${lib.getExe' xdg-utils "xdg-open"} "$1"
        fi
      '')
      (add-pkg-deps [ xdg-open ])

      (persist-home "claude-desktop")
      (add-runtime "mkdir -p ~/Downloads/Claude")
      (rw-bind (noescape "~/Downloads/Claude") (noescape "~/Downloads"))

      # chromium keeps its single-instance socket under TMPDIR, so a claude://
      # login callback started in a second jail has to find the first one's
      (set-env "TMPDIR" (noescape "~/.cache/tmp"))
      (wrap-entry (entry: ''
        mkdir -p "$TMPDIR"
        exec ${entry}
      ''))
      # cookies fall back to chromium's fixed key instead of the host keyring
      (set-argv [
        "--password-store=basic"
        (noescape "\"$@\"")
      ])
    ]
  );
in
symlinkJoin {
  name = "claude-desktop-jailed";
  # jailed first, so its bin/claude-desktop wins over the original
  paths = [
    jailed
    claude-desktop
  ];
  meta.mainProgram = "claude-desktop";
}
