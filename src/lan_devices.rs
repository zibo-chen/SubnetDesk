//! Saved devices are keyed exclusively by their public-key fingerprint.
//! Endpoints and names are mutable attributes, never device identities.
use base::config::keys::OPTION_LAN_DEVICE_ADDRESSES;
use hbb_common::{
    anyhow::{anyhow, bail},
    config::{Config, DiscoveryPeer, LocalConfig, PeerConfig, RecentLanEndpoint},
    log, ResultType,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, HashSet},
    net::IpAddr,
    sync::Mutex,
};

static EDIT: Mutex<()> = Mutex::new(());

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct SavedDevice {
    pub endpoint: String,
    #[serde(default)]
    pub legacy_ids: Vec<String>,
    pub peer: RecentLanEndpoint,
    pub automatic: bool,
    pub source: String,
    pub revision: i64,
    pub manual_since: i64,
    pub address_changed_at: i64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
struct Registry {
    #[serde(default)]
    devices: BTreeMap<String, SavedDevice>,
}

pub(crate) fn valid_fingerprint(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|b| b.is_ascii_hexdigit())
}

pub(crate) fn normalize_address(value: &str) -> ResultType<String> {
    let endpoint =
        hbb_common::lan::Endpoint::parse(value.trim()).map_err(|_| anyhow!("invalid_address"))?;
    let host = endpoint.host();
    let host = if let Ok(ip) = host.parse::<IpAddr>() {
        ip.to_string()
    } else {
        if host.bytes().all(|b| b.is_ascii_digit() || b == b'.') {
            bail!("invalid_address");
        }
        host.to_ascii_lowercase()
    };
    Ok(if host.contains(':') {
        format!("[{host}]:{}", endpoint.port())
    } else {
        format!("{host}:{}", endpoint.port())
    })
}

impl Registry {
    fn load() -> ResultType<Self> {
        let json = LocalConfig::get_option_from_file(OPTION_LAN_DEVICE_ADDRESSES);
        if json.is_empty() {
            return Ok(Self::default());
        }
        let old: Self = serde_json::from_str(&json)
            .map_err(|err| anyhow!("Invalid saved device addresses: {err}"))?;
        let mut registry = Self::default();
        for (old_id, mut saved) in old.devices {
            if valid_fingerprint(&saved.peer.fingerprint) {
                if !valid_fingerprint(&old_id) && !saved.legacy_ids.contains(&old_id) {
                    saved.legacy_ids.push(old_id);
                }
                registry
                    .devices
                    .entry(saved.peer.fingerprint.to_ascii_lowercase())
                    .or_insert(saved);
            }
        }
        Ok(registry)
    }

    fn store(&self) -> ResultType<()> {
        let value = serde_json::to_string(self)?;
        let previous = LocalConfig::get_option_from_file(OPTION_LAN_DEVICE_ADDRESSES);
        LocalConfig::set_option(OPTION_LAN_DEVICE_ADDRESSES.to_owned(), value.clone());
        if LocalConfig::get_option_from_file(OPTION_LAN_DEVICE_ADDRESSES) != value {
            LocalConfig::set_option(OPTION_LAN_DEVICE_ADDRESSES.to_owned(), previous);
            bail!("storage_error");
        }
        Ok(())
    }

    fn legacy_owner(&self, legacy: &str) -> Option<String> {
        let mut owners = self
            .devices
            .iter()
            .filter(|(_, saved)| saved.legacy_ids.iter().any(|id| id == legacy));
        let (id, _) = owners.next()?;
        if owners.next().is_some() {
            return None;
        }
        Some(id.clone())
    }

    fn id_for_peer(&self, peer: &RecentLanEndpoint) -> Option<String> {
        let id = peer.fingerprint.to_ascii_lowercase();
        (valid_fingerprint(&id) && self.devices.contains_key(&id)).then_some(id)
    }

