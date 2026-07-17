use hbb_common::{
    anyhow::anyhow,
    config::{self, Config, DiscoveryPeer},
    lan::{device_fingerprint, DEFAULT_PORT, PROTOCOL_VERSION},
    log,
    tokio::sync::mpsc::UnboundedSender,
    ResultType,
};
use mdns_sd::{DaemonEvent, ServiceDaemon, ServiceEvent, ServiceInfo};
use std::{
    collections::{BTreeSet, HashMap},
    net::{IpAddr, Ipv6Addr},
    thread,
    time::{Duration, Instant},
};

const SERVICE_TYPE: &str = "_subnetdesk._tcp.local.";
const BROWSE_DURATION: Duration = Duration::from_secs(3);

#[derive(Clone, Debug, Eq, PartialEq)]
struct Announcement {
    display_name: String,
    dns_label: String,
    platform: String,
    fingerprint: String,
    port: u16,
    addresses: Vec<IpAddr>,
}

impl Announcement {
    fn current() -> Option<Self> {
        if Config::get_option("lan-discovery-enabled") == "N"
            || !Config::lan_credentials_configured()
            || config::option2bool("stop-service", &Config::get_option("stop-service"))
        {
            return None;
        }

        let fingerprint = device_fingerprint(&Config::get_key_pair().1);
        if !valid_fingerprint(&fingerprint) {
            return None;
        }
        let display_name = safe_display_name(&crate::whoami_hostname());
        let addresses = advertised_addresses();
        if addresses.is_empty() {
            return None;
        }

        Some(Self {
            dns_label: dns_host_label(&display_name, &fingerprint),
            display_name,
            platform: hbb_common::whoami::platform().to_string(),
            fingerprint,
            port: Config::get_option("lan-listen-port")
                .parse::<u16>()
                .ok()
                .filter(|port| *port > 0)
                .unwrap_or(DEFAULT_PORT),
            addresses,
        })
    }

    fn service_info(&self) -> ResultType<ServiceInfo> {
        let hostname = format!("{}.local.", self.dns_label);
        ServiceInfo::new(
            SERVICE_TYPE,
            &self.dns_label,
            &hostname,
            self.addresses.as_slice(),
            self.port,
            announcement_properties(
                &self.display_name,
                &self.platform,
                &self.fingerprint,
            ),
        )
        .map_err(|err| anyhow!("Failed to create mDNS service info: {err}"))
    }
}

pub(super) fn start_publisher() -> ResultType<()> {
    let daemon = ServiceDaemon::new().map_err(|err| anyhow!("Failed to start mDNS: {err}"))?;
    let monitor = daemon.monitor().ok();
    let mut current: Option<Announcement> = None;
    let mut registered_fullname: Option<String> = None;

    loop {
        if let Some(monitor) = monitor.as_ref() {
            while let Ok(event) = monitor.try_recv() {
                match event {
                    DaemonEvent::Error(err) => log::warn!("mDNS daemon error: {err}"),
                    DaemonEvent::NameChange(change) => {
                        log::info!("mDNS resolved a name conflict: {change:?}")
                    }
                    _ => {}
                }
            }
        }

        let desired = Announcement::current();
        if desired != current {
            if let Some(fullname) = registered_fullname.take() {
                if let Err(err) = daemon.unregister(&fullname) {
                    log::warn!("Failed to unregister old mDNS service {fullname}: {err}");
                }
            }

            current = None;
            if let Some(announcement) = desired {
                match announcement.service_info() {
                    Ok(service_info) => {
                        let fullname = service_info.get_fullname().to_owned();
                        match daemon.register(service_info) {
                            Ok(()) => {
                                log::info!(
                                    "Published mDNS service {fullname} on port {}",
                                    announcement.port
                                );
                                registered_fullname = Some(fullname);
                                current = Some(announcement);
                            }
                            Err(err) => log::warn!("Failed to publish mDNS service: {err}"),
                        }
                    }
                    Err(err) => log::warn!("Failed to prepare mDNS service: {err}"),
                }
            }
        }

        thread::sleep(Duration::from_secs(1));
    }
}

