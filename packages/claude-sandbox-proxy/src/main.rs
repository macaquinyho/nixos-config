use std::ffi::OsString;
use std::fmt;
use std::fs::File;
use std::io::{self, BufRead, ErrorKind, IoSlice, IoSliceMut, Read, Write};
use std::mem::MaybeUninit;
use std::net::SocketAddr;
use std::os::fd::{AsFd, FromRawFd, OwnedFd};
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{ExitCode, Stdio};
use std::sync::Arc;
use std::time::Duration;

use clap::Parser;
use fast_socks5::server::{Socks5ServerProtocol, SocksServerError};
use fast_socks5::util::target_addr::TargetAddr;
use fast_socks5::{ReplyError, Socks5Command, consts};
use log::{Level, Record};
use rustix::net::{
    RecvAncillaryBuffer, RecvAncillaryMessage, RecvFlags, SendAncillaryBuffer,
    SendAncillaryMessage, SendFlags,
};
use systemd_journal_logger::JournalLog;
use tokio::io::{
    AsyncBufRead, AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader,
    Interest,
};
use tokio::net::{TcpListener, TcpStream, UnixListener, UnixStream};
use tokio::process::Command;
use tokio::signal::unix::{SignalKind, signal};

mod session;
use session::{Session, Sessions};

const MAX_HEAD: u64 = 8 * 1024;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const IDLE_EXIT: Duration = Duration::from_secs(5 * 60);
const LOG_FD_VAR: &str = "CLAUDE_SANDBOX_LOG_FD";
// first byte of a git-ssh request, never the start of SOCKS5 or HTTP
const GIT_SSH_MAGIC: u8 = 0;
// exit status for a refused git-ssh request, like ssh's own failures
const GIT_SSH_REFUSED: u8 = 255;
// lets the host prompt show why a CONNECT is asked for
const REASON_HEADER: &str = "x-sandbox-reason";