    fn register(&mut self, mut peer: RecentLanEndpoint) -> Option<String> {
        if !valid_fingerprint(&peer.fingerprint) {
            return None;
        }
        peer.fingerprint = peer.fingerprint.to_ascii_lowercase();
        let id = peer.fingerprint.clone();
        if let Some(saved) = self.devices.get_mut(&id) {
            if peer.last_connected_at > 0 && !saved.legacy_ids.contains(&peer.endpoint) {
                saved.legacy_ids.push(peer.endpoint.clone());
            }
            if peer.last_connected_at >= saved.peer.last_connected_at {
                if peer.hostname.is_empty() {
                    peer.hostname = saved.peer.hostname.clone();
                }
                if peer.platform.is_empty() {
                    peer.platform = saved.peer.platform.clone();
                }
                if peer.device_type.is_empty() {
                    peer.device_type = saved.peer.device_type.clone();
                }
                saved.peer = peer;
            }
            return Some(id);
        }
        let endpoint = normalize_address(&peer.endpoint).ok()?;
        self.devices.insert(
            id.clone(),
            SavedDevice {
                legacy_ids: if peer.last_connected_at > 0 {
                    vec![peer.endpoint.clone()]
                } else {
                    vec![]
                },
                endpoint,
                peer,
                automatic: true,
                source: "saved".to_owned(),
                revision: 0,
                manual_since: 0,
                address_changed_at: 0,
            },
        );
        Some(id)
    }

    fn discover(&mut self, peers: &[DiscoveryPeer], now: i64) {
        for saved in self.devices.values_mut() {
            if !saved.automatic || !valid_fingerprint(&saved.peer.fingerprint) {
                continue;
            }
            let fresh = peers
                .iter()
                .filter(|peer| {
                    peer.fingerprint
                        .eq_ignore_ascii_case(&saved.peer.fingerprint)
                        && peer.last_seen > saved.manual_since
                        && peer.online_state(now) == Some(true)
                })
                .max_by_key(|peer| peer.last_seen);
            if let Some(peer) = fresh {
                if let Ok(endpoint) = normalize_address(&peer.endpoint) {
                    if saved.endpoint != endpoint {
                        saved.endpoint = endpoint;
                        saved.source = "discovery".to_owned();
                        saved.address_changed_at = 0;
                        saved.revision += 1;
                    }
                }
            }
        }
    }

    fn update(
        &mut self,
        id: &str,
        address: &str,
        automatic: bool,
        revision: i64,
        now: i64,
    ) -> ResultType<SavedDevice> {
        let endpoint = normalize_address(address)?;
        let saved = self.devices.get(id).ok_or_else(|| anyhow!("not_found"))?;
        if saved.revision != revision {
            bail!("stale_address");
        }
        // Cached addresses may be reassigned or swapped; identity is never
        // merged or rejected merely because another record has the same IP.
        let previous = saved.clone();
        let saved = self
            .devices
            .get_mut(id)
            .ok_or_else(|| anyhow!("not_found"))?;
        if saved.endpoint != endpoint {
            saved.source = "manual".to_owned();
            saved.address_changed_at = now;
        }
        saved.endpoint = endpoint;
        saved.automatic = automatic;
        saved.manual_since = now;
        saved.revision += 1;
        Ok(previous)
    }
}

fn synchronized(discovered: &[DiscoveryPeer], now: i64) -> ResultType<Registry> {
    let _guard = EDIT.lock().unwrap();
    let mut registry = Registry::load()?;
    let before = registry.clone();
    let favorites = LocalConfig::get_fav();
    let recent = LocalConfig::get_recent_lan_endpoints();
    for peer in &recent {
        registry.register(peer.clone());
    }
    for legacy in &favorites {
        if valid_fingerprint(legacy) {
            continue;
        }
        // Only a previously verified endpoint binding can recover a legacy identity.
        // A new advertisement at the same IP is not evidence of its previous owner.
        let endpoint = match normalize_address(legacy) {
            Ok(value) => value,
            Err(_) => continue,
        };
        if let Some(fp) =
            Config::get_trusted_lan_fingerprint(&endpoint).filter(|fp| valid_fingerprint(fp))
        {
            let peer = recent
                .iter()
                .find(|peer| peer.fingerprint.eq_ignore_ascii_case(&fp))
                .cloned()
                .unwrap_or_else(|| RecentLanEndpoint {
                    endpoint: endpoint.clone(),
                    fingerprint: fp.clone(),
                    ..Default::default()
                });
            if let Some(id) = registry.register(peer) {
                if let Some(saved) = registry.devices.get_mut(&id) {
                    if !saved.legacy_ids.contains(legacy) {
                        saved.legacy_ids.push(legacy.clone());
                    }
                }
            }
        }
    }
    for peer in discovered {
        registry.register(RecentLanEndpoint {
            endpoint: peer.endpoint.clone(),
            fingerprint: peer.fingerprint.clone(),
            hostname: peer.hostname.clone(),
            platform: peer.platform.clone(),
            device_type: peer.device_type.clone(),
            ..Default::default()
        });
    }
    registry.discover(discovered, now);
    if registry != before {
        registry.store()?;
    }
    let mut seen = HashSet::new();
    let migrated = LocalConfig::get_fav()
        .into_iter()
        .map(|legacy| {
            if valid_fingerprint(&legacy) {
                return legacy.to_ascii_lowercase();
            }
            registry.legacy_owner(&legacy).unwrap_or(legacy)
        })
        .filter(|id| seen.insert(id.clone()))
        .collect::<Vec<_>>();
    LocalConfig::set_fav(migrated);
    // Alias migration is idempotent. Address-based credentials are never copied.
    for (id, saved) in &registry.devices {
        let mut config = PeerConfig::load(id);
        if config
            .options
            .get("alias")
            .map(|v| !v.is_empty())
            .unwrap_or(false)
        {
            continue;
        }
        for legacy in &saved.legacy_ids {
            if registry.legacy_owner(legacy).as_deref() != Some(id.as_str()) {
                continue;
            }
            if let Some(alias) = PeerConfig::load(legacy)
                .options
                .get("alias")
                .filter(|v| !v.is_empty())
                .cloned()
            {
                config.options.insert("alias".to_owned(), alias);
                config.store(id);
                break;
            }
        }
    }
    Ok(registry)
}

