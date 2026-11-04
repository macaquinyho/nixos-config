{
  lib,
  jail,
  claude-code,
  mcp-victoriametrics,
  writeText,
  cacert,
  claude-sandbox-proxy,
  gnugrep,
  findutils,
  bash,
  coreutils,
  curl,
  fd,
  file,
  git,
  git-lfs,
  gnumake,
  gnused,
  iproute2,
  jq,
  just,
  python313,
  ripgrep,
  tree,
  uv,
  nix,
  writers,
  python3Packages,

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
      "gitlab.com:443" # GitLab MCP endpoint
      "api.githubcopilot.com:443" # GitHub MCP endpoint
    ],
  extraAllowedHosts ? [ ],
  extraMcpServers ? { },
}:
# Claude Code confined to the directory it is started in
let
  hosts = allowedHosts ++ extraAllowedHosts;
  proxyPort = 3128;
  proxyUrl = "http://127.0.0.1:${toString proxyPort}";
  runDir = "/run/claude-sandbox";
  proxyDir = "/run/claude-sandbox-proxy";
  devEnvFile = "${runDir}/devenv";

  claudeMdFile = writeText "CLAUDE.md" (
    lib.optionalString (claudeMd != null) claudeMd
    + ''

      ## Sandbox network

      Egress goes through a proxy. Only these hosts are reachable, on port 443,
      and a leading dot covers subdomains:

      ${lib.concatMapStrings (host: "- ${lib.removeSuffix ":443" host}\n") hosts}
      Anything else gets `CONNECT tunnel failed, response 403`. Retrying won't
      help. Ask me to allow the domain.

      The same proxy speaks SOCKS5 for tools that need it:
      `socks5h://127.0.0.1:${toString proxyPort}`, or directly on the unix socket
      `${proxyDir}/proxy.sock` for clients that support it (curl:
      `socks5h://localhost${proxyDir}/proxy.sock`). Use socks5h, there is no DNS
      in the sandbox.

      ## Sandbox /tmp

      /tmp is a host directory, so I can read what you leave there. On the host it
      is at the path in `$CLAUDE_SANDBOX_HOST_TMP`. When you tell me about a file
      in /tmp, give me that host path instead of the /tmp one.

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

  proxyExe = lib.getExe claude-sandbox-proxy;
  ensureProxy = writers.writePython3 "claude-sandbox-ensure-proxy" {
    libraries = [ python3Packages.jeepney ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./claude-sandbox-proxy/ensure-proxy.py);
  proxyUnit = "claude-sandbox-proxy";
  # tells a running proxy from an older build apart, so it gets replaced
  proxyDescription = "claude-sandbox proxy ${
    builtins.substring 0 8 (
      builtins.hashString "sha256" (builtins.unsafeDiscardStringContext "${proxyExe} ${toString hosts}")
    )
  }";

in
jail "claude-sandbox" (claude-code.override { inherit extraMcpServers; }) (
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

      CLAUDE_HOST_TMP_ROOT="''${XDG_RUNTIME_DIR:?}/claude-sandbox-tmp"
      mkdir -p "$CLAUDE_HOST_TMP_ROOT"
      CLAUDE_HOST_TMP=$(mktemp -d -p "$CLAUDE_HOST_TMP_ROOT")
      RUNTIME_ARGS+=(
        --bind "$CLAUDE_HOST_TMP" /tmp
        --setenv CLAUDE_SANDBOX_HOST_TMP "$CLAUDE_HOST_TMP"
      )

      CLAUDE_PROXY_DIR="''${XDG_RUNTIME_DIR:?}/claude-sandbox-proxy"
      mkdir -p "$CLAUDE_PROXY_DIR"
      ${ensureProxy} ${proxyUnit} ${lib.escapeShellArg proxyDescription} "$CLAUDE_PROXY_DIR/proxy.sock" \
        ${proxyExe} serve ${lib.escapeShellArgs hosts}

      exec {CLAUDE_LOG_FD}> >(exec ${proxyExe} journal "claude-sandbox-bridge@$PWD")
      RUNTIME_ARGS+=(--setenv CLAUDE_SANDBOX_LOG_FD "$CLAUDE_LOG_FD")
    '')
    # --dev-bind PATH (repeatable) binds a host device node, --netif IFACE moves a
    # host interface into the sandbox netns. Both must precede claude's own args.
    (add-runtime ''
      CLAUDE_NETIF=
      while [ $# -gt 0 ]; do
        case $1 in
          --dev-bind)
            dev=''${2:?--dev-bind needs a device path}
            RUNTIME_ARGS+=(--dev-bind "$dev" "$dev")
            shift 2 ;;
          --netif) CLAUDE_NETIF=''${2:?--netif needs an interface name}; shift 2 ;;
          *) break ;;
        esac
      done

      if [ -n "$CLAUDE_NETIF" ]; then
        if [ ! -d "/sys/class/net/$CLAUDE_NETIF" ]; then
          echo "claude-sandbox: no interface $CLAUDE_NETIF" >&2
          exit 1
        fi
        # bwrap reports the in-namespace pid on this fd, and the interface has to be
        # moved by the pid that owns the netns
        exec {CLAUDE_STATUS_FD}> >(
          read -r status
          pid=$(${lib.getExe jq} -r '."child-pid"' <<< "$status")
          /run/wrappers/bin/sudo ${iproute2}/bin/ip link set "$CLAUDE_NETIF" netns "$pid" ||
            echo "claude-sandbox: could not move $CLAUDE_NETIF" >&2
          cat > /dev/null
        )
        # --dev makes bwrap nest a second userns to drop to the real uid, and caps
        # there don't apply to the netns, which the outer userns owns
        RUNTIME_ARGS+=(
          --json-status-fd "$CLAUDE_STATUS_FD"
          --uid 0 --gid 0
          --cap-add CAP_NET_ADMIN --cap-add CAP_NET_RAW
          --setenv CLAUDE_SANDBOX_NETIF "$CLAUDE_NETIF"
        )
      fi
    '')

    (add-cleanup ''
      if [ -n "''${CLAUDE_RUN_DIR-}" ]; then
        rm -rf "$CLAUDE_RUN_DIR"
      fi
    '')
    (rw-bind (noescape "\"$CLAUDE_RUN_DIR/run\"") runDir)
    (ro-bind (noescape "\"$CLAUDE_PROXY_DIR\"") proxyDir)

    (wrap-entry (entry: ''
      if [ -r ${devEnvFile} ]; then
        # print-dev-env saves PATH and appends it back, so the jail's own
        # tools survive the dev shell's
        set +u
        # shellcheck disable=SC1091
        . ${devEnvFile}
        set -u
      fi
      if [ -n "''${CLAUDE_SANDBOX_NETIF-}" ]; then
        # the host moves the interface in once bwrap has created the netns
        for _ in $(seq 600); do
          ip link show "$CLAUDE_SANDBOX_NETIF" > /dev/null 2>&1 && break
          sleep 0.1
        done
      fi
      exec ${proxyExe} bridge 127.0.0.1:${toString proxyPort} ${proxyDir}/proxy.sock -- ${entry}
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
    # for #!/usr/bin/env shebangs (prek hooks)
    (ro-bind "${coreutils}/bin/env" "/usr/bin/env")
    (set-env "SHELL" "/bin/bash")

    (add-pkg-deps [
      mcp-victoriametrics
      bash
      coreutils
      curl
      fd
      file
      gitPackage
      git-lfs
      gnugrep
      gnumake
      gnused
      iproute2
      jq
      just
      python313
      ripgrep
      tree
      uv
    ])

    (try-fwd-env "COLORTERM")
    # point claude at another Anthropic-compatible endpoint, e.g. a local llama-server
    (try-fwd-env "ANTHROPIC_BASE_URL")
    (try-fwd-env "ANTHROPIC_AUTH_TOKEN")
    (try-fwd-env "ANTHROPIC_MODEL")
    (try-fwd-env "ANTHROPIC_DEFAULT_OPUS_MODEL")
    (try-fwd-env "ANTHROPIC_DEFAULT_SONNET_MODEL")
    (try-fwd-env "ANTHROPIC_DEFAULT_HAIKU_MODEL")
  ]
)
