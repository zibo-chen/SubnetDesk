use std::{
    net::{IpAddr, SocketAddr},
    str::FromStr,
    sync::{
        atomic::{AtomicU64, AtomicUsize, Ordering},
        Mutex,
    },
    time::Duration,
};

use cidr_utils::cidr::IpCidr;
use hbb_common::{
    config::{option2bool, Config},
    lan::DEFAULT_PORT,
    log,
    tcp::{listen_any, new_listener},
    tokio::{self, sync::watch},
    ResultType, Stream,
};

#[cfg(not(target_os = "ios"))]
use crate::server::{new as new_server, ServerPtr};

static RESTART_GENERATION: AtomicU64 = AtomicU64::new(0);
static ACTIVE_LISTENERS: AtomicUsize = AtomicUsize::new(0);

pub const RUNTIME_STATE_STOPPED: &str = "stopped";
pub const RUNTIME_STATE_STARTING: &str = "starting";
pub const RUNTIME_STATE_LISTENING: &str = "listening";
pub const RUNTIME_STATE_FAILED: &str = "failed";

#[derive(Clone, Debug)]
pub struct LanServerRuntimeStatus {
    pub state: String,
    pub last_error: String,
}

lazy_static::lazy_static! {
    static ref RUNTIME_STATUS: Mutex<LanServerRuntimeStatus> = Mutex::new(LanServerRuntimeStatus {
        state: RUNTIME_STATE_STARTING.to_owned(),
        last_error: String::new(),
    });
}

fn set_runtime_status(state: &str, last_error: String) {
    let mut status = RUNTIME_STATUS.lock().unwrap();
    status.state = state.to_owned();
    status.last_error = last_error;
}

pub struct LanServer;

impl LanServer {
    pub fn restart() {
        RESTART_GENERATION.fetch_add(1, Ordering::SeqCst);
        set_runtime_status(RUNTIME_STATE_STARTING, String::new());
        log::info!("LAN server restart requested");
    }

    pub fn is_running() -> bool {
        ACTIVE_LISTENERS.load(Ordering::SeqCst) > 0
    }

    pub fn runtime_status() -> LanServerRuntimeStatus {
        RUNTIME_STATUS.lock().unwrap().clone()
    }

    pub(crate) fn is_discoverable() -> bool {
        // Discovery advertises presence, independently of incoming access.
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        return !desktop_stopping();
        #[cfg(any(target_os = "android", target_os = "ios"))]
        return Self::is_running() && service_ready();
    }

    #[cfg(not(target_os = "ios"))]
    pub async fn start() {
        let server = new_server();
        start_auxiliary_services_once();
        loop {
            let generation = RESTART_GENERATION.load(Ordering::SeqCst);
            let signature = listener_signature();
            #[cfg(not(any(target_os = "android", target_os = "ios")))]
            if crate::desktop_runtime::is_stopping() {
                server.write().unwrap().close_connections();
                ACTIVE_LISTENERS.store(0, Ordering::SeqCst);
                set_runtime_status(RUNTIME_STATE_STOPPED, String::new());
                return;
            }
            if !service_ready() {
                server.write().unwrap().close_connections();
                ACTIVE_LISTENERS.store(0, Ordering::SeqCst);
                set_runtime_status(RUNTIME_STATE_STOPPED, String::new());
                tokio::time::sleep(Duration::from_secs(1)).await;
                continue;
            }
            let (stop_tx, stop_rx) = watch::channel(false);
            let (handles, native_listener_count) =
                match bind_listeners(server.clone(), stop_rx).await {
                    Ok(result) => result,
                    Err(err) => {
                        log::error!("Failed to start LAN server: {err}");
                        ACTIVE_LISTENERS.store(0, Ordering::SeqCst);
                        set_runtime_status(RUNTIME_STATE_FAILED, err.to_string());
                        tokio::time::sleep(Duration::from_secs(1)).await;
                        continue;
                    }
                };
            ACTIVE_LISTENERS.store(native_listener_count, Ordering::SeqCst);
            set_runtime_status(RUNTIME_STATE_LISTENING, String::new());
            loop {
                tokio::time::sleep(Duration::from_secs(1)).await;
                if generation != RESTART_GENERATION.load(Ordering::SeqCst)
                    || signature != listener_signature()
                    || !service_ready()
                    || desktop_stopping()
                {
                    break;
                }
            }
            if stop_tx.send(true).is_err() {
                log::debug!("LAN listener stop receivers already closed");
            }
            ACTIVE_LISTENERS.store(0, Ordering::SeqCst);
            set_runtime_status(
                if service_ready() {
                    RUNTIME_STATE_STARTING
                } else {
                    RUNTIME_STATE_STOPPED
                },
                String::new(),
            );
            for handle in handles {
                if let Err(err) = handle.await {
                    log::debug!("LAN listener task ended: {err}");
                }
            }
        }
    }
}