fn peer_json(
    id: &str,
    saved: &SavedDevice,
    discovered: &[DiscoveryPeer],
    now: i64,
) -> serde_json::Value {
    let alias = PeerConfig::load(id)
        .options
        .get("alias")
        .cloned()
        .unwrap_or_default();
    let presence =
        crate::lan::find_discovered_peer(discovered, &saved.peer.fingerprint, &saved.endpoint)
            .filter(|peer| {
                normalize_address(&peer.endpoint).ok().as_deref() == Some(&saved.endpoint)
                    && peer.last_seen >= saved.address_changed_at
            });
    serde_json::json!({
        "id": id, "address": saved.endpoint, "legacy_ids": saved.legacy_ids, "username": saved.peer.username,
        "hostname": saved.peer.hostname, "platform": saved.peer.platform,
        "device_type": presence.map(|p| p.device_type.as_str()).filter(|v| !v.is_empty()).unwrap_or(&saved.peer.device_type),
        "alias": alias, "fingerprint": saved.peer.fingerprint,
        "online": presence.and_then(|p| p.online_state(now)),
        "last_seen": presence.map(|p| p.last_seen).unwrap_or_default(),
        "last_checked": presence.map(|p| p.last_checked).unwrap_or_default(),
        "auto_update_address": saved.automatic, "address_source": saved.source, "address_revision": saved.revision,
    })
}

pub(crate) fn saved_peers(
    favorites_only: bool,
    discovered: &[DiscoveryPeer],
    now: i64,
) -> ResultType<Vec<serde_json::Value>> {
    let registry = synchronized(discovered, now)?;
    let ids = if favorites_only {
        LocalConfig::get_fav()
            .into_iter()
            .map(|id| {
                if registry.devices.contains_key(&id) {
                    id
                } else {
                    registry
                        .id_for_peer(&RecentLanEndpoint {
                            endpoint: id.clone(),
                            ..Default::default()
                        })
                        .unwrap_or(id)
                }
            })
            .collect::<Vec<_>>()
    } else {
        LocalConfig::get_recent_lan_endpoints()
            .iter()
            .filter_map(|peer| registry.id_for_peer(peer))
            .collect()
    };
    let mut seen = HashSet::new();
    Ok(ids
        .into_iter()
        .filter(|id| seen.insert(id.clone()))
        .map(|id| {
            if let Some(saved) = registry.devices.get(&id) {
                let mut json = peer_json(&id, saved, discovered, now);
                json["legacy_ids"] = serde_json::json!(saved
                    .legacy_ids
                    .iter()
                    .filter(|legacy| registry.legacy_owner(legacy).as_deref() == Some(id.as_str()))
                    .collect::<Vec<_>>());
                return json;
            }
            // Legacy endpoints without a known identity stay pending until connected/discovered.
            let peer = RecentLanEndpoint {
                endpoint: id,
                ..Default::default()
            };
            crate::lan_ui::recent_lan_endpoint_to_map(peer, &[], now)
        })
        .collect())
}

