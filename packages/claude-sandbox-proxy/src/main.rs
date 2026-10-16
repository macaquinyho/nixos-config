use std::ffi::OsString;
use std::fmt;
use std::fs::File;
use std::io::{self, BufRead, ErrorKind, Write};
use std::net::SocketAddr;
use std::os::fd::FromRawFd;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use clap::Parser;
use fast_socks5::server::{Socks5ServerProtocol, SocksServerError};
use fast_socks5::util::target_addr::TargetAddr;
use fast_socks5::{ReplyError, Socks5Command, consts};
use log::{Level, Record};
use systemd_journal_logger::JournalLog;
use tokio::io::{
    AsyncBufRead, AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader,
};
use tokio::net::{TcpListener, TcpStream, UnixListener, UnixStream};
use tokio::process::Command;
use tokio::signal::unix::{SignalKind, signal};

const MAX_HEAD: u64 = 8 * 1024;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const IDLE_EXIT: Duration = Duration::from_secs(5 * 60);
const LOG_FD_VAR: &str = "CLAUDE_SANDBOX_LOG_FD";

#[derive(Parser)]
enum Cli {
    /// Serve on the unix socket passed by systemd socket activation, exit when idle
    Serve {
        /// Allowed destinations. A leading dot in HOST also allows its subdomains.
        #[arg(value_name = "HOST:PORT", required = true, value_parser = Allowed::parse)]
        allowed: Vec<Allowed>,
    },
    /// Forward ADDR to SOCKET while COMMAND runs, then exit with its status.
    /// Logs go to the fd in CLAUDE_SANDBOX_LOG_FD, if set.
    Bridge {
        addr: SocketAddr,
        socket: PathBuf,
        #[arg(last = true, required = true)]
        command: Vec<OsString>,
    },
    /// Copy stdin to the journal as warnings, like systemd-cat
    Journal { identifier: String },
}

#[derive(Debug)]
enum Error {
    NoListenFd,
    ListenFd(io::Error),
    BindTcp(SocketAddr, io::Error),
    Spawn(io::Error),
    Journal(io::Error),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Error::NoListenFd => f.write_str("no socket from systemd (LISTEN_FDS)"),
            Error::ListenFd(e) => write!(f, "socket from systemd: {e}"),
            Error::BindTcp(addr, e) => write!(f, "bind {addr}: {e}"),
            Error::Spawn(e) => write!(f, "spawn: {e}"),
            Error::Journal(e) => write!(f, "journal: {e}"),
        }
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    let result = match Cli::parse() {
        Cli::Serve { allowed } => serve(allowed).await.map(|()| ExitCode::SUCCESS),
        Cli::Bridge {
            addr,
            socket,
            command,
        } => bridge(addr, socket, command).await,
        Cli::Journal { identifier } => journal(identifier).map(|()| ExitCode::SUCCESS),
    };
    result.unwrap_or_else(|e| {
        eprintln!("claude-sandbox-proxy: {e}");
        ExitCode::from(2)
    })
}

#[derive(Clone)]
struct Allowed {
    host: String,
    port: u16,
    subdomains: bool,
}

impl Allowed {
    fn parse(s: &str) -> Result<Self, String> {
        let invalid = || format!("expected HOST:PORT, got {s}");
        let (host, port) = s.rsplit_once(':').ok_or_else(invalid)?;
        let (host, subdomains) = match host.strip_prefix('.') {
            Some(parent) => (parent, true),
            None => (host, false),
        };
        Ok(Allowed {
            host: host.to_ascii_lowercase(),
            port: port.parse().map_err(|_| invalid())?,
            subdomains,
        })
    }

    fn matches(&self, host: &str, port: u16) -> bool {
        let subdomain = || {
            host.strip_suffix(&self.host)
                .is_some_and(|rest| rest.ends_with('.'))
        };
        port == self.port && (host == self.host || self.subdomains && subdomain())
    }
}

fn normalize_host(host: &str) -> String {
    host.trim_end_matches('.').to_ascii_lowercase()
}

async fn serve(allowed: Vec<Allowed>) -> Result<(), Error> {
    let allowed: Arc<[Allowed]> = allowed.into();
    let listener = listen_fd()?;
    // every open tunnel holds a clone
    let tunnels = Arc::new(());
    loop {
        let accepted = match tokio::time::timeout(IDLE_EXIT, listener.accept()).await {
            Ok(accepted) => accepted,
            // systemd keeps listening and starts us again on the next connection
            Err(_) if Arc::strong_count(&tunnels) == 1 => return Ok(()),
            Err(_) => continue,
        };
        let client = match accepted {
            Ok((client, _)) => client,
            Err(e) => {
                eprintln!("accept: {e}");
                continue;
            }
        };
        let (allowed, tunnel_ref) = (allowed.clone(), tunnels.clone());
        tokio::spawn(async move {
            let _tunnel_ref = tunnel_ref;
            if let Err(e) = tunnel(client, &allowed).await {
                eprintln!("{e}");
            }
        });
    }
}

