{
  lib,
  jail,
  pi,
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
  mcp-searxng,
  gnumake,
  gnused,
  jq,
  just,
  python313,
  ripgrep,
  tree,
  uv,
  nix,
  writers,
  python3Packages,

  # Global AGENTS.md text prepended to the sandbox notes.
  piMd ? null,

  # Contents of ~/.pi/agent/models.json, linked read-only.
  piModels ? null,

  # llama.cpp router URL for pi's built-in llama.cpp provider.
  llamaBaseUrl ? null,

  # the host's configured git wrapper, for user.email inside the jail
  gitPackage ? git,

  # talk to the host nix daemon with the whole store mounted, instead of only
  # the dev shell closure. Only safe when the user is not a trusted nix user.
  nixDaemon ? false,
  nixPackage ? nix,

  # pi only needs its provider endpoints here. Add them with extraAllowedHosts.
  allowedHosts ? [
    ".github.com:443"
    ".githubusercontent.com:443"
    "registry.npmjs.org:443"
    ".pypi.org:443"
    ".pythonhosted.org:443"
    ".crates.io:443"
    ".nixos.org:443"
    "gitlab.com:443"
  ],
  extraAllowedHosts ? [ ],
}:
# pi confined to the directory it is started in
let
  hosts = allowedHosts ++ extraAllowedHosts;
  proxyPort = 3128;
  proxyUrl = "http://127.0.0.1:${toString proxyPort}";
  runDir = "/run/pi-sandbox";
  proxyDir = "/run/pi-sandbox-proxy";
  devEnvFile = "${runDir}/devenv";

  agentsMdFile = writeText "AGENTS.md" (
    lib.optionalString (piMd != null) piMd
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

      ## Sandbox dev shell

      The devShell from this directory's flake.nix, if there is one, is already
      in the environment. To reload it, tell me and I'll restart pi.
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

  piModelsFile = writeText "models.json" (builtins.toJSON piModels);
  mcpFile = writeText "mcp.json" (
    builtins.toJSON {
      mcpServers = {
        searxng = {
          command = "mcp-searxng";
          env = {
            SEARXNG_URL = "https://searxng.avalls.dev";
          };
        };
      };
    }
  );

  proxyExe = lib.getExe claude-sandbox-proxy;
  ensureProxy = writers.writePython3 "pi-sandbox-ensure-proxy" {
    libraries = [ python3Packages.jeepney ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./claude-sandbox-proxy/ensure-proxy.py);
  proxyUnit = "pi-sandbox-proxy";
  proxyDescription = "pi-sandbox proxy ${
    builtins.substring 0 8 (
      builtins.hashString "sha256" (builtins.unsafeDiscardStringContext "${proxyExe} ${toString hosts}")
    )
  }";

in
jail "pi-sandbox" pi (
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
      PI_RUN_DIR=$(mktemp -d)
      mkdir "$PI_RUN_DIR/run"

      PI_PROXY_DIR="''${XDG_RUNTIME_DIR:?}/pi-sandbox-proxy"
      mkdir -p "$PI_PROXY_DIR"
      ${ensureProxy} ${proxyUnit} ${lib.escapeShellArg proxyDescription} "$PI_PROXY_DIR/proxy.sock" \
        ${proxyExe} serve ${lib.escapeShellArgs hosts}

      exec {PI_LOG_FD}> >(exec ${proxyExe} journal "pi-sandbox-bridge@$PWD")
      RUNTIME_ARGS+=(--setenv CLAUDE_SANDBOX_LOG_FD "$PI_LOG_FD")
    '')
    (add-cleanup ''
      if [ -n "''${PI_RUN_DIR-}" ]; then
        rm -rf "$PI_RUN_DIR"
      fi
    '')
    (rw-bind (noescape "\"$PI_RUN_DIR/run\"") runDir)
    (ro-bind (noescape "\"$PI_PROXY_DIR\"") proxyDir)

    (wrap-entry (entry: ''
      if [ -r ${devEnvFile} ]; then
        # print-dev-env saves PATH and appends it back, so the jail's own
        # tools survive the dev shell's
        set +u
        # shellcheck disable=SC1091
        . ${devEnvFile}
        set -u
      fi
      exec ${proxyExe} bridge 127.0.0.1:${toString proxyPort} ${proxyDir}/proxy.sock -- ${entry}
    ''))
    (set-env "HTTP_PROXY" proxyUrl)
    (set-env "HTTPS_PROXY" proxyUrl)
    (set-env "http_proxy" proxyUrl)
    (set-env "https_proxy" proxyUrl)
    (set-env "ALL_PROXY" "socks5h://localhost${proxyDir}/proxy.sock")
    no-new-session

    # one login, one history and one set of settings for every workspace,
    # under ~/.local/share/jail.nix/home/pi
    (persist-home "pi")

    # global AGENTS.md, read by pi from its agent directory
    (bind-pkg (noescape "~/.pi/agent/AGENTS.md") agentsMdFile)

    mount-cwd
  ]
  ++ lib.optional (llamaBaseUrl != null) (set-env "LLAMA_BASE_URL" llamaBaseUrl)
  ++ lib.optional (piModels != null) (bind-pkg (noescape "~/.pi/agent/models.json") piModelsFile)
  ++ [ (bind-pkg (noescape "~/.pi/agent/mcp.json") mcpFile) ]
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
          if nix print-dev-env > "$PI_RUN_DIR/devenv" 2> /dev/null; then
            mv "$PI_RUN_DIR/devenv" "$PI_RUN_DIR/run/devenv"
          fi
        '')
      ]
    else
      [
        # mount the runtime closure of the dev shell's inputs, if this is a flake
        # with devShells.<system>.default (same scheme as claude-sandbox)
        (add-runtime ''
          if nix print-dev-env > "$PI_RUN_DIR/devenv" 2> /dev/null; then
            mv "$PI_RUN_DIR/devenv" "$PI_RUN_DIR/run/devenv"
            sys=$(nix eval --raw --impure --expr builtins.currentSystem)
            if drv=$(nix eval --raw ".#devShells.$sys.default.drvPath" 2> /dev/null); then
              nix-store --query --references "$drv" \
                | ${lib.getExe gnugrep} '\.drv$' \
                | ${findutils}/bin/xargs -r nix-store --query --outputs 2> /dev/null \
                | sort -u \
                | while read -r p; do nix-store --query --requisites "$p" 2> /dev/null || true; done \
                | sort -u \
                | while read -r p; do printf '%s\0%s\0%s\0' --ro-bind "$p" "$p"; done \
                > "$PI_RUN_DIR/binds"
              exec {PI_DEV_FD}< "$PI_RUN_DIR/binds"
              RUNTIME_ARGS+=(--args "$PI_DEV_FD")
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

    # pi's bash tool runs /bin/bash
    (ro-bind "${bash}/bin/bash" "/bin/bash")
    # for #!/usr/bin/env shebangs (prek hooks)
    (ro-bind "${coreutils}/bin/env" "/usr/bin/env")
    (set-env "SHELL" "/bin/bash")

    (add-pkg-deps [
      bash
      coreutils
      curl
      fd
      file
      gitPackage
      git-lfs
      mcp-searxng
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

    (set-env "PI_TELEMETRY" "0")
    (set-env "PI_SKIP_VERSION_CHECK" "1")
    (try-fwd-env "COLORTERM")
  ]
)
