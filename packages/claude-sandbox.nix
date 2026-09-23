{
  lib,
  jail,
  claude-code,
  mcp-victoriametrics,
  writeText,
  cacert,
  gost,
  gnugrep,
  findutils,
  bash,
  coreutils,
  fd,
  file,
  git,
  gnumake,
  gnused,
  jq,
  just,
  python313,
  ripgrep,
  tree,
  uv,
  nix,

  # Global CLAUDE.md text prepended to the sandbox notes. The private flake sets
  # it.
  claudeMd ? null,
  claudeSettings ? null,

  # the host's configured git wrapper, for user.email inside the jail
  gitPackage ? git,

  # talk to the host nix daemon with the whole store mounted, instead of only
  # the dev shell closure. Only safe when the user is not a trusted nix user.
  nixDaemon ? false,
  nixPackage ? nix,

  allowedHosts ?
    # https://code.claude.com/docs/en/network-config#network-access-requirements
    [
      "api.anthropic.com:443"
      "claude.ai:443"
      "claude.com:443"
      "platform.claude.com:443"
      "mcp-proxy.anthropic.com:443" # connectors an org admin configures
      "downloads.claude.ai:443" # plugin executables
      "registry.npmjs.org:443" # plugin installs, npx-launched MCP servers
      ".frame.claudeusercontent.com:443" # artifact content reads
      "raw.githubusercontent.com:443" # /release-notes changelog
      "code.claude.com:443" # docs lookups by claude-code-guide
    ]

    ++ [
      ".github.com:443" # github.com, api.github.com, codeload
      ".githubusercontent.com:443"
      ".pypi.org:443"
      ".pythonhosted.org:443"
      ".crates.io:443"
      ".nixos.org:443"
    ]

    ++ [
      "vmetrics.oxigen.smd.dev:443" # victoriametrics MCP server target
    ],
}:
# Claude Code confined to the directory it is started in
let
  proxyPort = 3128;
  proxyUrl = "http://127.0.0.1:${toString proxyPort}";
  runDir = "/run/claude-sandbox";
  proxySocket = "${runDir}/proxy.sock";
  devEnvFile = "${runDir}/devenv";

  proxyConfig = writeText "claude-sandbox-gost.json" (
    builtins.toJSON {
      services = [
        {
          name = "claude-sandbox";
          addr = "proxy.sock";
          bypass = "allowed-hosts";
          handler.type = "auto";
          listener.type = "unix";
        }
      ];
      bypasses = [
        {
          name = "allowed-hosts";
          whitelist = true;
          matchers = allowedHosts;
        }
      ];
    }
  );

  claudeMdFile = writeText "CLAUDE.md" (
    lib.optionalString (claudeMd != null) claudeMd
    + ''

      ## Sandbox network

      Egress goes through a proxy. Only these hosts are reachable, on port 443,
      and a leading dot covers subdomains:

      ${lib.concatMapStrings (host: "- ${lib.removeSuffix ":443" host}\n") allowedHosts}
      Anything else gets `CONNECT tunnel failed, response 403`. Retrying won't
      help. Ask me to allow the domain.

      ## Sandbox dev shell

      The devShell from this directory's flake.nix, if there is one, is already
      in the environment. To reload it, tell me and I'll restart claude.
    ''
    + (
      if nixDaemon then
        ''

          nix is available and talks to the host daemon, with the whole store
          readable. Use `nix build`, `nix run` or `nix shell` for tools that aren't
          in the environment.
        ''
      else
        ''

          There is no nix here.
        ''
    )
  );

  claudeSettingsFile = writeText "claude-settings.json" (builtins.toJSON claudeSettings);

  bridgeConfig = writeText "claude-sandbox-gost-bridge.json" (
    builtins.toJSON {
      services = [
        {
          name = "claude-sandbox-bridge";
          addr = "127.0.0.1:${toString proxyPort}";
          handler.type = "tcp";
          listener.type = "tcp";
          forwarder.nodes = [
            {
              name = "proxy";
              addr = proxySocket;
              network = "unix";
            }
          ];
        }
      ];
    }
  );

