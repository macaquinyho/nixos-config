//! Per-session allowlists, and the host prompt that adds to them.
//!
//! A session is a sandbox's network namespace. The launcher records it in
//! `DIR/NETNS/{pid,cwd,allow}`, a directory the sandbox can't see.

use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{self, Write};
use std::net::IpAddr;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{Mutex, PoisonError};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use nix::sys::signal::{Signal, kill};
use nix::sys::socket::{getsockopt, sockopt::PeerPidfd};
use nix::unistd::Pid;
use tokio::io::AsyncReadExt;
use tokio::net::UnixStream;
use tokio::process::Command;

use crate::Allowed;

const PROMPT_TIMEOUT: Duration = Duration::from_secs(60);
const DENY_MEMORY: Duration = Duration::from_secs(10 * 60);
const ALLOW_HOUR: u64 = 3600;
const MAX_REASON: usize = 100;

pub struct Sessions {
    dir: PathBuf,
    notify: Option<PathBuf>,
    // one notification at a time, for every session
    prompting: tokio::sync::Mutex<()>,
    denied: Mutex<HashMap<(u64, String), Instant>>,
}

pub struct Session {
    dir: PathBuf,
    netns: u64,
}

impl Sessions {
    pub fn new(dir: PathBuf, notify: Option<PathBuf>) -> Self {
        Sessions {
            dir,
            notify,
            prompting: tokio::sync::Mutex::new(()),
            denied: Mutex::new(HashMap::new()),
        }
    }

    /// The session of the process at the other end of CLIENT, if it is a live one
    pub fn of(&self, client: &UnixStream) -> Option<Session> {
        let netns = peer_netns(client)
            .map_err(|e| eprintln!("peer netns: {e}"))
            .ok()?;
        let session = Session {
            dir: self.dir.join(netns.to_string()),
            netns,
        };
        session.live().then_some(session)
    }

    /// Asks on the host whether SESSION may reach HOST:PORT, and records a yes
    pub async fn prompt(&self, session: &Session, host: &str, port: u16, reason: &str) -> bool {
        let Some(notify) = &self.notify else {
            return false;
        };
        if !promptable(host) {
            return false;
        }
        let dest = format!("{host}:{port}");
        let key = (session.netns, dest.clone());
        if self.recently_denied(&key) {
            return false;
        }
        let Ok(_turn) = tokio::time::timeout(PROMPT_TIMEOUT, self.prompting.lock()).await else {
            return false;
        };
        // settled by the prompt we waited behind
        if session.allows(host, port) {
            return true;
        }
        if self.recently_denied(&key) {
            return false;
        }

        let expires = match ask(notify, session, host, &dest, reason).await {
            Some(Answer::Hour) => Some(now() + ALLOW_HOUR),
            Some(Answer::Session) => None,
            None => {
                eprintln!("{dest}: denied at the prompt");
                let mut denied = self.denied.lock().unwrap_or_else(PoisonError::into_inner);
                denied.retain(|_, at| at.elapsed() < DENY_MEMORY);
                denied.insert(key, Instant::now());
                return false;
            }
        };
        match session.allow(&dest, expires) {
            Ok(()) => {
                eprintln!("{dest}: allowed at the prompt");
                true
            }
            Err(e) => {
                eprintln!("{dest}: recording the allow: {e}");
                false
            }
        }
    }

    fn recently_denied(&self, key: &(u64, String)) -> bool {
        let denied = self.denied.lock().unwrap_or_else(PoisonError::into_inner);
        denied.get(key).is_some_and(|at| at.elapsed() < DENY_MEMORY)
    }
}

impl Session {
    /// A record left behind by a killed launcher must not match a reused inode
    fn live(&self) -> bool {
        std::fs::read_to_string(self.dir.join("pid"))
            .ok()
            .and_then(|pid| std::fs::metadata(format!("/proc/{}/ns/net", pid.trim())).ok())
            .is_some_and(|ns| ns.ino() == self.netns)
    }

