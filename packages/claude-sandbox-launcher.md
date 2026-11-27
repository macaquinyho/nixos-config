# Plan: replace bwrap with a Rust launcher

Status: not started. Today `claude-sandbox.nix` builds the jail with jail.nix,
which runs bubblewrap, plus about 250 lines of bash in `add-runtime` hooks.

## Goals

- One typed program instead of bwrap plus bash hooks.
- Keep what makes the current sandbox cheap: bind-mounted store paths (or the
  whole `/nix/store` read-only) and access to the host nix daemon.
- Use the new mount API (`open_tree`, `move_mount`, `fsopen`/`fsconfig`/
  `fsmount`, `mount_setattr`, Linux 5.12+, all present on 6.x) instead of
  `mount(2)` with remount passes.
- Know the session's netns directly, so the proxy session record needs no
  `--json-status-fd` round trip.

## Non-goals

- No OCI, no images, no container runtime (youki/libcontainer, podman).
- No change to the proxy, its allowlists or the host prompt.
- No general-purpose sandbox. Only what this jail uses today.

## What it must reproduce

Check `lib/jail.nix` base arguments (namespaces, `/proc`, `/dev`, env
clearing, die-with-parent) before starting, then everything in
`claude-sandbox.nix`:

- Namespaces: user, mount, pid, net, ipc, uts, cgroup, all unshared.
- Root: tmpfs, then:
  - read-only binds: `add-pkg-deps` closures, CA bundle, `/etc/nix`,
    `/etc/static`, the proxy dir, `/bin/bash`, `/usr/bin/env`, worktrees
  - read-write binds: cwd, `--add-dir` dirs, the per-session run dir, the
    host tmp dir at `/tmp`, the persisted home
    (`~/.local/share/jail.nix/home/claude-code`), the nix daemon socket
  - files written in: `/etc/hosts`, CLAUDE.md, settings.json, time zone
- Nix daemon mode: `/nix/store` read-only and `NIX_REMOTE=daemon`. Otherwise
  the dev shell closure as individual read-only binds (can be thousands).
- Env: cleared, then the fixed set (proxy vars, `SSL_CERT_FILE`, `SHELL`,
  `GIT_SSH_*`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `PATH` from the
  package deps) plus the forwarded `ANTHROPIC_*` and `COLORTERM`.
- CLI: `--add-dir DIR...`, `--dev-bind PATH`, `--netif IFACE`, `--exec CMD...`,
  then claude's own args.
- `--netif`: move a host interface into the netns (sudo `ip link`), and run
  as uid 0 with `CAP_NET_ADMIN` and `CAP_NET_RAW` in a nested user namespace.
- Entry: source the dev shell env, wait for the netif if any, exec the proxy
  bridge, which runs claude.
- Proxy: ensure the shared proxy unit, register the session under
  `$XDG_RUNTIME_DIR/claude-sandbox-sessions/<netns inode>`, remove it on exit.
- Keep the controlling terminal (jail.nix `no-new-session`).

## Process model

1. Launcher (host, unprivileged): parse args, read the config Nix generated,
   resolve every bind source to an `O_PATH` fd with `openat2` and
   `RESOLVE_NO_MAGICLINKS`, start the proxy unit.
2. `clone3` with `CLONE_NEWUSER | NEWNS | NEWPID | NEWNET | NEWIPC | NEWUTS |
   NEWCGROUP` and `CLONE_PIDFD`. The child blocks on a pipe.
3. Parent: write `setgroups` = `deny`, then `uid_map` and `gid_map` (single
   mapping of the real uid/gid). Read the netns inode from the pidfd
   (`PIDFD_GET_NET_NAMESPACE`), write the session record, move the netif if
   asked. Release the child.
4. Child (pid 1 in the new pid ns): build the root, drop privileges, fork the
   real payload, and stay as init.
5. Parent waits on the pidfd, removes the session record and the run dir,
   exits with the payload's status.

## Mount setup with the new API

All targets are created and opened relative to the new root's fd, never by
host path, so a symlink planted by an earlier session can't redirect a mount.

1. `mount(NULL, "/", NULL, MS_REC | MS_PRIVATE)` once, so nothing propagates
   back to the host. (Or `mount_setattr(AT_RECURSIVE, propagation =
   MS_PRIVATE)` on `/`.)
2. New root: `fsopen("tmpfs")`, `fsconfig` (`mode=0755`, `size`), `fsmount`,
   keep the fd.
3. Each bind: `open_tree(src_fd, "", OPEN_TREE_CLONE | AT_RECURSIVE |
   AT_EMPTY_PATH)`. For read-only, `mount_setattr(tree_fd, "",
   AT_EMPTY_PATH | AT_RECURSIVE, MOUNT_ATTR_RDONLY | MOUNT_ATTR_NOSUID |
   MOUNT_ATTR_NODEV)` on the detached tree, before it is attached. That makes
   the whole subtree read-only in one call, with no remount pass and no
   window where it is writable. Locked flags from the source stay set, the
   kernel refuses to clear them, which is what we want.