fn listen_fd() -> Result<UnixListener, Error> {
    let ours = std::env::var("LISTEN_PID").ok() == Some(std::process::id().to_string());
    if !ours || std::env::var("LISTEN_FDS").ok().as_deref() != Some("1") {
        return Err(Error::NoListenFd);
    }
    // SAFETY: with LISTEN_PID and LISTEN_FDS=1, systemd passed exactly one socket as fd 3
    let listener = unsafe { std::os::unix::net::UnixListener::from_raw_fd(3) };
    listener.set_nonblocking(true).map_err(Error::ListenFd)?;
    UnixListener::from_std(listener).map_err(Error::ListenFd)
}

trait Stream: AsyncRead + AsyncWrite + Unpin {}
impl<T: AsyncRead + AsyncWrite + Unpin> Stream for T {}

struct Tunnel<S> {
    target: String,
    client: S,
    upstream: TcpStream,
}

async fn tunnel(client: UnixStream, allowed: &[Allowed]) -> Result<(), String> {
    let mut client = BufReader::new(client);
    let Some(&first) = client
        .fill_buf()
        .await
        .map_err(|e| format!("read: {e}"))?
        .first()
    else {
        return Ok(());
    };
    let Tunnel {
        target,
        mut client,
        mut upstream,
    } = if first == consts::SOCKS5_VERSION {
        socks5(client, allowed).await?
    } else {
        http_connect(client, allowed).await?
    };
    splice(&mut client, &mut upstream)
        .await
        .map_err(|e| format!("{target}: {e}"))
}

enum Refused {
    Denied,
    Failed(io::Error),
    TimedOut,
}

impl fmt::Display for Refused {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Refused::Denied => f.write_str("denied"),
            Refused::Failed(e) => write!(f, "{e}"),
            Refused::TimedOut => f.write_str("connect timed out"),
        }
    }
}

async fn dial(host: &str, port: u16, allowed: &[Allowed]) -> Result<TcpStream, Refused> {
    if !allowed.iter().any(|a| a.matches(host, port)) {
        return Err(Refused::Denied);
    }
    let upstream = tokio::time::timeout(CONNECT_TIMEOUT, TcpStream::connect((host, port)))
        .await
        .map_err(|_| Refused::TimedOut)?
        .map_err(Refused::Failed)?;
    let _ = upstream.set_nodelay(true);
    Ok(upstream)
}

async fn http_connect<S: Stream + AsyncBufRead>(
    mut client: S,
    allowed: &[Allowed],
) -> Result<Tunnel<S>, String> {
    let mut head = (&mut client).take(MAX_HEAD);
    let mut request = String::new();
    head.read_line(&mut request)
        .await
        .map_err(|e| format!("read: {e}"))?;
    loop {
        let mut header = String::new();
        match head.read_line(&mut header).await {
            Ok(0) => return Err("request head truncated or too large".into()),
            Ok(_) if header.trim_end().is_empty() => break,
            Ok(_) => {}
            Err(e) => return Err(format!("read: {e}")),
        }
    }

    let mut words = request.split_whitespace();
    let (method, target) = (words.next().unwrap_or(""), words.next().unwrap_or(""));
    if method != "CONNECT" {
        http_reply(&mut client, "405 Method Not Allowed").await;
        return Err(format!("{method} {target}: only CONNECT is supported"));
    }
    let Some((host, port)) = target
        .rsplit_once(':')
        .and_then(|(host, port)| Some((normalize_host(host), port.parse().ok()?)))
    else {
        http_reply(&mut client, "400 Bad Request").await;
        return Err(format!("bad CONNECT target {target}"));
    };
    let target = format!("{host}:{port}");

    let upstream = match dial(&host, port, allowed).await {
        Ok(upstream) => upstream,
        Err(refused) => {
            let status = match refused {
                Refused::Denied => "403 Forbidden",
                Refused::Failed(_) => "502 Bad Gateway",
                Refused::TimedOut => "504 Gateway Timeout",
            };
            http_reply(&mut client, status).await;
            return Err(format!("{target}: {refused}"));
        }
    };
    client
        .write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        .await
        .map_err(|e| format!("{target}: {e}"))?;
    Ok(Tunnel {
        target,
        client,
        upstream,
    })
}