in
jail "claude-sandbox" claude-code (
  with jail.combinators;
  [

    time-zone
    (bind-pkg "/etc/ssl/certs/ca-certificates.crt" "${cacert}/etc/ssl/certs/ca-bundle.crt")
    (set-env "SSL_CERT_FILE" "/etc/ssl/certs/ca-certificates.crt")
    (write-text "/etc/hosts" ''
      127.0.0.1 localhost
      ::1 localhost
    '')

    (add-runtime ''
      CLAUDE_RUN_DIR=$(mktemp -d)
      mkdir "$CLAUDE_RUN_DIR/run"
      (cd "$CLAUDE_RUN_DIR/run" && exec ${lib.getExe gost} -C ${proxyConfig}) \
        > "$CLAUDE_RUN_DIR/log" 2>&1 &
      CLAUDE_PROXY_PID=$!
    '')
    (add-cleanup ''
      if [ -n "''${CLAUDE_PROXY_PID-}" ]; then
        kill "$CLAUDE_PROXY_PID" 2>/dev/null || true
      fi
      if [ -n "''${CLAUDE_RUN_DIR-}" ]; then
        rm -rf "$CLAUDE_RUN_DIR"
      fi
    '')
    (rw-bind (noescape "\"$CLAUDE_RUN_DIR/run\"") runDir)

    (wrap-entry (entry: ''
      ${lib.getExe gost} -C ${bridgeConfig} 2>/dev/null &
      if [ -r ${devEnvFile} ]; then
        # print-dev-env saves PATH and appends it back, so the jail's own
        # tools survive the dev shell's
        set +u
        # shellcheck disable=SC1091
        . ${devEnvFile}
        set -u
      fi
      exec ${entry}
    ''))
    (set-env "HTTP_PROXY" proxyUrl)
    (set-env "HTTPS_PROXY" proxyUrl)
    (set-env "http_proxy" proxyUrl)
    (set-env "https_proxy" proxyUrl)
    (set-env "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "1")
    no-new-session

    # one login, one history and one set of settings for every workspace,
    # under ~/.local/share/jail.nix/home/claude-code
    (persist-home "claude-code")

    # global CLAUDE.md
    (bind-pkg (noescape "~/.claude/CLAUDE.md") claudeMdFile)

    mount-cwd
  ]
  ++ lib.optional (claudeSettings != null) (
    bind-pkg (noescape "~/.claude/settings.json") claudeSettingsFile
  )
  ++ [

  ]
  ++ (
    if nixDaemon then
      [
        (readonly "/nix/store")
        (readwrite "/nix/var/nix/daemon-socket")
        (readonly "/etc/nix")
        (try-readonly "/etc/static")
        (set-env "NIX_REMOTE" "daemon")
        (add-pkg-deps [ nixPackage ])
        (add-runtime ''
          if nix print-dev-env > "$CLAUDE_RUN_DIR/devenv" 2> /dev/null; then
            mv "$CLAUDE_RUN_DIR/devenv" "$CLAUDE_RUN_DIR/run/devenv"
          fi
        '')
      ]
    else
      [
        # mount the runtime closure of the dev shell's inputs, if this is a flake
        # with devShells.<system>.default. print-dev-env is still run for the env
        # vars wrap-entry sources; the mounts come from the devShell derivation's
        # direct inputs -> their outputs -> runtime requisites, which avoids
        # scraping store paths out of the print-dev-env script text.
        (add-runtime ''
          if nix print-dev-env > "$CLAUDE_RUN_DIR/devenv" 2> /dev/null; then
            mv "$CLAUDE_RUN_DIR/devenv" "$CLAUDE_RUN_DIR/run/devenv"
            sys=$(nix eval --raw --impure --expr builtins.currentSystem)
            if drv=$(nix eval --raw ".#devShells.$sys.default.drvPath" 2> /dev/null); then
              nix-store --query --references "$drv" \
                | ${lib.getExe gnugrep} '\.drv$' \
                | ${findutils}/bin/xargs -r nix-store --query --outputs 2> /dev/null \
                | sort -u \
                | while read -r p; do nix-store --query --requisites "$p" 2> /dev/null || true; done \
                | sort -u \
                | while read -r p; do printf '%s\0%s\0%s\0' --ro-bind "$p" "$p"; done \
                > "$CLAUDE_RUN_DIR/binds"
              exec {CLAUDE_DEV_FD}< "$CLAUDE_RUN_DIR/binds"
              RUNTIME_ARGS+=(--args "$CLAUDE_DEV_FD")
            fi
          fi
        '')
      ]
  )
  ++ [

    # if git worktree, mount also the parent
    (add-runtime ''
      GIT_PATHS=$(${git}/bin/git rev-parse --path-format=absolute \
        --show-toplevel --git-common-dir 2>/dev/null || true)
      GIT_TOPLEVEL=''${GIT_PATHS%%$'\n'*}
      GIT_COMMON_DIR=''${GIT_PATHS##*$'\n'}
      if [ -n "$GIT_PATHS" ] && [ "$GIT_TOPLEVEL" = "$(pwd -P)" ] &&
         [ "''${GIT_COMMON_DIR#"$GIT_TOPLEVEL"/}" = "$GIT_COMMON_DIR" ]; then
        RUNTIME_ARGS+=(--bind "$GIT_COMMON_DIR" "$GIT_COMMON_DIR")
      fi
    '')

    # claude reaches for /bin/bash for its shell tool
    (ro-bind "${bash}/bin/bash" "/bin/bash")
    (set-env "SHELL" "/bin/bash")

    (add-pkg-deps [
      mcp-victoriametrics
      bash
      coreutils
      fd
      file
      gitPackage
      gnugrep
      gnumake
      gnused
      jq
      just
      python313
      ripgrep
      tree
      uv
    ])

    (try-fwd-env "COLORTERM")
  ]
)