#[derive(Parser)]
enum Cli {
    /// Serve on the unix socket passed by systemd socket activation, exit when idle
    Serve {
        /// Host that git-ssh requests may fetch from, over ssh as git@HOST
        #[arg(long = "git-ssh-host", value_name = "HOST")]
        git_ssh_hosts: Vec<String>,
        /// ssh client run for git-ssh requests
        #[arg(long, default_value = "ssh")]
        ssh: PathBuf,
        /// Per-session allowlists, in DIR/NETNS/allow, where NETNS is the inode
        /// of the connecting process's network namespace
        #[arg(long, value_name = "DIR")]
        sessions: Option<PathBuf>,
        /// notify-send, to ask on the host about a session's denied destinations
        #[arg(long, requires = "sessions")]
        notify: Option<PathBuf>,
        /// Allowed destinations. A leading dot in HOST also allows its subdomains.
        #[arg(value_name = "HOST:PORT", required = true, value_parser = Allowed::parse)]
        allowed: Vec<Allowed>,
    },
    /// Run as git's ssh command: ask the proxy behind SOCKET to run git-upload-pack
    /// on the host, with this process's stdio
    GitSsh {
        socket: PathBuf,
        /// ssh arguments, as git passes them with ssh.variant=ssh
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// Forward ADDR to SOCKET while COMMAND runs, then exit with its status.
    /// Logs go to the fd in CLAUDE_SANDBOX_LOG_FD, if set.
    Bridge {
        addr: SocketAddr,
        socket: PathBuf,
        #[arg(last = true, required = true)]
        command: Vec<OsString>,
    },
    /// Ask the proxy behind SOCKET to let this session reach HOST[:PORT],
    /// which may prompt on the host, and wait for the answer
    Request {
        socket: PathBuf,
        #[arg(value_name = "HOST[:PORT]")]
        dest: String,
        /// Shown in the prompt
        #[arg(default_value = "")]
        reason: String,
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
    GitSshArgs(String),
    GitSsh(io::Error),
    Request(io::Error),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Error::NoListenFd => f.write_str("no socket from systemd (LISTEN_FDS)"),
            Error::ListenFd(e) => write!(f, "socket from systemd: {e}"),
            Error::BindTcp(addr, e) => write!(f, "bind {addr}: {e}"),
            Error::Spawn(e) => write!(f, "spawn: {e}"),
            Error::Journal(e) => write!(f, "journal: {e}"),
            Error::GitSshArgs(e) => write!(f, "git-ssh: {e}"),
            Error::GitSsh(e) => write!(f, "git-ssh: {e}"),
            Error::Request(e) => write!(f, "request: {e}"),
        }
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    let result = match Cli::parse() {
        Cli::Serve {
            git_ssh_hosts,
            ssh,
            sessions,
            notify,
            allowed,
        } => serve(Config {
            allowed,
            git_ssh_hosts: git_ssh_hosts.iter().map(|h| normalize_host(h)).collect(),
            ssh,
            sessions: sessions.map(|dir| Sessions::new(dir, notify)),
        })
        .await
        .map(|()| ExitCode::SUCCESS),
        Cli::GitSsh { socket, args } => git_ssh_client(&socket, &args),
        Cli::Bridge {
            addr,
            socket,
            command,
        } => bridge(addr, socket, command).await,
        Cli::Request {
            socket,
            dest,
            reason,
        } => request(&socket, &dest, &reason),
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

struct Config {
    allowed: Vec<Allowed>,
    git_ssh_hosts: Vec<String>,
    ssh: PathBuf,
    sessions: Option<Sessions>,
}

async fn serve(config: Config) -> Result<(), Error> {
    let config = Arc::new(config);
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
        let (config, tunnel_ref) = (config.clone(), tunnels.clone());
        tokio::spawn(async move {
            let _tunnel_ref = tunnel_ref;
            if let Err(e) = tunnel(client, &config).await {
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

async fn tunnel(client: UnixStream, config: &Config) -> Result<(), String> {
    // peeked, as a plain read would drop the fds a git-ssh request carries
    let mut first = [0u8];
    let peeked = client
        .async_io(Interest::READABLE, || {
            rustix::net::recv(&client, &mut first[..], RecvFlags::PEEK)
                .map(|(_, n)| n)
                .map_err(io::Error::from)
        })
        .await
        .map_err(|e| format!("read: {e}"))?;
    let [first] = first;
    if peeked == 0 {
        return Ok(());
    }
    if first == GIT_SSH_MAGIC {
        return git_ssh_serve(client, config).await;
    }
    let session = config.sessions.as_ref().and_then(|s| s.of(&client));
    let session = session.as_ref();
    let client = BufReader::new(client);
    let Tunnel {
        target,
        mut client,
        mut upstream,
    } = if first == consts::SOCKS5_VERSION {
        socks5(client, config, session).await?
    } else {
        http_connect(client, config, session).await?
    };
    splice(&mut client, &mut upstream)
        .await
        .map_err(|e| format!("{target}: {e}"))
}

enum Refused {
    Denied,
    Private,
    Failed(io::Error),
    TimedOut,
}

impl fmt::Display for Refused {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Refused::Denied => f.write_str("denied"),
            Refused::Private => f.write_str("resolves to no public address"),
            Refused::Failed(e) => write!(f, "{e}"),
            Refused::TimedOut => f.write_str("connect timed out"),
        }
    }
}

async fn dial(
    host: &str,
    port: u16,
    config: &Config,
    session: Option<&Session>,
    reason: &str,
) -> Result<TcpStream, Refused> {
    if config.allowed.iter().any(|a| a.matches(host, port)) {
        return connect((host, port)).await;
    }
    let (Some(sessions), Some(session)) = (&config.sessions, session) else {
        return Err(Refused::Denied);
    };
    if !session.allows(host, port) && !sessions.prompt(session, host, port, reason).await {
        return Err(Refused::Denied);
    }
    // only the addresses checked here are dialed, so DNS can't change its answer
    let addrs = tokio::time::timeout(CONNECT_TIMEOUT, tokio::net::lookup_host((host, port)))
        .await
        .map_err(|_| Refused::TimedOut)?
        .map_err(Refused::Failed)?
        .filter(|addr| session::is_public(addr.ip()))
        .collect::<Vec<_>>();
    if addrs.is_empty() {
        return Err(Refused::Private);
    }
    connect(&addrs[..]).await
}

async fn connect(addr: impl tokio::net::ToSocketAddrs) -> Result<TcpStream, Refused> {
    let upstream = tokio::time::timeout(CONNECT_TIMEOUT, TcpStream::connect(addr))
        .await
        .map_err(|_| Refused::TimedOut)?
        .map_err(Refused::Failed)?;
    let _ = upstream.set_nodelay(true);
    Ok(upstream)
}

async fn http_connect<S: Stream + AsyncBufRead>(
    mut client: S,
    config: &Config,
    session: Option<&Session>,
) -> Result<Tunnel<S>, String> {
    let mut head = (&mut client).take(MAX_HEAD);
    let mut request = String::new();
    head.read_line(&mut request)
        .await
        .map_err(|e| format!("read: {e}"))?;
    let mut reason = String::new();
    loop {
        let mut header = String::new();
        match head.read_line(&mut header).await {
            Ok(0) => return Err("request head truncated or too large".into()),
            Ok(_) if header.trim_end().is_empty() => break,
            Ok(_) => {}
            Err(e) => return Err(format!("read: {e}")),
        }
        if let Some((name, value)) = header.split_once(':')
            && name.eq_ignore_ascii_case(REASON_HEADER)
        {
            reason = session::clean_reason(value);
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

    let upstream = match dial(&host, port, config, session, &reason).await {
        Ok(upstream) => upstream,
        Err(refused) => {
            let status = match refused {
                Refused::Denied | Refused::Private => "403 Forbidden",
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

async fn socks5<S: Stream>(
    client: S,
    config: &Config,
    session: Option<&Session>,
) -> Result<Tunnel<S>, String> {
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

    match dial(&host, port, config, session, "").await {
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
                Refused::Denied | Refused::Private => ReplyError::ConnectionNotAllowed,
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

struct GitSshRequest {
    host: String,
    port: Option<u16>,
    command: String,
    protocol: Option<String>,
}

impl GitSshRequest {
    /// Parses DEST\0PORT\0COMMAND\0GIT_PROTOCOL, and only lets through
    /// git-upload-pack on an allowed host, which is a fetch and never a push
    fn parse(payload: &[u8], hosts: &[String]) -> Result<Self, String> {
        let payload = std::str::from_utf8(payload).map_err(|_| "request is not UTF-8")?;
        let [dest, port, command, protocol] = payload
            .split('\0')
            .collect::<Vec<_>>()
            .try_into()
            .map_err(|_| "malformed request")?;

        let host = dest
            .strip_prefix("git@")
            .map(normalize_host)
            .filter(|host| hosts.contains(host))
            .ok_or_else(|| format!("{dest} is not an allowed git host"))?;
        let port = match port {
            "" => None,
            port => Some(
                port.parse()
                    .ok()
                    .filter(|&p| p != 0)
                    .ok_or_else(|| format!("bad port {port}"))?,
            ),
        };
        // git quotes the path in single quotes, anything else is refused
        let path = command
            .strip_prefix("git-upload-pack '")
            .and_then(|rest| rest.strip_suffix('\''))
            .filter(|path| {
                !path.is_empty()
                    && !path.contains(['\'', '\\'])
                    && !path.chars().any(char::is_control)
            });
        if path.is_none() {
            return Err(format!(
                "only git-upload-pack (fetch) is allowed, not {command:?}"
            ));
        }
        let protocol = match protocol {
            "" => None,
            "version=1" | "version=2" => Some(protocol.to_owned()),
            _ => return Err(format!("bad GIT_PROTOCOL {protocol:?}")),
        };
        Ok(GitSshRequest {
            host,
            port,
            command: command.to_owned(),
            protocol,
        })
    }
}

async fn git_ssh_serve(mut client: UnixStream, config: &Config) -> Result<(), String> {
    let (mut buf, fds) = recv_with_fds(&client)
        .await
        .map_err(|e| format!("git-ssh: read: {e}"))?;
    let len = match buf.get(1..3) {
        Some(&[hi, lo]) => 3 + usize::from(u16::from_be_bytes([hi, lo])),
        _ => return Err("git-ssh: truncated request".into()),
    };
    if buf.len() < len {
        let have = buf.len();
        buf.resize(len, 0);
        client
            .read_exact(&mut buf[have..])
            .await
            .map_err(|e| format!("git-ssh: read: {e}"))?;
    }
    let Ok([stdin, stdout, stderr]): Result<[OwnedFd; 3], _> = fds.try_into() else {
        let _ = client.write_u8(GIT_SSH_REFUSED).await;
        return Err("git-ssh: expected stdin, stdout and stderr".into());
    };

    let request = match GitSshRequest::parse(&buf[3..len], &config.git_ssh_hosts) {
        Ok(request) => request,
        Err(e) => {
            let _ = File::from(stderr).write_all(format!("claude-sandbox: {e}\n").as_bytes());
            let _ = client.write_u8(GIT_SSH_REFUSED).await;
            return Err(format!("git-ssh: {e}"));
        }
    };
    let target = format!("git@{}: {}", request.host, request.command);
    eprintln!("git-ssh {target}");

    let mut child = {
        let mut ssh = Command::new(&config.ssh);
        // whatever ~/.ssh/config says, the session only runs the fetch
        ssh.args(["-x", "-a", "-T", "-o", "BatchMode=yes"])
            .args([
                "-o",
                "ClearAllForwardings=yes",
                "-o",
                "PermitLocalCommand=no",
            ])
            .env_remove("GIT_PROTOCOL");
        if let Some(port) = request.port {
            ssh.arg("-p").arg(port.to_string());
        }
        if let Some(protocol) = &request.protocol {
            ssh.args(["-o", "SendEnv=GIT_PROTOCOL"])
                .env("GIT_PROTOCOL", protocol);
        }
        ssh.arg("--")
            .arg(format!("git@{}", request.host))
            .arg(&request.command)
            .stdin(Stdio::from(stdin))
            .stdout(Stdio::from(stdout))
            .stderr(Stdio::from(stderr))
            .kill_on_drop(true);
        // dropping the command closes our copies of the client's stdio
        ssh.spawn().map_err(|e| format!("git-ssh {target}: {e}"))?
    };

    let status = tokio::select! {
        status = child.wait() => status.map_err(|e| format!("git-ssh {target}: {e}"))?,
        // the client sends nothing more, so this only returns when it is gone
        _ = client.read_u8() => return Err(format!("git-ssh {target}: client went away")),
    };
    let code = status.code().or(status.signal().map(|signal| 128 + signal));
    let code = code.map_or(GIT_SSH_REFUSED, |code| code.clamp(0, 255) as u8);
    client
        .write_u8(code)
        .await
        .map_err(|e| format!("git-ssh {target}: {e}"))
}

async fn recv_with_fds(client: &UnixStream) -> io::Result<(Vec<u8>, Vec<OwnedFd>)> {
    let mut buf = vec![0u8; 3 + usize::from(u16::MAX)];
    let mut space = [MaybeUninit::uninit(); rustix::cmsg_space!(ScmRights(3))];
    let mut control = RecvAncillaryBuffer::new(&mut space);
    let n = client
        .async_io(Interest::READABLE, || {
            rustix::net::recvmsg(
                client,
                &mut [IoSliceMut::new(&mut buf)],
                &mut control,
                RecvFlags::CMSG_CLOEXEC,
            )
            .map(|msg| msg.bytes)
            .map_err(io::Error::from)
        })
        .await?;
    buf.truncate(n);
    let mut fds = Vec::new();
    for msg in control.drain() {
        if let RecvAncillaryMessage::ScmRights(received) = msg {
            fds.extend(received);
        }
    }
    Ok((buf, fds))
}

/// Splits git's ssh arguments, `[-o OPT] [-p PORT] [-4|-6] DEST COMMAND...`
fn parse_ssh_args(args: &[String]) -> Result<(&str, &str, String), String> {
    let mut port = "";
    let mut args = args.iter().map(String::as_str);
    let dest = loop {
        match args.next().ok_or("no destination")? {
            "-p" => port = args.next().ok_or("-p needs a port")?,
            // SendEnv=GIT_PROTOCOL, which the proxy sets itself
            "-o" => _ = args.next().ok_or("-o needs an option")?,
            "-4" | "-6" => {}
            "--" => break args.next().ok_or("no destination")?,
            opt if opt.starts_with('-') => return Err(format!("unsupported ssh option {opt}")),
            dest => break dest,
        }
    };
    let command = args.collect::<Vec<_>>().join(" ");
    if command.is_empty() {
        return Err("no command".into());
    }
    Ok((dest, port, command))
}

fn git_ssh_client(socket: &Path, args: &[String]) -> Result<ExitCode, Error> {
    let (dest, port, command) = parse_ssh_args(args).map_err(Error::GitSshArgs)?;
    let protocol = std::env::var("GIT_PROTOCOL").unwrap_or_default();
    let payload = [dest, port, &command, &protocol].join("\0");
    let len =
        u16::try_from(payload.len()).map_err(|_| Error::GitSshArgs("request too long".into()))?;
    let mut msg = vec![GIT_SSH_MAGIC];
    msg.extend(len.to_be_bytes());
    msg.extend(payload.as_bytes());

    let mut sock = std::os::unix::net::UnixStream::connect(socket).map_err(Error::GitSsh)?;
    let (stdin, stdout, stderr) = (io::stdin(), io::stdout(), io::stderr());
    let fds = [stdin.as_fd(), stdout.as_fd(), stderr.as_fd()];
    let mut space = [MaybeUninit::uninit(); rustix::cmsg_space!(ScmRights(3))];
    let mut control = SendAncillaryBuffer::new(&mut space);
    control.push(SendAncillaryMessage::ScmRights(&fds));
    let sent = rustix::net::sendmsg(
        &sock,
        &[IoSlice::new(&msg)],
        &mut control,
        SendFlags::empty(),
    )
    .map_err(|e| Error::GitSsh(e.into()))?;
    sock.write_all(&msg[sent..]).map_err(Error::GitSsh)?;

    let mut code = [0u8];
    sock.read_exact(&mut code).map_err(Error::GitSsh)?;
    Ok(ExitCode::from(code[0]))
}

fn request(socket: &Path, dest: &str, reason: &str) -> Result<ExitCode, Error> {
    let dest = if dest.contains(':') {
        dest.to_owned()
    } else {
        format!("{dest}:443")
    };
    if dest.contains(|c: char| c.is_whitespace() || c.is_control()) {
        return Err(Error::Request(ErrorKind::InvalidInput.into()));
    }
    let reason = session::clean_reason(reason);
    let mut sock = std::os::unix::net::UnixStream::connect(socket).map_err(Error::Request)?;
    write!(
        sock,
        "CONNECT {dest} HTTP/1.1\r\n{REASON_HEADER}: {reason}\r\n\r\n"
    )
    .map_err(Error::Request)?;
    let mut status = String::new();
    io::BufReader::new(&sock)
        .read_line(&mut status)
        .map_err(Error::Request)?;
    match status.split_whitespace().nth(1) {
        Some("200") => {
            println!("allowed: {dest}");
            Ok(ExitCode::SUCCESS)
        }
        Some("403") => {
            println!("not allowed: {dest}");
            Ok(ExitCode::FAILURE)
        }
        _ => {
            println!("allowed, but connecting failed: {dest} ({})", status.trim());
            Ok(ExitCode::FAILURE)
        }
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
    use super::{Allowed, GitSshRequest, parse_ssh_args};

    #[test]
    fn git_ssh_request() {
        let hosts = ["gitlab.com".to_owned()];
        let parse = |s: &str| GitSshRequest::parse(s.as_bytes(), &hosts);

        let ok = parse("git@GitLab.com\0\0git-upload-pack 'group/repo.git'\0version=2");
        assert!(ok.is_ok_and(|r| r.host == "gitlab.com" && r.port.is_none()));
        assert!(parse("git@gitlab.com\x002222\0git-upload-pack '/g/r.git'\0").is_ok());

        for bad in [
            "git@gitlab.com\0\0git-receive-pack 'g/r.git'\0",
            "git@gitlab.com\0\0git-upload-pack 'g/r.git' ; x\0",
            "git@gitlab.com\0\0git-upload-pack 'g/r'\\''x'\0",
            "git@gitlab.com\0\0git-upload-pack 'g/r\nx'\0",
            "git@gitlab.com\0\0git-upload-pack ''\0",
            "git@gitlab.com\0\0git-lfs-authenticate 'g/r.git' download\0",
            "git@github.com\0\0git-upload-pack 'g/r.git'\0",
            "root@gitlab.com\0\0git-upload-pack 'g/r.git'\0",
            "gitlab.com\0\0git-upload-pack 'g/r.git'\0",
            "git@gitlab.com\0-oProxyCommand=x\0git-upload-pack 'g/r.git'\0",
            "git@gitlab.com\x000\0git-upload-pack 'g/r.git'\0",
            "git@gitlab.com\0\0git-upload-pack 'g/r.git'\0version=2:x",
            "git@gitlab.com\0\0git-upload-pack 'g/r.git'",
        ] {
            assert!(parse(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn ssh_args() {
        let args = |a: &[&str]| a.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        let git = args(&[
            "-o",
            "SendEnv=GIT_PROTOCOL",
            "-p",
            "2222",
            "-4",
            "git@h",
            "git-upload-pack 'r'",
        ]);
        assert_eq!(
            parse_ssh_args(&git),
            Ok(("git@h", "2222", "git-upload-pack 'r'".into()))
        );
        assert!(parse_ssh_args(&args(&["-L", "1:x:2", "git@h", "c"])).is_err());
        assert!(parse_ssh_args(&args(&["git@h"])).is_err());
    }

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
