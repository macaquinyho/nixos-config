{
  lib,
  jail,
  claude-code,
  mcp-victoriametrics,
  writeText,
  writeShellScriptBin,
  writeShellApplication,
  openssh,
  symlinkJoin,
  cacert,
  claude-sandbox-proxy,
  libnotify,
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

  # git@HOST remotes fetched through the proxy with the host's ssh key, push refused
  gitSshHosts ? [ ],
  sshPackage ? openssh,
}:
# Claude Code confined to the directory it is started in
let
  hosts = allowedHosts ++ extraAllowedHosts;
  proxyPort = 3128;
  proxyUrl = "http://127.0.0.1:${toString proxyPort}";
  runDir = "/run/claude-sandbox";
  proxyDir = "/run/claude-sandbox-proxy";
  # under $XDG_RUNTIME_DIR, never mounted in the sandbox
  sessionsDir = "claude-sandbox-sessions";
  devEnvFile = "${runDir}/devenv";

  claudeMdFile = writeText "CLAUDE.md" (
    lib.optionalString (claudeMd != null) claudeMd
    + ''

      ## Sandbox network

      Egress goes through a proxy. Only these hosts are reachable, on port 443,
      and a leading dot covers subdomains:

      ${lib.concatMapStrings (host: "- ${lib.removeSuffix ":443" host}\n") hosts}
      Any other host pops up a prompt on my desktop, and the connection waits up
      to a minute for my answer. If I deny it or don't answer, it fails with
      `CONNECT tunnel failed, response 403`. Retrying won't help for ten minutes.
      When you know you'll need a host, ask ahead with `sandbox-request HOST[:PORT]
      "short reason"`, which waits for my answer. I can also allow hosts from the
      host with `claude-allow HOST`.

      The same proxy speaks SOCKS5 for tools that need it:
      `socks5h://127.0.0.1:${toString proxyPort}`, or directly on the unix socket
      `${proxyDir}/proxy.sock` for clients that support it (curl:
      `socks5h://localhost${proxyDir}/proxy.sock`). Use socks5h, there is no DNS
      in the sandbox.

      ## Sandbox /tmp

      /tmp is a host directory, so I can read what you leave there. On the host it
      is at the path in `$CLAUDE_SANDBOX_HOST_TMP`. When you tell me about a file
      in /tmp, give me that host path instead of the /tmp one.

      ${
        lib.optionalString (gitSshHosts != [ ]) ''
          ## Sandbox git access

          git over ssh (`git@HOST:` remotes) to ${lib.concatStringsSep ", " gitSshHosts}
          goes through the proxy, which runs ssh on the host with my key. Clone, fetch
          and pull work. Push and other ssh commands are refused by the proxy, don't try
          to work around that. https remotes on those hosts have no credentials. LFS
          is not available, clone repos that use it with `GIT_LFS_SKIP_SMUDGE=1`.

        ''
      }## Sandbox git worktrees

      When this directory belongs to a git repository with other worktrees, they
      are mounted at their usual paths, read-only. The shared git directory is
      writable. Don't remove or prune those worktrees, and don't edit files in
      them. If a task needs that, ask me to restart claude with `--add-dir` for
      that path.

      Git config, hooks and the files that locate `.git` are read-only, as git
      on the host would run what they name. Commands that write repo config
      fail: use `git switch -c NAME --no-track`, `git -c KEY=VALUE` for one-off
      settings, and ask me for remotes, submodule init or hook installs.

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
  proxyArgs = [
    "--ssh"
    (lib.getExe' sshPackage "ssh")
    "--notify"
    (lib.getExe' libnotify "notify-send")
  ]
  ++ lib.concatMap (host: [
    "--git-ssh-host"
    host
  ]) gitSshHosts
  ++ hosts;
  ensureProxy = writers.writePython3 "claude-sandbox-ensure-proxy" {
    libraries = [ python3Packages.jeepney ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./claude-sandbox-proxy/ensure-proxy.py);
  proxyUnit = "claude-sandbox-proxy";
  # tells a running proxy from an older build apart, so it gets replaced
  proxyDescription = "claude-sandbox proxy ${
    builtins.substring 0 8 (
      builtins.hashString "sha256" (
        builtins.unsafeDiscardStringContext "${proxyExe} ${toString proxyArgs}"
      )
    )
  }";

  jailed = jail "claude" (claude-code.override { inherit extraMcpServers; }) (
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
        CLAUDE_SESSIONS_DIR="''${XDG_RUNTIME_DIR:?}/${sessionsDir}"
        mkdir -p "$CLAUDE_PROXY_DIR"
        [ -d "$CLAUDE_SESSIONS_DIR" ] || mkdir -m 700 "$CLAUDE_SESSIONS_DIR"
        ${ensureProxy} ${proxyUnit} ${lib.escapeShellArg proxyDescription} "$CLAUDE_PROXY_DIR/proxy.sock" \
          ${proxyExe} serve --sessions "$CLAUDE_SESSIONS_DIR" ${lib.escapeShellArgs proxyArgs}

        exec {CLAUDE_LOG_FD}> >(exec ${proxyExe} journal "claude-sandbox-bridge@$PWD")
        RUNTIME_ARGS+=(--setenv CLAUDE_SANDBOX_LOG_FD "$CLAUDE_LOG_FD")
      '')
      # --dev-bind PATH binds a host device node, --add-dir DIR... mounts directories at the
      # same path, --netif IFACE moves a host interface into the sandbox netns. The
      # first two repeat, and all must precede claude's own args. --exec CMD... runs
      # CMD in the sandbox instead of claude, and takes the rest of the arguments.
      (add-runtime ''
        CLAUDE_NETIF=
        CLAUDE_EXTRA_DIRS=()
        while [ $# -gt 0 ]; do
          case $1 in
            --add-dir)
              : "''${2:?--add-dir needs a directory}"
              shift
              # variadic like claude's own --add-dir, up to the next option
              while [ $# -gt 0 ] && [ "''${1#-}" = "$1" ]; do
                [ -d "$1" ] || {
                  echo "claude-sandbox: $1 is not a directory" >&2
                  exit 1
                }
                CLAUDE_EXTRA_DIRS+=("$1")
                shift
              done ;;
            --dev-bind)
              dev=''${2:?--dev-bind needs a device path}
              RUNTIME_ARGS+=(--dev-bind "$dev" "$dev")
              shift 2 ;;
            --netif) CLAUDE_NETIF=''${2:?--netif needs an interface name}; shift 2 ;;
            --exec)
              shift
              [ $# -gt 0 ] || {
                echo "claude-sandbox: --exec needs a command" >&2
                exit 1
              }
              RUNTIME_ARGS+=(--setenv CLAUDE_SANDBOX_EXEC 1)
              break ;;
            *) break ;;
          esac
        done

        if [ -n "$CLAUDE_NETIF" ] && [ ! -d "/sys/class/net/$CLAUDE_NETIF" ]; then
          echo "claude-sandbox: no interface $CLAUDE_NETIF" >&2
          exit 1
        fi
        # bwrap reports the in-namespace pid on this fd. Its netns identifies the
        # session to the proxy, and an interface has to be moved by that pid.
        exec {CLAUDE_STATUS_FD}> >(
          read -r status
          pid=$(${lib.getExe jq} -r '."child-pid"' <<< "$status")
          # a shared host netns would hand this session's allowlist to every process
          if ns=$(stat -L -c %i "/proc/$pid/ns/net") &&
            [ "$ns" != "$(stat -L -c %i /proc/self/ns/net)" ]; then
            session="$CLAUDE_SESSIONS_DIR/$ns"
            # built aside and moved in whole, so claude-allow never sees it half done
            tmp=$(mktemp -d -p "$CLAUDE_SESSIONS_DIR" .new.XXXXXX)
            printf '%s\n' "$PWD" > "$tmp/cwd"
            printf '%s\n' "$pid" > "$tmp/pid"
            : > "$tmp/allow"
            rm -rf "$session"
            mv "$tmp" "$session"
            printf '%s\n' "$session" > "$CLAUDE_RUN_DIR/session"
          fi
          if [ -n "$CLAUDE_NETIF" ]; then
            /run/wrappers/bin/sudo ${iproute2}/bin/ip link set "$CLAUDE_NETIF" netns "$pid" ||
              echo "claude-sandbox: could not move $CLAUDE_NETIF" >&2
          fi
          cat > /dev/null
        )
        RUNTIME_ARGS+=(--json-status-fd "$CLAUDE_STATUS_FD")
        if [ -n "$CLAUDE_NETIF" ]; then
          # --dev makes bwrap nest a second userns to drop to the real uid, and caps
          # there don't apply to the netns, which the outer userns owns
          RUNTIME_ARGS+=(
            --uid 0 --gid 0
            --cap-add CAP_NET_ADMIN --cap-add CAP_NET_RAW
            --setenv CLAUDE_SANDBOX_NETIF "$CLAUDE_NETIF"
          )
        fi
      '')

      (add-cleanup ''
        if [ -n "''${CLAUDE_RUN_DIR-}" ]; then
          if [ -r "$CLAUDE_RUN_DIR/session" ]; then
            rm -rf "$(< "$CLAUDE_RUN_DIR/session")"
          fi
          # some tools leave read-only dirs behind, like Go's module cache
          chmod -R u+w "$CLAUDE_RUN_DIR" 2> /dev/null || true
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
        if [ -n "''${CLAUDE_SANDBOX_EXEC-}" ]; then
          exec ${proxyExe} bridge 127.0.0.1:${toString proxyPort} ${proxyDir}/proxy.sock -- "$@"
        fi
        exec ${proxyExe} bridge 127.0.0.1:${toString proxyPort} ${proxyDir}/proxy.sock -- ${entry}
      ''))
      (set-env "HTTP_PROXY" proxyUrl)
      (set-env "HTTPS_PROXY" proxyUrl)
      (set-env "http_proxy" proxyUrl)
      (set-env "https_proxy" proxyUrl)
      (set-env "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "1")
    ]
    ++ lib.optionals (gitSshHosts != [ ]) [
      (set-env "GIT_SSH_COMMAND" "${proxyExe} git-ssh ${proxyDir}/proxy.sock")
      # so git passes -p and SendEnv=GIT_PROTOCOL
      (set-env "GIT_SSH_VARIANT" "ssh")
    ]
    ++ [
      no-new-session

      # A fresh home and ~/.claude every session, on disk in the run dir, so
      # they go with it. Only these persist, in ~/.local/share/claude-sandbox:
      # config and login, chats, prompt history and plugins.
      # CLAUDE_CONFIG_DIR moves .claude.json into ~/.claude.
      (add-runtime ''
        CLAUDE_STATE=~/.local/share/claude-sandbox
        CLAUDE_OLD=~/.local/share/jail.nix/home/claude-code
        mkdir -p "$CLAUDE_STATE"
        for f in .claude.json .credentials.json history.jsonl projects plugins; do
          if [ -e "$CLAUDE_OLD/.claude/$f" ] && [ ! -e "$CLAUDE_STATE/$f" ]; then
            mv "$CLAUDE_OLD/.claude/$f" "$CLAUDE_STATE/"
          fi
        done
        mkdir -p "$CLAUDE_STATE/projects" "$CLAUDE_STATE/plugins"
        [ -e "$CLAUDE_STATE/.claude.json" ] || echo '{}' > "$CLAUDE_STATE/.claude.json"
        touch "$CLAUDE_STATE/.credentials.json" "$CLAUDE_STATE/history.jsonl"
        chmod 600 "$CLAUDE_STATE/.claude.json" "$CLAUDE_STATE/.credentials.json" "$CLAUDE_STATE/history.jsonl"

        mkdir -p "$CLAUDE_RUN_DIR/home/.claude"
        # .claude.json is saved by renaming a temp file over it, which fails on
        # a bind-mounted file, but Claude writes it through symlinks
        ln -s "$CLAUDE_STATE/.claude.json" "$CLAUDE_RUN_DIR/home/.claude/.claude.json"
      '')
      (rw-bind (noescape "\"$CLAUDE_RUN_DIR/home\"") (noescape "~"))
      (rw-bind (noescape "\"$CLAUDE_STATE\"") (noescape "\"$CLAUDE_STATE\""))
      # credentials are opened with O_NOFOLLOW and rewritten in place, so a bind works and a symlink doesn't
      (rw-bind (noescape "\"$CLAUDE_STATE/.credentials.json\"") (noescape "~/.claude/.credentials.json"))
      (rw-bind (noescape "\"$CLAUDE_STATE/history.jsonl\"") (noescape "~/.claude/history.jsonl"))
      (rw-bind (noescape "\"$CLAUDE_STATE/projects\"") (noescape "~/.claude/projects"))
      (rw-bind (noescape "\"$CLAUDE_STATE/plugins\"") (noescape "~/.claude/plugins"))
      (set-env "CLAUDE_CONFIG_DIR" (noescape "\"$HOME/.claude\""))

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

      # --add-dir paths are writable. For them and the cwd, other worktrees are
      # mounted read-only, with their git admin dirs, so they can't be removed. The
      # rest of the git dir stays writable.
      # Worktree .git files point to these by absolute path, so paths are kept.
      (add-runtime ''
        claude_rw_roots=("$(pwd -P)")
        for dir in "''${CLAUDE_EXTRA_DIRS[@]}"; do
          p=$(realpath -e -- "$dir")
          claude_rw_roots+=("$p")
          RUNTIME_ARGS+=(--bind "$p" "$p")
        done
        claude_covered() {
          local r
          for r in "''${claude_rw_roots[@]}"; do
            case $1/ in
              "$r"/*) return 0 ;;
            esac
          done
          return 1
        }
        claude_bind_git() {
          local common wt p
          common=$(${git}/bin/git -C "$1" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || return 0
          while read -r wt; do
            p=$(realpath -e -- "$wt" 2> /dev/null) || continue
            claude_covered "$p" || RUNTIME_ARGS+=(--ro-bind "$p" "$p")
          done < <(${git}/bin/git -C "$1" worktree list --porcelain | ${gnused}/bin/sed -n 's/^worktree //p')
          # after the worktrees, so it is not hidden by the read-only mount of one
          common=$(realpath -e -- "$common")
          claude_covered "$common" || RUNTIME_ARGS+=(--bind "$common" "$common")
          # git unregisters a worktree even when deleting its files fails
          for d in "$common"/worktrees/*/; do
            d=''${d%/}
            [ -f "$d/gitdir" ] || continue
            claude_covered "$(dirname "$(< "$d/gitdir")")" || RUNTIME_ARGS+=(--ro-bind "$d" "$d")
          done
          claude_pin_git "$1" "$common"
        }
        # git on the host runs commands named in config and hooks, so the sandbox
        # can't change them. Mount points can't be renamed or replaced, which pins
        # the dirs holding them too.
        claude_pin_git() {
          local top gitdir common=$2 m f
          top=$(${git}/bin/git -C "$1" rev-parse --show-toplevel)
          gitdir=$(realpath -e -- "$(${git}/bin/git -C "$1" rev-parse --absolute-git-dir)")
          if [ -d "$top/.git" ]; then
            RUNTIME_ARGS+=(--bind "$top/.git" "$top/.git")
          else
            RUNTIME_ARGS+=(--ro-bind "$top/.git" "$top/.git")
          fi
          if [ "$gitdir" != "$common" ]; then
            # a linked worktree finds the common dir through these
            RUNTIME_ARGS+=(
              --bind "$gitdir" "$gitdir"
              --ro-bind "$gitdir/commondir" "$gitdir/commondir"
              --ro-bind "$gitdir/gitdir" "$gitdir/gitdir"
            )
          fi
          # the common dir and submodule git dirs. Sorted, a parent comes before its
          # children, so pinning a child never hides the parent's read-only files.
          while read -r m; do
            [ "$m" = "$common" ] || RUNTIME_ARGS+=(--bind "$m" "$m")
            mkdir -p "$m/hooks"
            RUNTIME_ARGS+=(--ro-bind "$m/config" "$m/config" --ro-bind "$m/hooks" "$m/hooks")
          done < <({
            echo "$common"
            find "$common/modules" -name HEAD -type f -printf '%h\n' 2> /dev/null |
              while read -r m; do [ -f "$m/config" ] && echo "$m"; done
          } | sort)
          # relative to the worktree root, as git runs hooks from there. Created if
          # missing, or the sandbox could create it.
          if f=$(${git}/bin/git -C "$1" config --path core.hooksPath); then
            f=$(cd "$top" && realpath -m -- "$f")
            mkdir -p "$f"
            RUNTIME_ARGS+=(--ro-bind "$f" "$f")
          fi
          if [ "$(${git}/bin/git -C "$1" config --bool extensions.worktreeConfig)" = true ]; then
            for f in "$common/config.worktree" "$gitdir/config.worktree"; do
              touch "$f"
              RUNTIME_ARGS+=(--ro-bind "$f" "$f")
            done
          fi
        }
        claude_bind_git .
        for dir in "''${CLAUDE_EXTRA_DIRS[@]}"; do
          claude_bind_git "$dir"
        done
      '')

      # claude reaches for /bin/bash for its shell tool
      (ro-bind "${bash}/bin/bash" "/bin/bash")
      # for #!/usr/bin/env shebangs (prek hooks)
      (ro-bind "${coreutils}/bin/env" "/usr/bin/env")
      (set-env "SHELL" "/bin/bash")

      (add-pkg-deps [
        sandboxRequest
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
  );

  sandboxRequest = writeShellScriptBin "sandbox-request" ''
    exec ${proxyExe} request ${proxyDir}/proxy.sock "$@"
  '';

  claudeAllow = writeShellApplication {
    name = "claude-allow";
    runtimeInputs = [ coreutils ];
    runtimeEnv.SESSIONS_DIR_NAME = sessionsDir;
    text = builtins.readFile ./claude-allow.sh;
  };
in
symlinkJoin {
  name = "claude";
  # so tmux shows claude, not the jail's bash
  paths = [
    (writeShellScriptBin "claude" ''exec -a claude ${lib.getExe bash} ${lib.getExe jailed} "$@"'')
    claudeAllow
  ];
  postBuild = ''
    install -Dm444 ${./claude-sandbox-completion.bash} $out/share/bash-completion/completions/claude
  '';
  meta.mainProgram = "claude";
}
