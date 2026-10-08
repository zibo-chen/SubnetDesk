//! LAN settings shared by Flutter and the native Sciter client.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use crate::ui_interface::get_lan_server_runtime_status;
use hbb_common::{
    config::{self, Config, PeerConfig, RecentLanEndpoint},
    log, ResultType,
};
use zeroize::Zeroize;

pub(crate) fn lan_server_info() -> String {
    let configured = Config::lan_credentials_configured();
    #[cfg(target_os = "windows")]
    let portable_service_running = crate::portable_service::client::running();
    #[cfg(not(target_os = "windows"))]
    let portable_service_running = false;
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let (runtime_state, runtime_error) = get_lan_server_runtime_status();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let (runtime_state, runtime_error) = {
        let status = crate::lan_server::LanServer::runtime_status();
        (status.state, status.last_error)
    };
    let running = lan_server_running_for_ui(&runtime_state);
    #[cfg(not(target_os = "ios"))]
    let configured_listen_addresses: std::collections::HashSet<String> =
        Config::get_option("lan-listen-addresses")
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .collect();
    #[cfg(not(target_os = "ios"))]
    let addresses: Vec<String> = crate::lan::local_connectable_addresses()
        .into_iter()
        .filter(|address| {
            if configured_listen_addresses.is_empty() {
                crate::lan_server::source_allowed(*address)
            } else {
                configured_listen_addresses.contains(&address.to_string())
            }
        })
        .map(|address| address.to_string())
        .collect();
    #[cfg(target_os = "ios")]
    let addresses: Vec<String> = Vec::new();
    let port = Config::get_option("lan-listen-port")
        .parse::<u16>()
        .ok()
        .filter(|value| *value > 0)
        .unwrap_or(hbb_common::lan::DEFAULT_PORT);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let (web_listen_port, web_https_enabled, web_runtime, web_ca_certificate_path) = (
        crate::web_gateway::configured_port(),
        crate::web_gateway::is_https_enabled(),
        serde_json::to_value(crate::web_gateway::runtime_status()).unwrap_or_default(),
        crate::web_gateway::certificate_authority_path_for_ui(),
    );
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let (web_listen_port, web_https_enabled, web_runtime, web_ca_certificate_path) = (
        18_123,
        true,
        serde_json::json!({
            "state": "unsupported",
            "endpoints": [],
            "last_error": "",
            "active_sessions": 0,
        }),
        String::new(),
    );
    let data = serde_json::json!({
        "configured": configured,
        "running": running,
        "portable_service_running": portable_service_running,
        "runtime_state": runtime_state,
        "runtime_error": runtime_error,
        "username": Config::get_lan_access_username(),
        "credential_revision": Config::get_credential_revision(),
        "device_name": crate::lan::device_display_name(),
        "system_device_name": crate::hostname(),
        "fingerprint": crate::lan_protocol::fingerprint(&Config::get_key_pair().1),
        "addresses": addresses,
        "port": port,
        "listen_addresses": Config::get_option("lan-listen-addresses"),
        "allowed_networks": Config::get_option("lan-allowed-networks"),
        "discovery_enabled": Config::get_option("lan-discovery-enabled") != "N",
        "web_access_enabled": Config::get_option("web-access-enabled") == "Y",
        "web_listen_port": web_listen_port,
        "web_https_enabled": web_https_enabled,
        "web_certificate_path": Config::get_option("web-certificate-path"),
        "web_private_key_path": Config::get_option("web-private-key-path"),
        "web_listen_addresses": Config::get_option("web-listen-addresses"),
        "web_allowed_networks": Config::get_option("web-allowed-networks"),
        "web_allowed_hosts": Config::get_option("web-allowed-hosts"),
        "web_permission_profile": Config::get_option("web-permission-profile"),
        "web_ca_certificate_path": web_ca_certificate_path,
        "web_runtime": web_runtime,
    });
    data.to_string()
}

pub(crate) fn lan_server_running_for_ui(runtime_state: &str) -> bool {
    runtime_state == crate::lan_server::RUNTIME_STATE_LISTENING
}

pub(crate) fn should_sync_lan_settings_to_background() -> bool {
    #[cfg(target_os = "macos")]
    {
        true
    }
    #[cfg(target_os = "windows")]
    {
        // Portable builds run the background host as a user process instead of
        // an SCM service. It still owns an independent in-memory Config snapshot,
        // so LAN credentials and listener options must always be synchronized.
        true
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        false
    }
}