pub(crate) fn discovered_peers(
    peers: &[DiscoveryPeer],
    now: i64,
) -> ResultType<Vec<serde_json::Value>> {
    let registry = synchronized(peers, now)?;
    Ok(peers
        .iter()
        .map(|peer| {
            let id = peer.fingerprint.to_ascii_lowercase();
            if let Some(saved) = registry.devices.get(&id) {
                peer_json(&id, saved, peers, now)
            } else {
                crate::ui_interface::discovery_peer_to_json(peer, now)
            }
        })
        .collect())
}

pub(crate) fn connection(id: &str) -> Option<SavedDevice> {
    match Registry::load() {
        Ok(registry) => registry.devices.get(&id.to_ascii_lowercase()).cloned(),
        Err(err) => {
            log::error!("Loading saved addresses: {err}");
            None
        }
    }
}

pub(crate) fn update_address(
    id: String,
    address: String,
    automatic: bool,
    revision: i64,
) -> String {
    let result = (|| -> ResultType<serde_json::Value> {
        let _guard = EDIT.lock().unwrap();
        let mut registry = Registry::load()?;
        let previous =
            registry.update(&id, &address, automatic, revision, hbb_common::get_time())?;
        registry.store()?;
        Ok(serde_json::json!({"id": id, "revision": previous.revision + 1, "previous": previous}))
    })();
    match result {
        Ok(undo) => serde_json::json!({"undo": undo}).to_string(),
        Err(err) => serde_json::json!({"error": err.to_string()}).to_string(),
    }
}

pub(crate) fn restore_address(token: String) -> String {
    let result = (|| -> ResultType<()> {
        #[derive(Deserialize)]
        struct Undo {
            id: String,
            revision: i64,
            previous: SavedDevice,
        }
        let undo: Undo = serde_json::from_str(&token)?;
        if !valid_fingerprint(&undo.id)
            || !undo
                .previous
                .peer
                .fingerprint
                .eq_ignore_ascii_case(&undo.id)
        {
            bail!("invalid_undo");
        }
        normalize_address(&undo.previous.endpoint)?;
        let _guard = EDIT.lock().unwrap();
        let mut registry = Registry::load()?;
        let current = registry
            .devices
            .get(&undo.id)
            .ok_or_else(|| anyhow!("not_found"))?;
        if current.revision != undo.revision {
            bail!("stale_address");
        }
        let mut previous = undo.previous;
        previous.revision = undo.revision + 1;
        registry.devices.insert(undo.id, previous);
        registry.store()
    })();
    result.err().map(|err| err.to_string()).unwrap_or_default()
}