pub(super) fn spawn_browse(tx: UnboundedSender<DiscoveryPeer>) -> ResultType<()> {
    let daemon = ServiceDaemon::new().map_err(|err| anyhow!("Failed to start mDNS: {err}"))?;
    let receiver = daemon
        .browse(SERVICE_TYPE)
        .map_err(|err| anyhow!("Failed to browse for SubnetDesk peers: {err}"))?;
    let local_fingerprint = device_fingerprint(&Config::get_key_pair().1);

    thread::spawn(move || {
        let deadline = Instant::now() + BROWSE_DURATION;
        while let Some(remaining) = deadline.checked_duration_since(Instant::now()) {
            match receiver.recv_timeout(remaining) {
                Ok(ServiceEvent::ServiceResolved(service)) => {
                    let properties = service
                        .get_properties()
                        .iter()
                        .map(|property| {
                            (property.key().to_owned(), property.val_str().to_owned())
                        })
                        .collect::<HashMap<_, _>>();
                    let addresses = service
                        .get_addresses()
                        .iter()
                        .map(|address| address.to_ip_addr())
                        .collect::<Vec<_>>();
                    if let Some(peer) = peer_from_mdns_fields(
                        &local_fingerprint,
                        service.get_hostname(),
                        service.get_port(),
                        &addresses,
                        &properties,
                    ) {
                        if tx.send(peer).is_err() {
                            break;
                        }
                    }
                }
                Ok(_) => {}
                Err(_) => break,
            }
        }
        if let Err(err) = daemon.stop_browse(SERVICE_TYPE) {
            log::debug!("Failed to stop mDNS browse: {err}");
        }
        if let Err(err) = daemon.shutdown() {
            log::debug!("Failed to shut down mDNS browse daemon: {err}");
        }
    });
    Ok(())
}