pub(crate) fn apply_lan_settings(
    username: String,
    mut password: String,
    listen_addresses: String,
    listen_port: String,
    allowed_networks: String,
    discovery_enabled: bool,
    web_access_enabled: bool,
    web_listen_port: String,
    web_certificate_path: String,
    web_private_key_path: String,
) -> String {
    let result = (|| -> ResultType<()> {
        let username = hbb_common::lan::validate_username(&username)?;
        let port = listen_port
            .parse::<u16>()
            .map_err(|_| hbb_common::anyhow::anyhow!("Listen port must be between 1 and 65535"))?;
        if port == 0 {
            hbb_common::bail!("Listen port must be between 1 and 65535");
        }
        let web_port = web_listen_port
            .parse::<u16>()
            .map_err(|_| hbb_common::anyhow::anyhow!("Web port must be between 1 and 65535"))?;
        if web_port == 0 {
            hbb_common::bail!("Web port must be between 1 and 65535");
        }
        if web_access_enabled && web_port == port {
            hbb_common::bail!("Web port must differ from the native LAN port");
        }
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        let (web_certificate_path, web_private_key_path) =
            match crate::web_gateway::validate_custom_certificate_files(
                &web_certificate_path,
                &web_private_key_path,
            )? {
                Some((certificate_path, private_key_path)) => (
                    certificate_path.to_string_lossy().into_owned(),
                    private_key_path.to_string_lossy().into_owned(),
                ),
                None => (String::new(), String::new()),
            };
        #[cfg(any(target_os = "android", target_os = "ios"))]
        let (web_certificate_path, web_private_key_path) = {
            if web_access_enabled {
                hbb_common::bail!("Web access is not supported on this platform");
            }
            (String::new(), String::new())
        };
        let listen_addresses = crate::lan_server::normalize_listen_addresses(&listen_addresses)?;
        let allowed_networks = crate::lan_server::normalize_allowed_networks(&allowed_networks)?;

        let current_username = Config::get_lan_access_username();
        if password.is_empty() {
            if !Config::lan_credentials_configured() || username != current_username {
                hbb_common::bail!(
                    "A password is required when creating or renaming the LAN account"
                );
            }
        } else {
            Config::set_lan_credentials(&username, password.as_bytes())?;
        }
        Config::set_option("lan-listen-addresses".to_owned(), listen_addresses);
        Config::set_option("lan-listen-port".to_owned(), port.to_string());
        Config::set_option("lan-allowed-networks".to_owned(), allowed_networks);
        Config::set_option(
            "lan-discovery-enabled".to_owned(),
            if discovery_enabled { "Y" } else { "N" }.to_owned(),
        );
        Config::set_option(
            "web-access-enabled".to_owned(),
            if web_access_enabled { "Y" } else { "N" }.to_owned(),
        );
        Config::set_option("web-listen-port".to_owned(), web_port.to_string());
        Config::set_option("web-https-enabled".to_owned(), "Y".to_owned());
        Config::set_option("web-certificate-path".to_owned(), web_certificate_path);
        Config::set_option("web-private-key-path".to_owned(), web_private_key_path);
        Config::set_option("stop-service".to_owned(), String::new());
        crate::lan_server::LanServer::restart();
        Ok(())
    })();
    password.zeroize();
    if let Err(err) = result {
        return err.to_string();
    }

    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if should_sync_lan_settings_to_background() {
        if let Err(err) = crate::ipc::sync_current_config_to_server(2_000) {
            log::error!("Failed to synchronize LAN settings to the background service: {err}");
            return "Failed to update the background service. Please retry.".to_owned();
        }
    }

    String::new()
}

pub(crate) fn recent_lan_endpoint_to_map(
    recent: RecentLanEndpoint,
    discovered: &[config::DiscoveryPeer],
    now: i64,
) -> serde_json::Value {
    let alias = PeerConfig::load(&recent.endpoint)
        .options
        .get("alias")
        .cloned()
        .unwrap_or_default();
    let presence =
        crate::lan::find_discovered_peer(discovered, &recent.fingerprint, &recent.endpoint);
    serde_json::json!({
        "id": recent.endpoint,
        "username": recent.username,
        "hostname": recent.hostname,
        "platform": recent.platform,
        "alias": alias,
        "fingerprint": recent.fingerprint,
        "online": presence.and_then(|peer| peer.online_state(now)),
        "last_seen": presence.map(|peer| peer.last_seen).unwrap_or_default(),
        "last_checked": presence.map(|peer| peer.last_checked).unwrap_or_default(),
    })
}

#[cfg(test)]
mod lan_server_info_tests {
    use super::{lan_server_running_for_ui, should_sync_lan_settings_to_background};

    #[test]
    fn reports_cached_background_listener_status() {
        assert!(lan_server_running_for_ui(
            crate::lan_server::RUNTIME_STATE_LISTENING
        ));
    }

    #[test]
    fn non_listening_background_status_is_not_ready() {
        assert!(!lan_server_running_for_ui(
            crate::lan_server::RUNTIME_STATE_STARTING
        ));
        assert!(!lan_server_running_for_ui(
            crate::lan_server::RUNTIME_STATE_FAILED
        ));
        assert!(!lan_server_running_for_ui(
            crate::lan_server::RUNTIME_STATE_STOPPED
        ));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn macos_lan_settings_are_synchronized_to_the_background_host() {
        assert!(should_sync_lan_settings_to_background());
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn windows_portable_lan_settings_are_synchronized_to_the_background_host() {
        assert!(should_sync_lan_settings_to_background());
    }
}