pub fn normalize_listen_addresses(value: &str) -> ResultType<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|address| {
            address
                .parse::<IpAddr>()
                .map(|address| address.to_string())
                .map_err(|_| hbb_common::anyhow::anyhow!("Invalid listen address: {address}"))
        })
        .collect::<Result<Vec<_>, _>>()
        .map(|addresses| addresses.join(","))
}

pub fn normalize_allowed_networks(value: &str) -> ResultType<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|network| {
            if !network.contains('/') {
                return Err(hbb_common::anyhow::anyhow!(
                    "Invalid allowed network: {network}"
                ));
            }
            IpCidr::from_str(network)
                .map(|network| network.to_string())
                .map_err(|_| hbb_common::anyhow::anyhow!("Invalid allowed network: {network}"))
        })
        .collect::<Result<Vec<_>, _>>()
        .map(|networks| networks.join(","))
}

fn desktop_stopping() -> bool {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    return crate::desktop_runtime::is_stopping();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    false
}

fn service_ready() -> bool {
    !desktop_stopping() && Config::lan_credentials_configured()
        && crate::host_permissions::ready()
        && !option2bool("stop-service", &Config::get_option("stop-service"))
}

fn listen_port() -> u16 {
    Config::get_option("lan-listen-port")
        .parse::<u16>()
        .ok()
        .filter(|port| *port > 0)
        .unwrap_or(DEFAULT_PORT)
}

fn listen_addresses() -> Vec<String> {
    Config::get_option("lan-listen-addresses")
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn listener_signature() -> (
    u16,
    Vec<String>,
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    Vec<String>,
    String,
) {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let web_certificate_addresses = crate::web_gateway::certificate_address_signature();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let web_certificate_addresses = Vec::new();
    (
        listen_port(),
        listen_addresses(),
        Config::get_option("lan-allowed-networks"),
        Config::get_option("web-access-enabled"),
        Config::get_option("web-listen-port"),
        Config::get_option("web-certificate-path"),
        Config::get_option("web-private-key-path"),
        Config::get_option("web-listen-addresses"),
        Config::get_option("web-allowed-networks"),
        Config::get_option("web-allowed-hosts"),
        web_certificate_addresses,
        Config::get_option("web-permission-profile"),
    )
}

#[cfg(not(target_os = "ios"))]
async fn bind_listeners(
    server: ServerPtr,
    stop_rx: watch::Receiver<bool>,
) -> ResultType<(Vec<tokio::task::JoinHandle<()>>, usize)> {
    let port = listen_port();
    let addresses = listen_addresses();
    let mut listeners = Vec::new();
    if addresses.is_empty() {
        listeners.push(listen_any(port).await.map_err(|err| {
            hbb_common::anyhow::anyhow!("Failed to listen on port {port}: {err}")
        })?);
    } else {
        for address in addresses {
            let ip = IpAddr::from_str(&address).map_err(|_| {
                hbb_common::anyhow::anyhow!("Invalid LAN listen address: {address}")
            })?;
            let endpoint = SocketAddr::new(ip, port);
            listeners.push(new_listener(endpoint, true).await.map_err(|err| {
                hbb_common::anyhow::anyhow!("Failed to listen on {endpoint}: {err}")
            })?);
        }
    }

    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let mut handles = match crate::web_gateway::bind(server.clone(), stop_rx.clone()).await {
        Ok(handles) => handles,
        Err(err) => {
            log::error!("Failed to start optional Web access: {err}");
            crate::web_gateway::record_start_failure(&err.to_string());
            Vec::new()
        }
    };
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let mut handles = Vec::new();
    let native_listener_count = listeners.len();
    handles.reserve(native_listener_count);
    for listener in listeners {
        let server = server.clone();
        let mut stop_rx = stop_rx.clone();
        log::info!("LAN server listening on {}", listener.local_addr()?);
        handles.push(tokio::spawn(async move {
            loop {
                tokio::select! {
                    changed = stop_rx.changed() => {
                        if changed.is_err() || *stop_rx.borrow() {
                            break;
                        }
                    }
                    accepted = listener.accept() => {
                        match accepted {
                            Ok((stream, addr)) => {
                                let addr = normalize_source_addr(addr);
                                if !source_allowed(addr.ip()) {
                                    log::warn!("Rejected LAN connection from disallowed source {addr}");
                                    continue;
                                }
                                if let Err(err) = stream.set_nodelay(true) {
                                    log::debug!("Failed to enable TCP_NODELAY for {addr}: {err}");
                                }
                                let local_addr = match stream.local_addr() {
                                    Ok(value) => value,
                                    Err(err) => {
                                        log::warn!("Failed to read local address for {addr}: {err}");
                                        continue;
                                    }
                                };
                                let server = server.clone();
                                tokio::spawn(async move {
                                    let stream = Stream::from(stream, local_addr);
                                    if let Err(err) = crate::server::create_lan_connection(server, stream, addr, false).await {
                                        log::warn!("LAN connection from {addr} failed: {err}");
                                    }
                                });
                            }
                            Err(err) => {
                                log::warn!("LAN listener accept failed: {err}");
                                tokio::time::sleep(Duration::from_millis(200)).await;
                            }
                        }
                    }
                }
            }
        }));
    }
    Ok((handles, native_listener_count))
}

pub fn source_allowed(ip: IpAddr) -> bool {
    let configured = Config::get_option("lan-allowed-networks");
    source_allowed_with(ip, &configured)
}

pub(crate) fn source_allowed_with(ip: IpAddr, configured: &str) -> bool {
    let ip = normalize_source_ip(ip);
    let networks: Vec<&str> = if configured.trim().is_empty() {
        vec![
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
            "100.64.0.0/10",
            "127.0.0.0/8",
            "169.254.0.0/16",
            "fc00::/7",
            "fe80::/10",
            "::1/128",
        ]
    } else {
        configured
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .collect()
    };
    networks
        .iter()
        .filter_map(|value| IpCidr::from_str(value).ok())
        .any(|network| network.contains(ip))
}

fn normalize_source_addr(addr: SocketAddr) -> SocketAddr {
    SocketAddr::new(normalize_source_ip(addr.ip()), addr.port())
}

fn normalize_source_ip(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(ipv6) => ipv6
            .to_ipv4_mapped()
            .map(IpAddr::V4)
            .unwrap_or(IpAddr::V6(ipv6)),
        IpAddr::V4(_) => ip,
    }
}