async fn http_reply<S: Stream>(client: &mut S, status: &str) {
    let reply = format!("HTTP/1.1 {status}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    let _ = client.write_all(reply.as_bytes()).await;
}

async fn socks5<S: Stream>(client: S, allowed: &[Allowed]) -> Result<Tunnel<S>, String> {
    let socks_err = |e: SocksServerError| format!("socks5: {e}");
    let (proto, command, addr) = Socks5ServerProtocol::accept_no_auth(client)
        .await
        .map_err(socks_err)?
        .read_command()
        .await
        .map_err(socks_err)?;

    let (host, port) = match addr {
        TargetAddr::Domain(host, port) => (normalize_host(&host), port),
        TargetAddr::Ip(addr) => (addr.ip().to_string(), addr.port()),
    };
    let target = format!("{host}:{port}");
    if command != Socks5Command::TCPConnect {
        let _ = proto.reply_error(&ReplyError::CommandNotSupported).await;
        return Err(format!("{target}: socks5 {command:?} is not supported"));
    }

    match dial(&host, port, allowed).await {
        Ok(upstream) => {
            // clients ignore the bound address for CONNECT
            let client = proto
                .reply_success(SocketAddr::from(([0, 0, 0, 0], 0)))
                .await
                .map_err(socks_err)?;
            Ok(Tunnel {
                target,
                client,
                upstream,
            })
        }
        Err(refused) => {
            let reply = match &refused {
                Refused::Denied => ReplyError::ConnectionNotAllowed,
                Refused::Failed(e) if e.kind() == ErrorKind::ConnectionRefused => {
                    ReplyError::ConnectionRefused
                }
                Refused::Failed(_) => ReplyError::HostUnreachable,
                Refused::TimedOut => ReplyError::ConnectionTimeout,
            };
            let _ = proto.reply_error(&reply).await;
            Err(format!("{target}: {refused}"))
        }
    }
}

async fn splice(a: &mut impl Stream, b: &mut impl Stream) -> io::Result<()> {
    match tokio::io::copy_bidirectional(a, b).await {
        // a peer hanging up mid-stream is how most tunnels end
        Err(e) if !matches!(e.kind(), ErrorKind::ConnectionReset | ErrorKind::BrokenPipe) => Err(e),
        _ => Ok(()),
    }
}

fn take_log_fd() -> Option<File> {
    let fd = std::env::var(LOG_FD_VAR).ok()?.parse().ok()?;
    // SAFETY: the launcher opened this fd for us and nothing else in this process uses it
    let inherited = unsafe { File::from_raw_fd(fd) };
    // the clone is O_CLOEXEC, so dropping the original keeps the fd out of the child
    inherited.try_clone().ok()
}

fn log(log: Option<&File>, msg: impl fmt::Display) {
    if let Some(mut file) = log {
        // one write per line, so concurrent connections don't interleave
        let _ = file.write_all(format!("{msg}\n").as_bytes());
    }
}

async fn bridge(
    addr: SocketAddr,
    socket: PathBuf,
    command: Vec<OsString>,
) -> Result<ExitCode, Error> {
    let socket: Arc<Path> = socket.into();
    let log_file = take_log_fd().map(Arc::new);
    let listener = TcpListener::bind(addr)
        .await
        .map_err(|e| Error::BindTcp(addr, e))?;

    // ^C belongs to the command, the bridge has to outlive it
    let _sigint = signal(SignalKind::interrupt());
    let _sigquit = signal(SignalKind::quit());

    let Some((program, args)) = command.split_first() else {
        return Err(Error::Spawn(ErrorKind::InvalidInput.into()));
    };
    let mut child = Command::new(program)
        .args(args)
        .env_remove(LOG_FD_VAR)
        .spawn()
        .map_err(Error::Spawn)?;

    let status = loop {
        let accepted = tokio::select! {
            status = child.wait() => break status.map_err(Error::Spawn)?,
            accepted = listener.accept() => accepted,
        };
        let mut client = match accepted {
            Ok((client, _)) => client,
            Err(e) => {
                log(log_file.as_deref(), format_args!("accept: {e}"));
                continue;
            }
        };
        let _ = client.set_nodelay(true);
        let (socket, log_file) = (socket.clone(), log_file.clone());
        tokio::spawn(async move {
            let result = match UnixStream::connect(&socket).await {
                Ok(mut upstream) => splice(&mut client, &mut upstream).await,
                Err(e) => Err(e),
            };
            if let Err(e) = result {
                log(
                    log_file.as_deref(),
                    format_args!("{}: {e}", socket.display()),
                );
            }
        });
    };

    let code = status.code().or(status.signal().map(|signal| 128 + signal));
    Ok(code.map_or(ExitCode::FAILURE, |code| ExitCode::from(code as u8)))
}

fn journal(identifier: String) -> Result<(), Error> {
    let journal = JournalLog::empty()
        .map_err(Error::Journal)?
        .with_syslog_identifier(identifier);
    for line in io::stdin().lock().lines() {
        let line = line.map_err(Error::Journal)?;
        journal
            .journal_send(
                &Record::builder()
                    .level(Level::Warn)
                    .args(format_args!("{line}"))
                    .build(),
            )
            .map_err(Error::Journal)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::Allowed;

    #[test]
    fn allowlist() -> Result<(), String> {
        let exact = Allowed::parse("api.anthropic.com:443")?;
        assert!(exact.matches("api.anthropic.com", 443));
        assert!(!exact.matches("api.anthropic.com", 80));
        assert!(!exact.matches("x.api.anthropic.com", 443));

        let sub = Allowed::parse(".github.com:443")?;
        assert!(sub.matches("github.com", 443));
        assert!(sub.matches("api.github.com", 443));
        assert!(!sub.matches("evilgithub.com", 443));
        assert!(!sub.matches("github.com.evil.io", 443));
        Ok(())
    }
}