pub(crate) fn remember_connection(id: &str, peer: RecentLanEndpoint) -> ResultType<String> {
    let _guard = EDIT.lock().unwrap();
    let mut registry = Registry::load()?;
    if !valid_fingerprint(&peer.fingerprint) {
        bail!("Invalid device fingerprint");
    }
    let stable_id = peer.fingerprint.to_ascii_lowercase();
    let endpoint = normalize_address(&peer.endpoint)?;
    if let Some(saved) = registry.devices.get_mut(&stable_id) {
        if saved.endpoint != endpoint {
            saved.revision += 1;
        }
        saved.endpoint = endpoint;
        saved.address_changed_at = 0;
        if !valid_fingerprint(id) && !saved.legacy_ids.iter().any(|legacy| legacy == id) {
            saved.legacy_ids.push(id.to_owned());
        }
        saved.peer = peer;
    } else {
        registry.devices.insert(
            stable_id.clone(),
            SavedDevice {
                endpoint,
                legacy_ids: if valid_fingerprint(id) {
                    vec![]
                } else {
                    vec![id.to_owned()]
                },
                peer,
                automatic: true,
                source: "saved".to_owned(),
                revision: 0,
                manual_since: 0,
                address_changed_at: 0,
            },
        );
    }
    registry.store()?;
    Ok(stable_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn peer(fp: &str, endpoint: &str) -> RecentLanEndpoint {
        RecentLanEndpoint {
            fingerprint: fp.repeat(64),
            endpoint: endpoint.to_owned(),
            hostname: "old name".to_owned(),
            last_connected_at: 1,
            ..Default::default()
        }
    }
    fn discovered(fp: &str, endpoint: &str, now: i64) -> DiscoveryPeer {
        let mut peer = DiscoveryPeer {
            fingerprint: fp.repeat(64),
            endpoint: endpoint.to_owned(),
            ..Default::default()
        };
        peer.mark_seen(now);
        peer
    }
    #[test]
    fn fingerprint_is_the_only_record_key_when_names_and_addresses_change() {
        let mut registry = Registry::default();
        let id = registry.register(peer("a", "10.0.0.1:21118")).unwrap();
        let mut next = peer("a", "10.0.0.2:21118");
        next.hostname = "new name".to_owned();
        assert_eq!(registry.register(next).as_deref(), Some(id.as_str()));
        assert_eq!(registry.devices.len(), 1);
        assert_eq!(id, "a".repeat(64));
        assert_eq!(registry.devices[&id].legacy_ids.len(), 2);
        let serialized = serde_json::to_string(&registry).unwrap();
        let loaded: Registry = serde_json::from_str(&serialized).unwrap();
        assert_eq!(registry, loaded);
    }
    #[test]
    fn different_fingerprints_are_never_merged_by_ip_or_name() {
        let mut registry = Registry::default();
        registry.register(peer("a", "10.0.0.1:21118"));
        registry.register(peer("b", "10.0.0.1:21118"));
        assert_eq!(registry.devices.len(), 2);
        assert_eq!(registry.legacy_owner("10.0.0.1:21118"), None);
        assert!(registry
            .register(RecentLanEndpoint {
                endpoint: "unverified.local".into(),
                ..Default::default()
            })
            .is_none());
        assert!(registry.devices.keys().all(|key| valid_fingerprint(key)));
    }
    #[test]
    fn discovery_does_not_claim_legacy_address_ownership() {
        let mut registry = Registry::default();
        let mut advertisement = peer("a", "10.0.0.1:21118");
        advertisement.last_connected_at = 0;
        registry.register(advertisement);
        assert_eq!(registry.legacy_owner("10.0.0.1:21118"), None);
        registry.register(peer("b", "10.0.0.1:21118"));
        assert_eq!(
            registry.legacy_owner("10.0.0.1:21118"),
            Some("b".repeat(64))
        );
        assert_eq!(registry.devices.len(), 2);
    }
    #[test]
    fn manual_updates_preserve_identity_and_require_a_fresh_scan_to_replace_them() {
        let mut registry = Registry::default();
        let id = registry.register(peer("a", "10.0.0.1:21118")).unwrap();
        let previous = registry.update(&id, "10.0.0.2", true, 0, 100_000).unwrap();
        assert_eq!(previous.endpoint, "10.0.0.1:21118");
        registry.discover(&[discovered("a", "10.0.0.1:21118", 99_999)], 100_000);
        assert_eq!(registry.devices[&id].endpoint, "10.0.0.2:21118");
        registry.discover(&[discovered("a", "10.0.0.3:21118", 101_000)], 101_000);
        assert_eq!(registry.devices[&id].endpoint, "10.0.0.3:21118");
        assert_eq!(registry.devices[&id].source, "discovery");
        assert!(registry
            .update(&id, "10.0.0.4", true, 1, 102_000)
            .unwrap_err()
            .to_string()
            .contains("stale_address"));
    }
    #[test]
    fn pinned_addresses_ignore_mdns_and_other_devices_cannot_redirect_a_record() {
        let mut registry = Registry::default();
        let id = registry.register(peer("a", "10.0.0.1:21118")).unwrap();
        registry.update(&id, "10.0.0.2", false, 0, 100_000).unwrap();
        registry.discover(&[discovered("a", "10.0.0.3:21118", 101_000)], 101_000);
        assert_eq!(registry.devices[&id].endpoint, "10.0.0.2:21118");
        registry.update(&id, "10.0.0.2", true, 1, 102_000).unwrap();
        registry.discover(&[discovered("b", "10.0.0.4:21118", 103_000)], 103_000);
        assert_eq!(registry.devices[&id].endpoint, "10.0.0.2:21118");
    }
    #[test]
    fn reassigned_addresses_stay_separate_and_invalid_updates_do_not_change_records() {
        let mut registry = Registry::default();
        let id = registry.register(peer("a", "10.0.0.1:21118")).unwrap();
        registry.register(peer("b", "10.0.0.2:21118"));
        registry.update(&id, "10.0.0.2", true, 0, 1).unwrap();
        assert_eq!(registry.devices.len(), 2);
        assert_eq!(
            registry.devices[&id].endpoint,
            registry.devices[&"b".repeat(64)].endpoint
        );
        let before = registry.clone();
        assert!(registry.update(&id, "999.1.1.1", true, 1, 1).is_err());
        assert_eq!(before, registry);
        assert_eq!(
            normalize_address("[2001:0db8::1]:22000").unwrap(),
            "[2001:db8::1]:22000"
        );
        assert_eq!(normalize_address("HOST.local").unwrap(), "host.local:21118");
    }
}