4. Create the target under the root fd (`mkdirat`/`openat` with
   `O_CREAT | O_EXCL`, parents with `RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS`),
   then `move_mount(tree_fd, "", target_dir_fd, "", MOVE_MOUNT_F_EMPTY_PATH |
   MOVE_MOUNT_T_EMPTY_PATH)`.
5. Files written in (`/etc/hosts`, CLAUDE.md, settings.json): write them on a
   small tmpfs or into the root tmpfs before it is made read-only, or bind a
   memfd. No host temp files.
6. `/proc`: `fsopen("proc")`, `fsconfig` `subset=pid` and `hidepid=invisible`,
   `fsmount`, `move_mount`. Must happen inside the new pid ns (in the child).
7. `/dev`: tmpfs, then binds of `null`, `zero`, `full`, `random`, `urandom`,
   `tty`, a fresh `devpts` (`newinstance`, `ptmxmode=0666`) with `/dev/ptmx`
   as a symlink, `/dev/shm` tmpfs, plus `--dev-bind` nodes.
8. Make the root itself read-only where wanted with `mount_setattr`, then
   `move_mount` it over `/`, or `pivot_root` into it and detach the old root
   with `umount2(MNT_DETACH)`.

Dev shell closures of thousands of paths: one `open_tree` + `move_mount` per
path is still cheap. Measure before optimizing. The fallback is binding all of
`/nix/store` read-only, as nix daemon mode already does.

## Privileges

- `PR_SET_NO_NEW_PRIVS`.
- Clear the bounding set, ambient, inheritable, permitted and effective caps,
  except the two kept for `--netif` (then via a nested user ns as uid 0,
  like bwrap's `--uid 0 --cap-add`).
- `PR_SET_PDEATHSIG(SIGKILL)` on the payload, and check the parent is still
  alive right after setting it.
- Close every fd except stdio and the ones passed on purpose (log fd).

## PID 1

- Fork the payload, forward `SIGINT`, `SIGTERM`, `SIGHUP`, `SIGWINCH` to it,
  reap every child (`waitpid(-1)`), exit with the payload's status when it
  exits.
- Terminal: keep the session (no `setsid`), as today.

## Nix side

- Replace the jail.nix combinators with a JSON config generated by
  `builtins.toJSON`: binds (src, dst, ro/rw, optional), files (content as a
  store path), env, deps for `PATH`. Read it at start.
- Store paths in the config are bare literals or package outputs, per the
  repo rule about derivations not pulling in the whole source.

## Crates

- `rustix` for `fsopen`, `fsconfig_*`, `fsmount`, `open_tree`, `move_mount`,
  `openat2`, `pivot_root`, `unshare`, caps and prctl.
- `mount_setattr` is missing from rustix 1.1.5 (listed as not implemented)
  and from `nix`. Check newer rustix first, otherwise one raw
  `syscall(SYS_mount_setattr, ...)` wrapper with `struct mount_attr`.
- `clone3` with `CLONE_PIDFD`: check rustix, else a raw syscall wrapper.
- `nix` is already a proxy dependency, reuse it for signals and pidfds.

## Pitfalls checklist

- `setgroups` = `deny` before `gid_map`, written by the parent.
- Propagation made private before any mount.
- Read-only applied to the detached tree, recursively, before attaching.
- No path-based mount target under a writable directory.
- `/proc` mounted from inside the new pid ns.
- Caps cleared before exec, not just dropped from effective.
- PID 1 reaps and forwards signals.
- Every inherited fd closed.
- Errors are typed (`thiserror`-style enum per stage), a failed mount aborts,
  never falls back to a weaker mount.

## Size estimate

| Part | Lines |
|---|---|
| Config from Nix and CLI flags | ~150 |
| Namespaces, uid/gid maps, sync, nested userns for `--netif` | ~150 |
| Mounts: root, binds, files, `/proc`, `/dev` | ~300 |
| Privilege dropping | ~60 |
| PID 1 | ~80 |
| Worktrees, dev shell closure, nix daemon | ~150 |
| Proxy unit, session record, netif move, cleanup | ~100 |
| Error types and logging | ~80 |
| Tests | ~150 |
| Total | ~1100 to 1300, plus ~100 lines of Nix |

## Testing and rollout

- Ship as `claude-next` next to `claude`, same config.
- Compare inside both: `/proc/self/mountinfo` (paths, `ro`, propagation),
  `/proc/self/status` (`CapEff`, `CapBnd`, `NoNewPrivs`, `Seccomp`), uid/gid
  maps, `ls -la /dev`, env, `readlink /proc/self/ns/*`.
- Negative tests: write to every read-only bind, mount from inside, `unshare
  -r` then remount, reach the host network, plant a symlink at a bind target
  and restart.
- Switch `claude` over once both match, keep bwrap reachable for a while.