#[cfg(not(target_os = "ios"))]
fn start_auxiliary_services_once() {
    std::thread::spawn(|| {
        if let Err(err) = crate::lan::start_listening() {
            log::warn!("LAN discovery stopped: {err}");
        }
    });
    #[cfg(target_os = "linux")]
    if crate::is_server() {
        crate::platform::linux_desktop_manager::start_xdesktop();
    }
    scrap::codec::test_av1();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_policy_has_expected_private_networks() {
        assert!(source_allowed_with("192.168.1.20".parse().unwrap(), ""));
        assert!(source_allowed_with(
            "::ffff:192.168.1.20".parse().unwrap(),
            ""
        ));
        assert!(source_allowed_with("::ffff:127.0.0.1".parse().unwrap(), ""));
        assert!(source_allowed_with("100.64.10.2".parse().unwrap(), ""));
        assert!(source_allowed_with("fd00::20".parse().unwrap(), ""));
        assert!(!source_allowed_with("8.8.8.8".parse().unwrap(), ""));
        assert!(!source_allowed_with("::ffff:8.8.8.8".parse().unwrap(), ""));
        assert!(source_allowed_with(
            "10.23.1.9".parse().unwrap(),
            "10.23.0.0/16"
        ));
        assert!(source_allowed_with(
            "::ffff:10.23.1.9".parse().unwrap(),
            "10.23.0.0/16"
        ));
        assert_eq!(
            normalize_source_addr("[::ffff:192.168.1.20]:21118".parse().unwrap()),
            "192.168.1.20:21118".parse().unwrap()
        );
    }

    #[test]
    fn normalizes_listener_configuration() {
        assert_eq!(
            normalize_listen_addresses(" 192.168.1.2, fd00::2 ").unwrap(),
            "192.168.1.2,fd00::2"
        );
        assert_eq!(
            normalize_allowed_networks(" 192.168.0.0/16, fd00::/8 ").unwrap(),
            "192.168.0.0/16,fd00::/8"
        );
        assert!(normalize_listen_addresses("host.lan").is_err());
        assert!(normalize_allowed_networks("192.168.1.1").is_err());
    }
}