    pub fn allows(&self, host: &str, port: u16) -> bool {
        std::fs::read_to_string(self.dir.join("allow")).is_ok_and(|text| {
            parse_allow(&text, now())
                .iter()
                .any(|a| a.matches(host, port))
        })
    }

    fn allow(&self, dest: &str, expires: Option<u64>) -> io::Result<()> {
        let expires = expires.map_or("-".to_owned(), |t| t.to_string());
        let mut file = OpenOptions::new()
            .append(true)
            .open(self.dir.join("allow"))?;
        // one write, so a concurrent reader never sees half a line
        file.write_all(format!("{dest} {expires}\n").as_bytes())
    }

    fn label(&self) -> String {
        std::fs::read_to_string(self.dir.join("cwd"))
            .map(|cwd| cwd.trim().to_owned())
            .unwrap_or_else(|_| "unknown session".into())
    }
}

enum Answer {
    Hour,
    Session,
}

async fn ask(
    notify: &Path,
    session: &Session,
    host: &str,
    dest: &str,
    reason: &str,
) -> Option<Answer> {
    let mut body = format!("{dest}\n{}", session.label());
    if !reason.is_empty() {
        body += &format!("\nClaude says: {reason}");
    }
    // no default action, so clicking the body or letting it lapse is a deny
    let mut child = Command::new(notify)
        .args(["--app-name=claude-sandbox", "--urgency=critical", "--wait"])
        .args([
            "--action=hour=Allow 1h",
            "--action=session=Allow for session",
        ])
        .args(["--action=deny=Deny", "--"])
        .arg(format!("Allow {}?", domain_hint(host)))
        .arg(escape_markup(&body))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| eprintln!("{dest}: {}: {e}", notify.display()))
        .ok()?;
    let mut stdout = child.stdout.take()?;
    let mut answer = String::new();
    let read = tokio::time::timeout(PROMPT_TIMEOUT, stdout.read_to_string(&mut answer)).await;
    if read.is_err() {
        // notify-send takes the notification down on SIGINT, not on a kill
        if let Some(pid) = child.id().and_then(|pid| i32::try_from(pid).ok()) {
            let _ = kill(Pid::from_raw(pid), Signal::SIGINT);
        }
        let _ = tokio::time::timeout(Duration::from_secs(2), child.wait()).await;
        return None;
    }
    match answer.trim() {
        "hour" => Some(Answer::Hour),
        "session" => Some(Answer::Session),
        _ => None,
    }
}

/// Lines of `HOST:PORT EXPIRES`, EXPIRES in unix seconds or `-` for never
fn parse_allow(text: &str, now: u64) -> Vec<Allowed> {
    text.lines()
        .filter_map(|line| {
            let (dest, expires) = line.split_once(' ').unwrap_or((line, "-"));
            let live = expires == "-" || expires.parse::<u64>().is_ok_and(|t| t > now);
            live.then(|| Allowed::parse(dest).ok()).flatten()
        })
        .collect()
}

/// A plain DNS name, so the prompt shows nothing misleading and no IP literal
fn promptable(host: &str) -> bool {
    let label = |l: &str| {
        (1..=63).contains(&l.len())
            && !l.starts_with('-')
            && !l.ends_with('-')
            && l.bytes()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-')
    };
    host.len() <= 253
        && host.parse::<IpAddr>().is_err()
        && host.contains('.')
        && host.split('.').all(label)
}

/// The last two labels, shown up front since a long name gets cut off at the end
fn domain_hint(host: &str) -> &str {
    let mut dots = host.rmatch_indices('.');
    match (dots.next(), dots.next()) {
        (Some(_), Some((i, _))) => &host[i + 1..],
        _ => host,
    }
}

/// The reason comes from inside the sandbox: one short line of plain text
pub fn clean_reason(reason: &str) -> String {
    reason
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .take(MAX_REASON)
        .collect::<String>()
        .trim()
        .to_owned()
}