fn advertised_addresses() -> Vec<IpAddr> {
    let configured = Config::get_option("lan-listen-addresses")
        .split(',')
        .filter_map(|value| value.trim().parse::<IpAddr>().ok())
        .collect::<BTreeSet<_>>();

    default_net::get_interfaces()
        .into_iter()
        .flat_map(|interface| {
            interface
                .ipv4
                .into_iter()
                .map(|network| IpAddr::V4(network.addr))
                .chain(
                    interface
                        .ipv6
                        .into_iter()
                        .map(|network| IpAddr::V6(network.addr)),
                )
        })
        .filter(|address| address_is_listened_on(*address, &configured))
        .filter(|address| connectable_address(*address))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn address_is_listened_on(address: IpAddr, configured: &BTreeSet<IpAddr>) -> bool {
    configured.is_empty()
        || configured.contains(&address)
        || configured
            .iter()
            .any(|candidate| candidate.is_unspecified() && candidate.is_ipv4() == address.is_ipv4())
}

fn announcement_properties(
    display_name: &str,
    platform: &str,
    fingerprint: &str,
) -> HashMap<String, String> {
    HashMap::from([
        ("v".to_owned(), PROTOCOL_VERSION.to_string()),
        ("name".to_owned(), safe_display_name(display_name)),
        ("os".to_owned(), normalize_platform(platform)),
        ("fp".to_owned(), fingerprint.to_ascii_lowercase()),
    ])
}

fn peer_from_mdns_fields(
    local_fingerprint: &str,
    service_hostname: &str,
    port: u16,
    addresses: &[IpAddr],
    properties: &HashMap<String, String>,
) -> Option<DiscoveryPeer> {
    if port == 0
        || properties
            .get("v")
            .and_then(|value| value.parse::<u32>().ok())
            != Some(PROTOCOL_VERSION)
    {
        return None;
    }

    let fingerprint = properties.get("fp")?.to_ascii_lowercase();
    if !valid_fingerprint(&fingerprint)
        || fingerprint.eq_ignore_ascii_case(local_fingerprint)
    {
        return None;
    }

    let mut addresses = addresses
        .iter()
        .copied()
        .filter(|address| connectable_address(*address))
        .collect::<Vec<_>>();
    addresses.sort_by_key(|address| (address_priority(*address), *address));
    addresses.dedup();
    let primary = addresses.first().copied()?;
    let endpoint = match primary {
        IpAddr::V4(address) => format!("{address}:{port}"),
        IpAddr::V6(address) => format!("[{address}]:{port}"),
    };

    let hostname = properties
        .get("name")
        .and_then(|value| valid_remote_label(value))
        .unwrap_or_else(|| {
            let fallback = service_hostname
                .trim_end_matches('.')
                .strip_suffix(".local")
                .unwrap_or(service_hostname.trim_end_matches('.'));
            valid_remote_label(fallback).unwrap_or_else(|| "Unknown".to_owned())
        });
    let platform = properties
        .get("os")
        .map(|value| normalize_platform(value))
        .unwrap_or_else(|| "Unknown".to_owned());
    let ip_mac = addresses
        .into_iter()
        .map(|address| (address.to_string(), String::new()))
        .collect();

    Some(DiscoveryPeer {
        id: endpoint.clone(),
        endpoint,
        fingerprint,
        hostname,
        platform,
        username: String::new(),
        online: true,
        ip_mac,
    })
}

fn connectable_address(address: IpAddr) -> bool {
    if address.is_loopback() || address.is_unspecified() || !crate::lan_server::source_allowed(address)
    {
        return false;
    }
    match address {
        IpAddr::V4(address) => !address.is_link_local(),
        IpAddr::V6(address) => !ipv6_link_local(address),
    }
}

fn address_priority(address: IpAddr) -> u8 {
    match address {
        IpAddr::V4(address) if address.is_private() => 0,
        IpAddr::V6(address) if (address.segments()[0] & 0xfe00) == 0xfc00 => 1,
        IpAddr::V4(_) => 2,
        IpAddr::V6(_) => 3,
    }
}

fn ipv6_link_local(address: Ipv6Addr) -> bool {
    (address.segments()[0] & 0xffc0) == 0xfe80
}

fn valid_fingerprint(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn normalize_platform(value: &str) -> String {
    match value {
        "Windows" => "Windows",
        "Linux" => "Linux",
        "Mac OS" | "macOS" => "Mac OS",
        "Android" => "Android",
        _ => "Unknown",
    }
    .to_owned()
}

fn safe_display_name(value: &str) -> String {
    let value = value.trim();
    let filtered = value
        .chars()
        .filter(|character| !character.is_control())
        .take(64)
        .collect::<String>();
    if filtered.is_empty() {
        "SubnetDesk".to_owned()
    } else {
        filtered
    }
}

fn valid_remote_label(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() || value.chars().count() > 128 || value.chars().any(char::is_control) {
        None
    } else {
        Some(value.to_owned())
    }
}

fn dns_host_label(display_name: &str, fingerprint: &str) -> String {
    let mut base = String::with_capacity(display_name.len());
    let mut last_was_hyphen = false;
    for byte in display_name.bytes() {
        let normalized = if byte.is_ascii_alphanumeric() {
            Some(byte.to_ascii_lowercase() as char)
        } else if !last_was_hyphen {
            Some('-')
        } else {
            None
        };
        if let Some(character) = normalized {
            last_was_hyphen = character == '-';
            base.push(character);
        }
    }
    let base = base.trim_matches('-');
    let base = if base.is_empty() { "subnetdesk" } else { base };
    let suffix = fingerprint.get(..8).unwrap_or("device");
    let max_base_len = 63usize.saturating_sub(suffix.len() + 1);
    let mut base = base.chars().take(max_base_len).collect::<String>();
    while base.ends_with('-') {
        base.pop();
    }
    if base.is_empty() {
        base.push_str("subnetdesk");
    }
    format!("{base}-{suffix}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{config::DiscoveryPeer, lan::PROTOCOL_VERSION};
    use std::{collections::HashMap, net::IpAddr};

    const REMOTE_FINGERPRINT: &str =
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const LOCAL_FINGERPRINT: &str =
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    fn valid_properties() -> HashMap<String, String> {
        HashMap::from([
            ("v".to_owned(), PROTOCOL_VERSION.to_string()),
            ("name".to_owned(), "Office PC".to_owned()),
            ("os".to_owned(), "Windows".to_owned()),
            ("fp".to_owned(), REMOTE_FINGERPRINT.to_owned()),
        ])
    }

    #[test]
    fn dns_host_label_is_valid_stable_and_fingerprint_scoped() {
        assert_eq!(
            dns_host_label("  Office PC!  ", REMOTE_FINGERPRINT),
            "office-pc-aaaaaaaa"
        );
        let label = dns_host_label(&"设备".repeat(80), REMOTE_FINGERPRINT);
        assert!(label.len() <= 63);
        assert!(!label.starts_with('-'));
        assert!(!label.ends_with('-'));
        assert!(label
            .bytes()
            .all(|value| value.is_ascii_alphanumeric() || value == b'-'));
    }

    #[test]
    fn announcement_txt_contains_only_public_discovery_metadata() {
        let properties = announcement_properties("Office PC", "Windows", REMOTE_FINGERPRINT);
        assert_eq!(
            properties.keys().cloned().collect::<std::collections::BTreeSet<_>>(),
            ["fp", "name", "os", "v"]
                .into_iter()
                .map(str::to_owned)
                .collect()
        );
        assert!(!properties.contains_key("username"));
        assert!(!properties.contains_key("password"));
        assert!(!properties.contains_key("password_hash"));
    }

    #[test]
    fn resolved_peer_prefers_private_ipv4_and_keeps_hostname_and_platform() {
        let addresses: Vec<IpAddr> = ["fd00::20", "8.8.8.8", "192.168.1.24"]
            .into_iter()
            .map(|value| value.parse().unwrap())
            .collect();
        let peer: DiscoveryPeer = peer_from_mdns_fields(
            LOCAL_FINGERPRINT,
            "office-pc.local.",
            21_118,
            &addresses,
            &valid_properties(),
        )
        .unwrap();

        assert_eq!(peer.id, "192.168.1.24:21118");
        assert_eq!(peer.endpoint, peer.id);
        assert_eq!(peer.hostname, "Office PC");
        assert_eq!(peer.platform, "Windows");
        assert_eq!(peer.fingerprint, REMOTE_FINGERPRINT);
        assert!(peer.username.is_empty());
        assert!(peer.online);
    }

    #[test]
    fn resolved_peer_rejects_self_invalid_identity_and_public_only_addresses() {
        let private_address = ["10.1.1.124".parse().unwrap()];
        let public_address = ["8.8.8.8".parse().unwrap()];
        let properties = valid_properties();

        assert!(peer_from_mdns_fields(
            REMOTE_FINGERPRINT,
            "office-pc.local.",
            21_118,
            &private_address,
            &properties,
        )
        .is_none());

        let mut invalid_fingerprint = properties.clone();
        invalid_fingerprint.insert("fp".to_owned(), "not-a-fingerprint".to_owned());
        assert!(peer_from_mdns_fields(
            LOCAL_FINGERPRINT,
            "office-pc.local.",
            21_118,
            &private_address,
            &invalid_fingerprint,
        )
        .is_none());

        let mut unsupported_version = properties.clone();
        unsupported_version.insert("v".to_owned(), "999".to_owned());
        assert!(peer_from_mdns_fields(
            LOCAL_FINGERPRINT,
            "office-pc.local.",
            21_118,
            &private_address,
            &unsupported_version,
        )
        .is_none());

        assert!(peer_from_mdns_fields(
            LOCAL_FINGERPRINT,
            "office-pc.local.",
            21_118,
            &public_address,
            &properties,
        )
        .is_none());
    }

    #[test]
    fn wildcard_listeners_advertise_only_their_address_family() {
        let configured = ["0.0.0.0".parse().unwrap()].into_iter().collect();
        assert!(address_is_listened_on(
            "192.168.1.24".parse().unwrap(),
            &configured
        ));
        assert!(!address_is_listened_on(
            "fd00::24".parse().unwrap(),
            &configured
        ));
    }
}