// notification bodies are markup
fn escape_markup(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// Whether a host allowed at runtime may resolve to IP. Keeps a name pointed
/// at the LAN, localhost or cloud metadata from reaching them.
pub fn is_public(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            let [a, b, c, _] = v4.octets();
            !(v4.is_private()
                || v4.is_loopback()
                || v4.is_link_local()
                || v4.is_broadcast()
                || v4.is_documentation()
                || v4.is_multicast()
                || a == 0
                || a >= 240
                || (a == 100 && b & 0xc0 == 64)
                || (a == 198 && b & 0xfe == 18)
                || (a == 192 && b == 0 && c == 0))
        }
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => is_public(IpAddr::V4(v4)),
            None => {
                let s = v6.segments();
                // global unicast, minus 6to4 and Teredo, which wrap IPv4 addresses
                s[0] & 0xe000 == 0x2000 && s[0] != 0x2002 && !(s[0] == 0x2001 && s[1] == 0)
            }
        },
    }
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

// PIDFD_GET_NET_NAMESPACE from <linux/pidfd.h>, which nix doesn't wrap
nix::ioctl_none!(pidfd_get_net_namespace, 0xFF, 4);

/// Network namespace inode of the process that connected. Taken through its
/// pidfd, so a reused pid can't stand in for it.
fn peer_netns(client: &UnixStream) -> io::Result<u64> {
    let pidfd = getsockopt(client, PeerPidfd)?;
    // SAFETY: the ioctl takes no argument, and on success returns a new fd we now own
    let ns = unsafe { OwnedFd::from_raw_fd(pidfd_get_net_namespace(pidfd.as_raw_fd())?) };
    Ok(File::from(ns).metadata()?.ino())
}

#[cfg(test)]
mod tests {
    use super::{clean_reason, domain_hint, is_public, parse_allow, promptable};

    #[test]
    fn allow_file() {
        let text = "a.com:443 -\nb.com:443 99\nc.com:443 101\nd.com 200\nbad line\ne.com:443\n\n";
        let hosts: Vec<_> = parse_allow(text, 100).into_iter().map(|a| a.host).collect();
        assert_eq!(hosts, ["a.com", "c.com", "e.com"]);
    }

    #[test]
    fn public_ips() {
        for ip in [
            "1.1.1.1",
            "93.184.215.14",
            "2606:4700::1111",
            "::ffff:1.1.1.1",
        ] {
            assert!(
                is_public(ip.parse().unwrap_or_else(|_| panic!("{ip}"))),
                "{ip}"
            );
        }
        for ip in [
            "10.1.2.3",
            "172.16.0.1",
            "192.168.1.1",
            "127.0.0.1",
            "169.254.169.254",
            "100.64.0.1",
            "0.0.0.0",
            "255.255.255.255",
            "224.0.0.1",
            "198.18.0.1",
            "192.0.0.1",
            "240.0.0.1",
            "::1",
            "::",
            "fd00::1",
            "fe80::1",
            "ff02::1",
            "::ffff:10.0.0.1",
            "64:ff9b::a00:1",
            "2002:a00:1::1",
            "2001:0:a00:1::1",
        ] {
            assert!(
                !is_public(ip.parse().unwrap_or_else(|_| panic!("{ip}"))),
                "{ip}"
            );
        }
    }

    #[test]
    fn prompt_text() {
        assert!(promptable("docs.rs"));
        assert!(promptable("a-b.example.co.uk"));
        for bad in [
            "localhost",
            "1.2.3.4",
            "::1",
            "a..b",
            "-a.com",
            "a_b.com",
            "xn--éx.com",
            "",
        ] {
            assert!(!promptable(bad), "{bad}");
        }
        assert_eq!(domain_hint("docs.rust-lang.org.evil.io"), "evil.io");
        assert_eq!(domain_hint("docs.rs"), "docs.rs");
        assert_eq!(
            clean_reason(" need\r\nthe <b>docs</b> "),
            "need  the <b>docs</b>"
        );
        assert_eq!(clean_reason(&"x".repeat(500)).len(), 100);
    }
}
