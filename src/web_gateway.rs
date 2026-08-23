use std::{
    collections::{HashMap, HashSet},
    fs::{self, OpenOptions},
    future::Future,
    io::{self, Write},
    net::{IpAddr, Ipv4Addr, SocketAddr},
    path::{Path, PathBuf},
    pin::Pin,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use axum::{
    body::Body,
    extract::{
        ws::{Message as WebSocketMessage, WebSocket, WebSocketUpgrade},
        ConnectInfo, State,
    },
    http::{
        header::{CACHE_CONTROL, CONTENT_DISPOSITION, CONTENT_TYPE, HOST, ORIGIN},
        HeaderMap, HeaderValue, Request, StatusCode, Uri,
    },
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use axum_server::{
    accept::Accept,
    tls_rustls::{RustlsAcceptor, RustlsConfig},
    Handle,
};
use hbb_common::{
    anyhow::{anyhow, bail, Context},
    bytes::Bytes,
    bytes_codec::BytesCodec,
    config::Config,
    futures::{SinkExt, StreamExt},
    log,
    sha2::{Digest, Sha256},
    tcp,
    tokio::{
        self,
        io::{duplex, AsyncReadExt, AsyncWriteExt},
        net::TcpStream,
        sync::{watch, OwnedSemaphorePermit, Semaphore},
        time::timeout,
    },
    tokio_util::codec::Framed,
    ResultType, Stream,
};
use rcgen::{
    BasicConstraints, CertificateParams, DistinguishedName, DnType, ExtendedKeyUsagePurpose, IsCa,
    KeyPair, KeyUsagePurpose,
};
use rustls::pki_types::{pem::PemObject, CertificateDer, PrivateKeyDer};
use tower_http::compression::CompressionLayer;
use x509_parser::prelude::{parse_x509_certificate, GeneralName};
use zeroize::Zeroize;

use crate::server::ServerPtr;

pub const DEFAULT_WEB_PORT: u16 = 18_123;
pub const MAX_WEBSOCKET_PAYLOAD_LEN: usize = 32 * 1024 * 1024;
pub const MAX_WEBSOCKET_CLIENT_PAYLOAD_LEN: usize = 256 * 1024;
const MAX_WEB_CONNECTIONS: usize = 16;
const MAX_WEB_CONNECTIONS_PER_SOURCE: usize = 4;
const MAX_WEB_REQUESTS_PER_MINUTE: usize = 120;
const WEB_CERTIFICATE_FILENAME: &str = "web-cert.der";
const WEB_PRIVATE_KEY_FILENAME: &str = "web-key.der";
const WEB_CA_CERTIFICATE_FILENAME: &str = "web-ca-cert.der";
const WEB_CA_PRIVATE_KEY_FILENAME: &str = "web-ca-key.der";
const WEB_CERTIFICATE_METADATA_FILENAME: &str = "web-cert-metadata.json";
const WEB_RUNTIME_STATUS_FILENAME: &str = "web-runtime.json";
const MAX_HTTP_REDIRECT_REQUEST_LEN: usize = 16 * 1024;
const MAX_CUSTOM_CERTIFICATE_LEN: u64 = 4 * 1024 * 1024;
const MAX_CUSTOM_PRIVATE_KEY_LEN: u64 = 1024 * 1024;
const HTTP_REDIRECT_TIMEOUT: Duration = Duration::from_secs(5);
const WEB_SOCKET_IDLE_TIMEOUT: Duration = Duration::from_secs(120);
const WEB_SOCKET_SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(2);
const WEB_RUNTIME_HEARTBEAT_INTERVAL: Duration = Duration::from_secs(2);
const WEB_RUNTIME_STALE_SECONDS: u64 = 5;
const INDEX_HTML: &str = include_str!("../web/dist/index.html");
const APP_JS: &[u8] = include_bytes!("../web/dist/app.js");
const VIDEO_WORKER_JS: &[u8] = include_bytes!("../web/dist/video-worker.js");
const STYLE_CSS: &str = include_str!("../web/dist/style.css");
const GENERATED_CERTIFICATE_ROTATION_SECONDS: u64 = 30 * 24 * 60 * 60;
const CONTENT_SECURITY_POLICY: &str = "default-src 'self'; base-uri 'none'; connect-src 'self'; frame-ancestors 'none'; img-src 'self' data:; object-src 'none'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; worker-src 'self' blob:";

#[derive(Clone)]
struct WebState {
    server: ServerPtr,
    secure: bool,
    allowed_hosts: Arc<HashSet<String>>,
    connection_limiter: ConnectionLimiter,
    request_budget: Arc<Mutex<RequestRateBudget>>,
}

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize)]
struct GeneratedCertificateMetadata {
    subject_alt_names: Vec<String>,
    generated_at_unix_seconds: u64,
}

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize)]
pub(crate) struct WebRuntimeStatus {
    pub state: String,
    pub endpoints: Vec<String>,
    pub last_error: String,
    pub updated_at_unix_seconds: u64,
    pub process_id: u32,
    pub active_sessions: usize,
}

static ACTIVE_WEB_SESSIONS: AtomicUsize = AtomicUsize::new(0);

#[derive(Clone)]
struct ConnectionLimiter {
    global: Arc<Semaphore>,
    per_source: Arc<Mutex<HashMap<IpAddr, usize>>>,
    max_per_source: usize,
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
enum ConnectionLimitError {
    Global,
    Source,
}

struct ConnectionPermit {
    _global: OwnedSemaphorePermit,
    source: IpAddr,
    per_source: Arc<Mutex<HashMap<IpAddr, usize>>>,
}

impl ConnectionLimiter {
    fn new(max_global: usize, max_per_source: usize) -> Self {
        Self {
            global: Arc::new(Semaphore::new(max_global)),
            per_source: Arc::new(Mutex::new(HashMap::new())),
            max_per_source,
        }
    }

    fn try_acquire(&self, source: IpAddr) -> Result<ConnectionPermit, ConnectionLimitError> {
        let global = self
            .global
            .clone()
            .try_acquire_owned()
            .map_err(|_| ConnectionLimitError::Global)?;
        let mut sources = self.per_source.lock().unwrap();
        let count = sources.entry(source).or_default();
        if *count >= self.max_per_source {
            return Err(ConnectionLimitError::Source);
        }
        *count += 1;
        ACTIVE_WEB_SESSIONS.fetch_add(1, Ordering::SeqCst);
        drop(sources);
        Ok(ConnectionPermit {
            _global: global,
            source,
            per_source: self.per_source.clone(),
        })
    }
}

impl Drop for ConnectionPermit {
    fn drop(&mut self) {
        ACTIVE_WEB_SESSIONS.fetch_sub(1, Ordering::SeqCst);
        let mut sources = self.per_source.lock().unwrap();
        if let Some(count) = sources.get_mut(&self.source) {
            *count = count.saturating_sub(1);
            if *count == 0 {
                sources.remove(&self.source);
            }
        }
    }
}

fn unix_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn runtime_status_path() -> PathBuf {
    Config::path(WEB_RUNTIME_STATUS_FILENAME)
}

fn runtime_status_is_fresh(updated_at: u64, now: u64) -> bool {
    now >= updated_at && now.saturating_sub(updated_at) <= WEB_RUNTIME_STALE_SECONDS
}

fn write_runtime_status(state: &str, endpoints: &[String], last_error: &str) -> ResultType<()> {
    let status = WebRuntimeStatus {
        state: state.to_owned(),
        endpoints: endpoints.to_vec(),
        last_error: last_error.to_owned(),
        updated_at_unix_seconds: unix_seconds(),
        process_id: std::process::id(),
        active_sessions: ACTIVE_WEB_SESSIONS.load(Ordering::SeqCst),
    };
    let path = runtime_status_path();
    let bytes = serde_json::to_vec(&status).context("Failed to encode Web runtime status")?;
    let temp_path = path.with_extension("json.tmp");
    write_private_file(&temp_path, &bytes)?;
    #[cfg(windows)]
    if path.exists() {
        fs::remove_file(&path)
            .with_context(|| format!("Failed to replace Web runtime status {}", path.display()))?;
    }
    fs::rename(&temp_path, &path)
        .with_context(|| format!("Failed to publish Web runtime status {}", path.display()))
}

pub(crate) fn record_start_failure(error: &str) {
    if let Err(write_error) = write_runtime_status("failed", &[], error) {
        log::debug!("Failed to record Web startup error: {write_error}");
    }
}

pub(crate) fn runtime_status() -> WebRuntimeStatus {
    if !is_enabled() {
        return WebRuntimeStatus {
            state: "disabled".to_owned(),
            endpoints: Vec::new(),
            last_error: String::new(),
            updated_at_unix_seconds: unix_seconds(),
            process_id: 0,
            active_sessions: 0,
        };
    }
    let path = runtime_status_path();
    let parsed = fs::read(&path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<WebRuntimeStatus>(&bytes).ok());
    match parsed {
        Some(mut status)
            if runtime_status_is_fresh(status.updated_at_unix_seconds, unix_seconds()) =>
        {
            status.active_sessions = ACTIVE_WEB_SESSIONS
                .load(Ordering::SeqCst)
                .max(status.active_sessions);
            status
        }
        Some(status) => WebRuntimeStatus {
            state: "stale".to_owned(),
            endpoints: status.endpoints,
            last_error: "Web runtime heartbeat is stale".to_owned(),
            updated_at_unix_seconds: status.updated_at_unix_seconds,
            process_id: status.process_id,
            active_sessions: 0,
        },
        None => WebRuntimeStatus {
            state: "starting".to_owned(),
            endpoints: Vec::new(),
            last_error: String::new(),
            updated_at_unix_seconds: unix_seconds(),
            process_id: 0,
            active_sessions: 0,
        },
    }
}

struct RequestRateBudget {
    max_requests: usize,
    window: Duration,
    sources: HashMap<IpAddr, (Instant, usize)>,
}

impl RequestRateBudget {
    fn new(max_requests: usize, window: Duration) -> Self {
        Self {
            max_requests,
            window,
            sources: HashMap::new(),
        }
    }

    fn allow(&mut self, source: IpAddr) -> bool {
        self.allow_at(source, Instant::now())
    }

    fn allow_at(&mut self, source: IpAddr, now: Instant) -> bool {
        self.sources
            .retain(|_, (started, _)| now.duration_since(*started) < self.window);
        let (started, count) = self.sources.entry(source).or_insert((now, 0));
        if now.duration_since(*started) >= self.window {
            *started = now;
            *count = 0;
        }
        if *count >= self.max_requests {
            return false;
        }
        *count += 1;
        true
    }
}

fn option_enabled(value: &str) -> bool {
    value == "Y"
}

fn normalized_web_permission_profile(value: &str) -> &'static str {
    if value.eq_ignore_ascii_case("view-only") {
        "view-only"
    } else if value.eq_ignore_ascii_case("collaboration") {
        "collaboration"
    } else {
        "control"
    }
}

fn https_required() -> bool {
    true
}

fn parse_web_port(value: &str) -> u16 {
    value
        .parse::<u16>()
        .ok()
        .filter(|port| *port > 0)
        .unwrap_or(DEFAULT_WEB_PORT)
}

fn valid_authority(authority: &str) -> bool {
    if authority.is_empty()
        || authority.len() > 512
        || authority.chars().any(char::is_whitespace)
        || authority
            .chars()
            .any(|value| matches!(value, '@' | '/' | '\\' | '?' | '#'))
    {
        return false;
    }
    let Ok(url) = url::Url::parse(&format!("http://{authority}")) else {
        return false;
    };
    url.host().is_some()
        && url.username().is_empty()
        && url.password().is_none()
        && url.path() == "/"
        && url.query().is_none()
        && url.fragment().is_none()
}

fn request_authority<'a>(headers: &'a HeaderMap, uri: &'a Uri) -> Option<&'a str> {
    let header_authority = match headers.get(HOST) {
        Some(value) => Some(value.to_str().ok()?),
        None => None,
    };
    let uri_authority = uri.authority().map(|value| value.as_str());
    match (header_authority, uri_authority) {
        (Some(header), Some(uri)) if header == uri => Some(header),
        (Some(_), Some(_)) => None,
        (Some(header), None) => Some(header),
        (None, Some(uri)) => Some(uri),
        (None, None) => None,
    }
}

fn origin_allowed(origin: Option<&str>, authority: &str, secure: bool) -> bool {
    if !valid_authority(authority) {
        return false;
    }
    let Some(origin) = origin else {
        return false;
    };
    let expected_scheme = if secure { "https" } else { "http" };
    let Ok(actual) = url::Url::parse(origin) else {
        return false;
    };
    let Ok(expected) = url::Url::parse(&format!("{expected_scheme}://{authority}")) else {
        return false;
    };
    actual.scheme() == expected.scheme()
        && actual.host() == expected.host()
        && actual.port_or_known_default() == expected.port_or_known_default()
        && actual.username().is_empty()
        && actual.password().is_none()
        && actual.path() == "/"
        && actual.query().is_none()
        && actual.fragment().is_none()
}

fn authority_host_allowed(authority: &str, allowed_hosts: &HashSet<String>) -> bool {
    if !valid_authority(authority) {
        return false;
    }
    url::Url::parse(&format!("http://{authority}"))
        .ok()
        .and_then(|url| {
            url.host().map(|host| {
                host.to_string()
                    .trim_start_matches('[')
                    .trim_end_matches(']')
                    .to_ascii_lowercase()
            })
        })
        .map(|host| allowed_hosts.contains(&host))
        .unwrap_or(false)
}

fn validate_websocket_payload_len(len: usize) -> ResultType<()> {
    if len == 0 {
        bail!("Empty WebSocket payload");
    }
    if len > MAX_WEBSOCKET_PAYLOAD_LEN {
        bail!("WebSocket payload is too large");
    }
    Ok(())
}

pub fn is_enabled() -> bool {
    option_enabled(&Config::get_option("web-access-enabled"))
}

pub fn is_https_enabled() -> bool {
    https_required()
}

pub fn configured_port() -> u16 {
    parse_web_port(&Config::get_option("web-listen-port"))
}

fn certificate_paths() -> (PathBuf, PathBuf) {
    (
        Config::path(WEB_CERTIFICATE_FILENAME),
        Config::path(WEB_PRIVATE_KEY_FILENAME),
    )
}

fn certificate_authority_paths() -> (PathBuf, PathBuf) {
    (
        Config::path(WEB_CA_CERTIFICATE_FILENAME),
        Config::path(WEB_CA_PRIVATE_KEY_FILENAME),
    )
}

pub(crate) fn certificate_authority_path_for_ui() -> String {
    if !Config::get_option("web-certificate-path").trim().is_empty() {
        return String::new();
    }
    let (path, _) = certificate_authority_paths();
    if path.is_file() {
        path.to_string_lossy().into_owned()
    } else {
        String::new()
    }
}

fn certificate_metadata_path() -> PathBuf {
    Config::path(WEB_CERTIFICATE_METADATA_FILENAME)
}

fn custom_certificate_paths(
    certificate_path: &str,
    private_key_path: &str,
) -> ResultType<Option<(PathBuf, PathBuf)>> {
    let certificate_path = certificate_path.trim();
    let private_key_path = private_key_path.trim();
    match (certificate_path.is_empty(), private_key_path.is_empty()) {
        (true, true) => return Ok(None),
        (true, false) | (false, true) => {
            bail!("Custom Web certificate and private key must both be configured")
        }
        (false, false) => {}
    }
    let certificate_path = PathBuf::from(certificate_path);
    let private_key_path = PathBuf::from(private_key_path);
    if !certificate_path.is_absolute() || !private_key_path.is_absolute() {
        bail!("Custom Web certificate and private key paths must be absolute");
    }
    Ok(Some((certificate_path, private_key_path)))
}

pub(crate) fn validate_custom_certificate_files(
    certificate_path: &str,
    private_key_path: &str,
) -> ResultType<Option<(PathBuf, PathBuf)>> {
    let Some((certificate_path, private_key_path)) =
        custom_certificate_paths(certificate_path, private_key_path)?
    else {
        return Ok(None);
    };
    let certificate_metadata = fs::metadata(&certificate_path).with_context(|| {
        format!(
            "Failed to read custom Web certificate {}",
            certificate_path.display()
        )
    })?;
    if !certificate_metadata.is_file()
        || certificate_metadata.len() == 0
        || certificate_metadata.len() > MAX_CUSTOM_CERTIFICATE_LEN
    {
        bail!("Custom Web certificate must be a PEM file no larger than 4 MiB");
    }
    let private_key_metadata = fs::metadata(&private_key_path).with_context(|| {
        format!(
            "Failed to read custom Web private key {}",
            private_key_path.display()
        )
    })?;
    if !private_key_metadata.is_file()
        || private_key_metadata.len() == 0
        || private_key_metadata.len() > MAX_CUSTOM_PRIVATE_KEY_LEN
    {
        bail!("Custom Web private key must be a PEM file no larger than 1 MiB");
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if private_key_metadata.mode() & 0o077 != 0 {
            bail!("Custom Web private key must not be accessible by group or other users");
        }
    }
    let certificate = fs::read(&certificate_path).with_context(|| {
        format!(
            "Failed to read custom Web certificate {}",
            certificate_path.display()
        )
    })?;
    let mut private_key = fs::read(&private_key_path).with_context(|| {
        format!(
            "Failed to read custom Web private key {}",
            private_key_path.display()
        )
    })?;
    let validation_result = validate_tls_material(&certificate, &private_key);
    private_key.zeroize();
    validation_result?;
    Ok(Some((certificate_path, private_key_path)))
}

fn validate_tls_material(certificate: &[u8], private_key: &[u8]) -> ResultType<()> {
    ensure_tls_crypto_provider()?;
    let certificates = CertificateDer::pem_slice_iter(certificate)
        .collect::<Result<Vec<_>, _>>()
        .context("Custom Web certificate is not a valid PEM certificate chain")?;
    if certificates.is_empty() {
        bail!("Custom Web certificate must contain at least one PEM certificate");
    }
    validate_custom_certificate_identity(certificates[0].as_ref())?;
    let mut private_keys = PrivateKeyDer::pem_slice_iter(private_key)
        .collect::<Result<Vec<_>, _>>()
        .context("Custom Web private key is not a supported PEM private key")?;
    if private_keys.len() != 1 {
        bail!("Custom Web private key must contain exactly one private key");
    }
    rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certificates, private_keys.remove(0))
        .context("Custom Web certificate and private key are invalid or do not match")?;
    Ok(())
}

fn dns_name_matches(pattern: &str, host: &str) -> bool {
    let pattern = pattern.to_ascii_lowercase();
    let host = host.to_ascii_lowercase();
    if pattern == host {
        return true;
    }
    let Some(suffix) = pattern.strip_prefix("*.") else {
        return false;
    };
    let Some(prefix) = host.strip_suffix(suffix) else {
        return false;
    };
    prefix.ends_with('.') && !prefix[..prefix.len() - 1].contains('.')
}

fn validate_custom_certificate_identity(certificate: &[u8]) -> ResultType<()> {
    let (_, certificate) = parse_x509_certificate(certificate)
        .map_err(|_| anyhow!("Custom Web certificate could not be parsed"))?;
    if !certificate.validity().is_valid() {
        bail!("Custom Web certificate is expired or not yet valid");
    }
    let configured_hosts = Config::get_option("web-allowed-hosts")
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(normalize_configured_host)
        .collect::<Result<Vec<_>, _>>()?;
    if configured_hosts.is_empty() {
        return Ok(());
    }
    let names = certificate
        .subject_alternative_name()
        .context("Custom Web certificate has an invalid subject alternative name extension")?
        .ok_or_else(|| anyhow!("Custom Web certificate has no subject alternative names"))?;
    for host in configured_hosts {
        let host_ip = host.parse::<IpAddr>().ok();
        let covered = names.value.general_names.iter().any(|name| match name {
            GeneralName::DNSName(pattern) if host_ip.is_none() => dns_name_matches(pattern, &host),
            GeneralName::IPAddress(bytes) => match (host_ip, bytes.len()) {
                (Some(IpAddr::V4(expected)), 4) => expected.octets().as_slice() == *bytes,
                (Some(IpAddr::V6(expected)), 16) => expected.octets().as_slice() == *bytes,
                _ => false,
            },
            _ => false,
        });
        if !covered {
            bail!("Custom Web certificate does not cover allowed host {host}");
        }
    }
    Ok(())
}

fn build_certificate_subject_alt_names(
    configured_hosts: &str,
    listen_addresses: &[IpAddr],
    interface_addresses: &[IpAddr],
) -> Vec<String> {
    let mut names = vec!["localhost".to_owned(), "subnetdesk.local".to_owned()];
    names.extend(
        configured_hosts
            .split(',')
            .filter_map(|value| normalize_configured_host(value).ok()),
    );
    names.extend(
        listen_addresses
            .iter()
            .filter(|address| !address.is_unspecified())
            .map(ToString::to_string),
    );
    names.extend(interface_addresses.iter().map(ToString::to_string));
    names.sort();
    names.dedup();
    names
}

fn certificate_subject_alt_names() -> Vec<String> {
    let listen_addresses = match configured_addresses() {
        Ok(addresses) => addresses,
        Err(error) => {
            log::warn!("Failed to include Web listen addresses in certificate: {error}");
            Vec::new()
        }
    };
    let mut interface_addresses = Vec::new();
    for interface in default_net::get_interfaces() {
        interface_addresses.extend(
            interface
                .ipv4
                .into_iter()
                .filter(|network| web_source_allowed(IpAddr::V4(network.addr)))
                .map(|network| IpAddr::V4(network.addr)),
        );
        interface_addresses.extend(
            interface
                .ipv6
                .into_iter()
                .filter(|network| web_source_allowed(IpAddr::V6(network.addr)))
                .map(|network| IpAddr::V6(network.addr)),
        );
    }
    build_certificate_subject_alt_names(
        &Config::get_option("web-allowed-hosts"),
        &listen_addresses,
        &interface_addresses,
    )
}

pub(crate) fn certificate_address_signature() -> Vec<String> {
    certificate_subject_alt_names()
}

fn normalize_configured_host(value: &str) -> ResultType<String> {
    let value = value.trim();
    if value.is_empty() {
        bail!("Web allowed host must not be empty");
    }
    let url = url::Url::parse(&format!("http://{value}"))
        .map_err(|_| anyhow!("Invalid Web allowed host: {value}"))?;
    if !url.username().is_empty()
        || url.password().is_some()
        || url.port().is_some()
        || url.path() != "/"
        || url.query().is_some()
        || url.fragment().is_some()
    {
        bail!("Invalid Web allowed host: {value}");
    }
    url.host()
        .map(|host| {
            host.to_string()
                .trim_start_matches('[')
                .trim_end_matches(']')
                .to_ascii_lowercase()
        })
        .ok_or_else(|| anyhow!("Invalid Web allowed host: {value}"))
}

fn configured_allowed_hosts(
    configured: &str,
    base_hosts: Vec<String>,
) -> ResultType<HashSet<String>> {
    let configured_hosts = configured
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(normalize_configured_host)
        .collect::<Result<HashSet<_>, _>>()?;
    if configured_hosts.is_empty() {
        Ok(base_hosts
            .into_iter()
            .map(|host| host.to_ascii_lowercase())
            .collect())
    } else {
        Ok(configured_hosts)
    }
}

fn allowed_hosts() -> ResultType<Arc<HashSet<String>>> {
    let configured = Config::get_option("web-allowed-hosts");
    if configured.trim().is_empty() && !Config::get_option("web-certificate-path").trim().is_empty()
    {
        bail!("Web allowed host names are required with a custom certificate");
    }
    configured_allowed_hosts(&configured, certificate_subject_alt_names()).map(Arc::new)
}

fn generated_certificate_needs_rotation(
    metadata: &GeneratedCertificateMetadata,
    subject_alt_names: &[String],
    now_unix_seconds: u64,
) -> bool {
    metadata.subject_alt_names != subject_alt_names
        || now_unix_seconds.saturating_sub(metadata.generated_at_unix_seconds)
            >= GENERATED_CERTIFICATE_ROTATION_SECONDS
}

fn write_private_file(path: &Path, bytes: &[u8]) -> ResultType<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "Failed to create certificate directory {}",
                parent.display()
            )
        })?;
    }
    let mut options = OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(path)
        .with_context(|| format!("Failed to open {}", path.display()))?;
    file.write_all(bytes)
        .with_context(|| format!("Failed to write {}", path.display()))?;
    file.sync_all()
        .with_context(|| format!("Failed to sync {}", path.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))
            .with_context(|| format!("Failed to secure {}", path.display()))?;
    }
    Ok(())
}

#[cfg(unix)]
fn secure_private_file_permissions(path: &Path) -> ResultType<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
        .with_context(|| format!("Failed to secure {}", path.display()))?;
    Ok(())
}

#[cfg(not(unix))]
fn secure_private_file_permissions(_path: &Path) -> ResultType<()> {
    Ok(())
}

fn certificate_authority_params() -> CertificateParams {
    let mut params = CertificateParams::default();
    let mut distinguished_name = DistinguishedName::new();
    distinguished_name.push(DnType::CommonName, "SubnetDesk Local CA");
    params.distinguished_name = distinguished_name;
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    params.key_usages = vec![
        KeyUsagePurpose::KeyCertSign,
        KeyUsagePurpose::DigitalSignature,
        KeyUsagePurpose::CrlSign,
    ];
    params
}

fn generate_certificate_authority() -> ResultType<(Vec<u8>, Vec<u8>)> {
    let key_pair =
        KeyPair::generate().context("Failed to generate the Web certificate authority key")?;
    let certificate = certificate_authority_params()
        .self_signed(&key_pair)
        .context("Failed to generate the Web certificate authority")?;
    Ok((certificate.der().to_vec(), key_pair.serialize_der()))
}

fn certificate_authority_material_valid(certificate: &[u8], private_key: &[u8]) -> bool {
    let Ok(key_pair) = KeyPair::try_from(private_key) else {
        return false;
    };
    let Ok((remaining, certificate)) = parse_x509_certificate(certificate) else {
        return false;
    };
    remaining.is_empty()
        && certificate.validity().is_valid()
        && certificate.is_ca()
        && certificate.public_key().raw == key_pair.public_key_der()
}

fn generate_leaf_certificate(
    certificate_authority_key: &[u8],
    subject_alt_names: &[String],
) -> ResultType<(Vec<u8>, Vec<u8>)> {
    let certificate_authority_key = KeyPair::try_from(certificate_authority_key)
        .context("Failed to load the Web certificate authority key")?;
    let certificate_authority = certificate_authority_params()
        .self_signed(&certificate_authority_key)
        .context("Failed to reconstruct the Web certificate authority")?;
    let leaf_key = KeyPair::generate().context("Failed to generate the Web server key")?;
    let mut params = CertificateParams::new(subject_alt_names.to_vec())
        .context("Failed to configure Web certificate names")?;
    let mut distinguished_name = DistinguishedName::new();
    distinguished_name.push(DnType::CommonName, "subnetdesk.local");
    params.distinguished_name = distinguished_name;
    params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];
    params.key_usages = vec![KeyUsagePurpose::DigitalSignature];
    let certificate = params
        .signed_by(
            &leaf_key,
            &certificate_authority,
            &certificate_authority_key,
        )
        .context("Failed to sign the Web server certificate")?;
    Ok((certificate.der().to_vec(), leaf_key.serialize_der()))
}

fn load_or_generate_certificate_authority() -> ResultType<(Vec<u8>, Vec<u8>)> {
    let (certificate_path, private_key_path) = certificate_authority_paths();
    match (fs::read(&certificate_path), fs::read(&private_key_path)) {
        (Ok(certificate), Ok(private_key))
            if !certificate.is_empty()
                && !private_key.is_empty()
                && certificate_authority_material_valid(&certificate, &private_key) =>
        {
            secure_private_file_permissions(&private_key_path)?;
            return Ok((certificate, private_key));
        }
        _ => {}
    }
    let (certificate, mut private_key) = generate_certificate_authority()?;
    if let Err(err) = write_private_file(&private_key_path, &private_key) {
        private_key.zeroize();
        return Err(err);
    }
    if let Err(err) = write_private_file(&certificate_path, &certificate) {
        private_key.zeroize();
        return Err(err);
    }
    Ok((certificate, private_key))
}

fn load_generated_certificate_metadata() -> Option<GeneratedCertificateMetadata> {
    fs::read(certificate_metadata_path())
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
}

fn write_generated_certificate_metadata(metadata: &GeneratedCertificateMetadata) -> ResultType<()> {
    let bytes =
        serde_json::to_vec(metadata).context("Failed to encode Web certificate metadata")?;
    write_private_file(&certificate_metadata_path(), &bytes)
}

fn load_or_generate_certificate() -> ResultType<(Vec<Vec<u8>>, Vec<u8>)> {
    let (certificate_authority, mut certificate_authority_key) =
        load_or_generate_certificate_authority()?;
    let subject_alt_names = certificate_subject_alt_names();
    let now = unix_seconds();
    let metadata = load_generated_certificate_metadata();
    let (certificate_path, private_key_path) = certificate_paths();
    let existing = match (fs::read(&certificate_path), fs::read(&private_key_path)) {
        (Ok(certificate), Ok(private_key))
            if !certificate.is_empty()
                && !private_key.is_empty()
                && metadata
                    .as_ref()
                    .map(|metadata| {
                        !generated_certificate_needs_rotation(metadata, &subject_alt_names, now)
                    })
                    .unwrap_or(false) =>
        {
            secure_private_file_permissions(&private_key_path)?;
            Some((certificate, private_key))
        }
        _ => None,
    };
    let (certificate, private_key) = match existing {
        Some(existing) => existing,
        None => {
            let (certificate, mut private_key) =
                generate_leaf_certificate(&certificate_authority_key, &subject_alt_names)?;
            if let Err(err) = write_private_file(&private_key_path, &private_key) {
                private_key.zeroize();
                certificate_authority_key.zeroize();
                return Err(err);
            }
            if let Err(err) = write_private_file(&certificate_path, &certificate) {
                private_key.zeroize();
                certificate_authority_key.zeroize();
                return Err(err);
            }
            write_generated_certificate_metadata(&GeneratedCertificateMetadata {
                subject_alt_names,
                generated_at_unix_seconds: now,
            })?;
            (certificate, private_key)
        }
    };
    certificate_authority_key.zeroize();
    Ok((vec![certificate, certificate_authority], private_key))
}

async fn load_tls_config() -> ResultType<RustlsConfig> {
    ensure_tls_crypto_provider()?;
    if let Some((certificate_path, private_key_path)) = validate_custom_certificate_files(
        &Config::get_option("web-certificate-path"),
        &Config::get_option("web-private-key-path"),
    )? {
        return RustlsConfig::from_pem_chain_file(&certificate_path, &private_key_path)
            .await
            .with_context(|| {
                format!(
                    "Failed to load custom Web TLS certificate {} and private key {}",
                    certificate_path.display(),
                    private_key_path.display()
                )
            });
    }
    let (certificates, mut private_key) = load_or_generate_certificate()?;
    let result = RustlsConfig::from_der(certificates, private_key.clone())
        .await
        .context("Failed to load the Web TLS certificate");
    private_key.zeroize();
    if let Ok(config) = result {
        return Ok(config);
    }

    log::warn!("Regenerating an invalid Web TLS certificate");
    let _ = fs::remove_file(certificate_metadata_path());
    let (certificates, mut private_key) = load_or_generate_certificate()?;
    let result = RustlsConfig::from_der(certificates, private_key.clone())
        .await
        .context("Failed to load the regenerated Web TLS certificate");
    private_key.zeroize();
    result
}

fn ensure_tls_crypto_provider() -> ResultType<()> {
    if rustls::crypto::CryptoProvider::get_default().is_some() {
        return Ok(());
    }
    if rustls::crypto::ring::default_provider()
        .install_default()
        .is_ok()
        || rustls::crypto::CryptoProvider::get_default().is_some()
    {
        Ok(())
    } else {
        bail!("Failed to initialize the HTTPS cryptography provider")
    }
}

fn configured_address_values(web_value: &str, lan_value: &str) -> ResultType<Vec<IpAddr>> {
    let selected = if web_value.trim().is_empty() {
        lan_value
    } else {
        web_value
    };
    let values: Vec<_> = selected
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| {
            value
                .parse::<IpAddr>()
                .map_err(|_| anyhow!("Invalid Web listen address: {value}"))
        })
        .collect::<Result<_, _>>()?;
    if values.is_empty() {
        Ok(vec![IpAddr::V4(Ipv4Addr::UNSPECIFIED)])
    } else {
        Ok(values)
    }
}

fn configured_addresses() -> ResultType<Vec<IpAddr>> {
    configured_address_values(
        &Config::get_option("web-listen-addresses"),
        &Config::get_option("lan-listen-addresses"),
    )
}

fn configured_network_value(web_value: &str, lan_value: &str) -> String {
    if web_value.trim().is_empty() {
        lan_value.trim().to_owned()
    } else {
        web_value.trim().to_owned()
    }
}

fn web_source_allowed(ip: IpAddr) -> bool {
    let configured = configured_network_value(
        &Config::get_option("web-allowed-networks"),
        &Config::get_option("lan-allowed-networks"),
    );
    crate::lan_server::source_allowed_with(ip, &configured)
}

fn validate_web_network_policy() -> ResultType<()> {
    let configured = configured_network_value(
        &Config::get_option("web-allowed-networks"),
        &Config::get_option("lan-allowed-networks"),
    );
    crate::lan_server::normalize_allowed_networks(&configured)
        .context("Invalid Web allowed network policy")?;
    Ok(())
}

fn asset_hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn app_javascript_path() -> String {
    format!("/app.{}.js", &asset_hash(APP_JS)[..16])
}

fn stylesheet_path() -> String {
    format!("/style.{}.css", &asset_hash(STYLE_CSS.as_bytes())[..16])
}

fn video_worker_javascript_path() -> String {
    format!("/video-worker.{}.js", &asset_hash(VIDEO_WORKER_JS)[..16])
}

fn cache_control_for_path(path: &str) -> &'static str {
    let file_name = path.rsplit('/').next().unwrap_or_default();
    let is_hashed_asset = (file_name.starts_with("app.") && file_name.ends_with(".js"))
        || (file_name.starts_with("video-worker.") && file_name.ends_with(".js"))
        || (file_name.starts_with("style.") && file_name.ends_with(".css"));
    if is_hashed_asset
        && file_name
            .split('.')
            .nth(1)
            .map(|hash| hash.len() >= 16 && hash.bytes().all(|value| value.is_ascii_hexdigit()))
            .unwrap_or(false)
    {
        "public, max-age=31536000, immutable"
    } else {
        "no-store"
    }
}

fn looks_like_plain_http(prefix: &[u8]) -> bool {
    prefix
        .first()
        .map(|value| value.is_ascii_uppercase())
        .unwrap_or(false)
}

fn http_redirect_location(
    request: &[u8],
    https_port: u16,
    allowed_hosts: &HashSet<String>,
) -> Option<String> {
    let header_end = request.windows(4).position(|value| value == b"\r\n\r\n")?;
    let request = std::str::from_utf8(&request[..header_end]).ok()?;
    let mut lines = request.split("\r\n");
    let mut request_line = lines.next()?.split_whitespace();
    let method = request_line.next()?;
    let target = request_line.next()?;
    let version = request_line.next()?;
    if request_line.next().is_some()
        || method.is_empty()
        || !method.bytes().all(|value| value.is_ascii_uppercase())
        || !matches!(version, "HTTP/1.0" | "HTTP/1.1")
    {
        return None;
    }
    let hosts = lines
        .filter_map(|line| line.split_once(':'))
        .filter(|(name, _)| name.trim().eq_ignore_ascii_case("host"))
        .map(|(_, value)| value.trim())
        .collect::<Vec<_>>();
    let [authority] = hosts.as_slice() else {
        return None;
    };
    if !authority_host_allowed(authority, allowed_hosts) {
        return None;
    }
    let authority_url = url::Url::parse(&format!("http://{authority}")).ok()?;
    let host = match authority_url.host()? {
        url::Host::Domain(value) => value.to_owned(),
        url::Host::Ipv4(value) => value.to_string(),
        url::Host::Ipv6(value) => format!("[{value}]"),
    };
    let target = target.parse::<Uri>().ok()?;
    if target.scheme().is_some() || target.authority().is_some() || !target.path().starts_with('/')
    {
        return None;
    }
    let path_and_query = target.path_and_query()?.as_str();
    Some(format!("https://{host}:{https_port}{path_and_query}"))
}

async fn write_plain_http_response(stream: &mut TcpStream, response: &[u8]) -> io::Result<()> {
    stream.write_all(response).await?;
    stream.shutdown().await
}

async fn redirect_plain_http(
    stream: &mut TcpStream,
    https_port: u16,
    allowed_hosts: &HashSet<String>,
) -> io::Result<()> {
    let remote_addr = stream.peer_addr()?;
    if !web_source_allowed(remote_addr.ip()) {
        return write_plain_http_response(
            stream,
            b"HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\nCache-Control: no-store\r\n\r\n",
        )
        .await;
    }
    let mut request = Vec::with_capacity(1024);
    let mut buffer = [0u8; 1024];
    while request.len() < MAX_HTTP_REDIRECT_REQUEST_LEN {
        let read = stream.read(&mut buffer).await?;
        if read == 0 {
            break;
        }
        request.extend_from_slice(&buffer[..read]);
        if request.windows(4).any(|value| value == b"\r\n\r\n") {
            break;
        }
    }
    let Some(location) = http_redirect_location(&request, https_port, allowed_hosts) else {
        return write_plain_http_response(
            stream,
            b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\nCache-Control: no-store\r\n\r\n",
        )
        .await;
    };
    let response = format!(
        "HTTP/1.1 308 Permanent Redirect\r\nLocation: {location}\r\nConnection: close\r\nContent-Length: 0\r\nCache-Control: no-store\r\n\r\n"
    );
    write_plain_http_response(stream, response.as_bytes()).await
}

#[derive(Clone)]
struct HttpsRedirectAcceptor {
    https_port: u16,
    allowed_hosts: Arc<HashSet<String>>,
}

impl HttpsRedirectAcceptor {
    fn new(https_port: u16, allowed_hosts: Arc<HashSet<String>>) -> Self {
        Self {
            https_port,
            allowed_hosts,
        }
    }
}

impl<S> Accept<TcpStream, S> for HttpsRedirectAcceptor
where
    S: Send + 'static,
{
    type Stream = TcpStream;
    type Service = S;
    type Future = Pin<Box<dyn Future<Output = io::Result<(TcpStream, S)>> + Send>>;

    fn accept(&self, mut stream: TcpStream, service: S) -> Self::Future {
        let https_port = self.https_port;
        let allowed_hosts = self.allowed_hosts.clone();
        Box::pin(async move {
            let mut prefix = [0u8; 8];
            let read = timeout(HTTP_REDIRECT_TIMEOUT, stream.peek(&mut prefix))
                .await
                .map_err(|_| {
                    io::Error::new(io::ErrorKind::TimedOut, "connection detection timed out")
                })??;
            if looks_like_plain_http(&prefix[..read]) {
                let _ = timeout(
                    HTTP_REDIRECT_TIMEOUT,
                    redirect_plain_http(&mut stream, https_port, &allowed_hosts),
                )
                .await;
                return Err(io::Error::new(
                    io::ErrorKind::ConnectionAborted,
                    "plain HTTP request redirected to HTTPS",
                ));
            }
            Ok((stream, service))
        })
    }
}

fn app(state: WebState) -> Router {
    let app_path = app_javascript_path();
    let style_path = stylesheet_path();
    let worker_path = video_worker_javascript_path();
    Router::new()
        .route("/", get(index))
        .route(&app_path, get(app_javascript))
        .route(&worker_path, get(video_worker_javascript))
        .route(&style_path, get(stylesheet))
        .route("/api/info", get(info))
        .route("/api/ca-certificate", get(ca_certificate))
        .route("/ws", get(websocket_upgrade))
        .fallback(not_found)
        .layer(CompressionLayer::new().br(true).gzip(true))
        .layer(middleware::from_fn(security_headers))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            restrict_request,
        ))
        .with_state(state)
}

async fn index() -> Response {
    let html = INDEX_HTML
        .replace("/app.js", &app_javascript_path())
        .replace("/style.css", &stylesheet_path());
    ([(CONTENT_TYPE, "text/html; charset=utf-8")], html).into_response()
}

async fn app_javascript() -> Response {
    (
        [(CONTENT_TYPE, "text/javascript; charset=utf-8")],
        Body::from(APP_JS),
    )
        .into_response()
}

async fn video_worker_javascript() -> Response {
    (
        [(CONTENT_TYPE, "text/javascript; charset=utf-8")],
        Body::from(VIDEO_WORKER_JS),
    )
        .into_response()
}

async fn stylesheet() -> Response {
    ([(CONTENT_TYPE, "text/css; charset=utf-8")], STYLE_CSS).into_response()
}

async fn ca_certificate() -> Response {
    if !Config::get_option("web-certificate-path").trim().is_empty() {
        return (StatusCode::NOT_FOUND, "A custom certificate is configured").into_response();
    }
    let (certificate_path, _) = certificate_authority_paths();
    match fs::read(&certificate_path) {
        Ok(certificate) if !certificate.is_empty() => (
            [
                (CONTENT_TYPE, "application/pkix-cert"),
                (
                    CONTENT_DISPOSITION,
                    "attachment; filename=\"subnetdesk-local-ca.der\"",
                ),
            ],
            Body::from(certificate),
        )
            .into_response(),
        _ => (
            StatusCode::NOT_FOUND,
            "Certificate authority is unavailable",
        )
            .into_response(),
    }
}

async fn info(State(state): State<WebState>) -> Response {
    Json(serde_json::json!({
        "app_name": crate::get_app_name(),
        "device_name": crate::lan::device_display_name(),
        "fingerprint": crate::lan_protocol::fingerprint(&Config::get_key_pair().1),
        "version": crate::VERSION,
        "secure": state.secure,
        "certificate_mode": if Config::get_option("web-certificate-path").trim().is_empty() {
            "local-ca"
        } else {
            "custom"
        },
        "ca_certificate_url": if Config::get_option("web-certificate-path").trim().is_empty() {
            "/api/ca-certificate"
        } else {
            ""
        },
        "video_worker_url": video_worker_javascript_path(),
        "permission_profile": normalized_web_permission_profile(
            &Config::get_option("web-permission-profile")
        ),
    }))
    .into_response()
}

async fn not_found() -> Response {
    (StatusCode::NOT_FOUND, "Not found").into_response()
}

async fn restrict_request(
    State(state): State<WebState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    let source_allowed = request
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|connect| web_source_allowed(connect.0.ip()))
        .unwrap_or(false);
    let source = request
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|connect| connect.0.ip());
    let authority = request_authority(request.headers(), request.uri()).unwrap_or_default();
    if !source_allowed {
        log::warn!(
            "Rejected Web request from {}: source is outside the allowed networks",
            source
                .map(|address| address.to_string())
                .unwrap_or_else(|| "unknown source".to_owned())
        );
        return (StatusCode::FORBIDDEN, "Source address is not allowed").into_response();
    }
    if !authority_host_allowed(authority, &state.allowed_hosts) {
        log::warn!(
            "Rejected Web request from {} for disallowed Host {authority}",
            source
                .map(|address| address.to_string())
                .unwrap_or_else(|| "unknown source".to_owned())
        );
        return (StatusCode::FORBIDDEN, "Host is not allowed").into_response();
    }
    if !source
        .map(|source| state.request_budget.lock().unwrap().allow(source))
        .unwrap_or(false)
    {
        return (StatusCode::TOO_MANY_REQUESTS, "Too many requests").into_response();
    }
    next.run(request).await
}

async fn security_headers(request: Request<Body>, next: Next) -> Response {
    let cache_control = cache_control_for_path(request.uri().path());
    let mut response = next.run(request).await;
    let headers = response.headers_mut();
    headers.insert(CACHE_CONTROL, HeaderValue::from_static(cache_control));
    headers.insert(
        "content-security-policy",
        HeaderValue::from_static(CONTENT_SECURITY_POLICY),
    );
    headers.insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );
    headers.insert("x-frame-options", HeaderValue::from_static("DENY"));
    headers.insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    headers.insert(
        "permissions-policy",
        HeaderValue::from_static(
            "camera=(), microphone=(), geolocation=(), clipboard-read=(self), clipboard-write=(self), fullscreen=(self)",
        ),
    );
    response
}

async fn websocket_upgrade(
    State(state): State<WebState>,
    ConnectInfo(remote_addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    uri: Uri,
    websocket: WebSocketUpgrade,
) -> Response {
    let authority = request_authority(&headers, &uri).unwrap_or_default();
    let origin = headers.get(ORIGIN).and_then(|value| value.to_str().ok());
    if !web_source_allowed(remote_addr.ip())
        || !authority_host_allowed(authority, &state.allowed_hosts)
        || !origin_allowed(origin, authority, state.secure)
    {
        return (StatusCode::FORBIDDEN, "Forbidden").into_response();
    }
    let permit = match state.connection_limiter.try_acquire(remote_addr.ip()) {
        Ok(permit) => permit,
        Err(_) => return (StatusCode::TOO_MANY_REQUESTS, "Too many Web sessions").into_response(),
    };
    websocket
        .max_frame_size(MAX_WEBSOCKET_PAYLOAD_LEN)
        .max_message_size(MAX_WEBSOCKET_PAYLOAD_LEN)
        .on_upgrade(move |socket| bridge_websocket(socket, state.server, remote_addr, permit))
}

async fn bridge_websocket(
    mut socket: WebSocket,
    server: ServerPtr,
    remote_addr: SocketAddr,
    _permit: ConnectionPermit,
) {
    let (server_stream, bridge_stream) = duplex(4 * 1024 * 1024);
    let local_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), configured_port());
    let stream = Stream::from_framed(tcp::FramedStream::from(server_stream, local_addr));
    let mut server_task = tokio::spawn(async move {
        if let Err(err) =
            crate::server::create_lan_connection(server, stream, remote_addr, true).await
        {
            log::warn!("Web LAN connection from {remote_addr} failed: {err}");
        }
    });
    let mut framed = Framed::new(bridge_stream, BytesCodec::new());
    let idle_timeout = tokio::time::sleep(WEB_SOCKET_IDLE_TIMEOUT);
    tokio::pin!(idle_timeout);

    loop {
        tokio::select! {
            _ = &mut idle_timeout => {
                log::debug!("Closing idle Web session from {remote_addr}");
                break;
            }
            incoming = socket.recv() => {
                idle_timeout.as_mut().reset(tokio::time::Instant::now() + WEB_SOCKET_IDLE_TIMEOUT);
                match incoming {
                    Some(Ok(WebSocketMessage::Binary(bytes))) => {
                        if validate_websocket_payload_len(bytes.len()).is_err()
                            || bytes.len() > MAX_WEBSOCKET_CLIENT_PAYLOAD_LEN
                        {
                            break;
                        }
                        if let Err(err) = framed.send(Bytes::from(bytes)).await {
                            log::debug!("WebSocket bridge input closed: {err}");
                            break;
                        }
                    }
                    Some(Ok(WebSocketMessage::Close(_))) | None => break,
                    Some(Ok(WebSocketMessage::Ping(_))) | Some(Ok(WebSocketMessage::Pong(_))) => {}
                    Some(Ok(WebSocketMessage::Text(_))) => break,
                    Some(Err(err)) => {
                        log::debug!("WebSocket receive failed: {err}");
                        break;
                    }
                }
            }
            outgoing = framed.next() => {
                idle_timeout.as_mut().reset(tokio::time::Instant::now() + WEB_SOCKET_IDLE_TIMEOUT);
                match outgoing {
                    Some(Ok(bytes)) => {
                        if validate_websocket_payload_len(bytes.len()).is_err() {
                            break;
                        }
                        if socket.send(WebSocketMessage::Binary(bytes.to_vec())).await.is_err() {
                            break;
                        }
                    }
                    Some(Err(err)) => {
                        log::debug!("WebSocket bridge output failed: {err}");
                        break;
                    }
                    None => break,
                }
            }
        }
    }
    drop(framed);
    drop(socket);
    match timeout(WEB_SOCKET_SHUTDOWN_TIMEOUT, &mut server_task).await {
        Ok(Err(err)) => log::debug!("Web connection task ended unexpectedly: {err}"),
        Ok(Ok(())) => {}
        Err(_) => {
            server_task.abort();
            let _ = server_task.await;
        }
    }
}

async fn wait_for_stop(mut stop_rx: watch::Receiver<bool>) {
    loop {
        if *stop_rx.borrow() || stop_rx.changed().await.is_err() {
            return;
        }
    }
}

pub async fn bind(
    server: ServerPtr,
    stop_rx: watch::Receiver<bool>,
) -> ResultType<Vec<tokio::task::JoinHandle<()>>> {
    if !is_enabled() {
        let _ = write_runtime_status("disabled", &[], "");
        return Ok(Vec::new());
    }
    let _ = write_runtime_status("starting", &[], "");
    validate_web_network_policy()?;
    let port = configured_port();
    let native_port = Config::get_option("lan-listen-port")
        .parse::<u16>()
        .ok()
        .filter(|value| *value > 0)
        .unwrap_or(hbb_common::lan::DEFAULT_PORT);
    if port == native_port {
        bail!("Web listen port must differ from the native LAN port");
    }
    let addresses = configured_addresses()?;
    let allowed_hosts = allowed_hosts()?;
    let tls_config = load_tls_config().await?;
    let mut listeners = Vec::new();
    for address in addresses {
        let socket_addr = SocketAddr::new(address, port);
        let listener = std::net::TcpListener::bind(socket_addr)
            .with_context(|| format!("Failed to bind Web access on {socket_addr}"))?;
        listener.set_nonblocking(true)?;
        listeners.push((socket_addr, listener));
    }
    let mut endpoint_hosts = allowed_hosts.iter().cloned().collect::<Vec<_>>();
    endpoint_hosts.sort();
    let endpoints = endpoint_hosts
        .into_iter()
        .filter(|host| host != "localhost")
        .map(|host| {
            let host = if host.contains(':') {
                format!("[{host}]")
            } else {
                host
            };
            format!("https://{host}:{port}")
        })
        .collect::<Vec<_>>();
    write_runtime_status("listening", &endpoints, "")?;

    let mut handles = Vec::with_capacity(listeners.len() + 1);
    let connection_limiter =
        ConnectionLimiter::new(MAX_WEB_CONNECTIONS, MAX_WEB_CONNECTIONS_PER_SOURCE);
    let request_budget = Arc::new(Mutex::new(RequestRateBudget::new(
        MAX_WEB_REQUESTS_PER_MINUTE,
        Duration::from_secs(60),
    )));
    for (socket_addr, listener) in listeners {
        let state = WebState {
            server: server.clone(),
            secure: true,
            allowed_hosts: allowed_hosts.clone(),
            connection_limiter: connection_limiter.clone(),
            request_budget: request_budget.clone(),
        };
        let router = app(state);
        let handle = Handle::new();
        let shutdown_handle = handle.clone();
        let stop_rx = stop_rx.clone();
        log::info!("Web access listening on https://{socket_addr} with HTTP redirect");
        let acceptor = RustlsAcceptor::new(tls_config.clone())
            .acceptor(HttpsRedirectAcceptor::new(port, allowed_hosts.clone()));
        let task = tokio::spawn(async move {
            let server = axum_server::from_tcp(listener)
                .acceptor(acceptor)
                .handle(handle)
                .serve(router.into_make_service_with_connect_info::<SocketAddr>());
            tokio::pin!(server);
            tokio::select! {
                result = &mut server => {
                    if let Err(err) = result {
                        log::error!("Web HTTPS server stopped: {err}");
                    }
                }
                _ = wait_for_stop(stop_rx) => {
                    shutdown_handle.graceful_shutdown(Some(Duration::from_secs(2)));
                    if let Err(err) = server.await {
                        log::debug!("Web HTTPS server shutdown: {err}");
                    }
                }
            }
        });
        handles.push(task);
    }
    let mut heartbeat_stop_rx = stop_rx.clone();
    let heartbeat_endpoints = endpoints.clone();
    handles.push(tokio::spawn(async move {
        let mut interval = tokio::time::interval(WEB_RUNTIME_HEARTBEAT_INTERVAL);
        loop {
            tokio::select! {
                _ = interval.tick() => {
                    if let Err(err) = write_runtime_status("listening", &heartbeat_endpoints, "") {
                        log::debug!("Failed to update Web runtime heartbeat: {err}");
                    }
                }
                changed = heartbeat_stop_rx.changed() => {
                    if changed.is_err() || *heartbeat_stop_rx.borrow() {
                        let _ = write_runtime_status("stopped", &heartbeat_endpoints, "");
                        break;
                    }
                }
            }
        }
    }));
    Ok(handles)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rcgen::CertifiedKey;

    #[test]
    fn web_access_is_opt_in_and_https_is_mandatory() {
        assert!(!option_enabled(""));
        assert!(!option_enabled("N"));
        assert!(option_enabled("Y"));
        assert!(https_required());
    }

    #[test]
    fn custom_certificate_and_key_must_be_paired_absolute_paths() {
        assert!(custom_certificate_paths("", "").unwrap().is_none());
        assert!(custom_certificate_paths("/tmp/cert.pem", "").is_err());
        assert!(custom_certificate_paths("cert.pem", "key.pem").is_err());
        assert_eq!(
            custom_certificate_paths(" /tmp/cert.pem ", " /tmp/key.pem ").unwrap(),
            Some((
                PathBuf::from("/tmp/cert.pem"),
                PathBuf::from("/tmp/key.pem")
            ))
        );
    }

    #[test]
    fn same_port_distinguishes_plain_http_from_tls() {
        assert!(looks_like_plain_http(b"GET / HTTP/1.1\r\n"));
        assert!(looks_like_plain_http(b"PRI * HTTP/2.0\r\n"));
        assert!(!looks_like_plain_http(&[0x16, 0x03, 0x01, 0x00, 0xf0]));
    }

    #[test]
    fn plain_http_redirects_to_https_without_becoming_an_open_redirect() {
        let allowed = HashSet::from(["10.1.1.124".to_owned()]);
        assert_eq!(
            http_redirect_location(
                b"GET /viewer?display=1 HTTP/1.1\r\nHost: 10.1.1.124:18123\r\n\r\n",
                18_123,
                &allowed,
            ),
            Some("https://10.1.1.124:18123/viewer?display=1".to_owned())
        );
        assert_eq!(
            http_redirect_location(
                b"GET / HTTP/1.1\r\nHost: attacker.example:18123\r\n\r\n",
                18_123,
                &allowed,
            ),
            None
        );
        assert_eq!(
            http_redirect_location(
                b"GET / HTTP/1.1\r\nHost: 10.1.1.124:18123\r\nHost: attacker.example\r\n\r\n",
                18_123,
                &allowed,
            ),
            None
        );
    }

    #[test]
    fn web_port_falls_back_to_18123() {
        assert_eq!(parse_web_port(""), 18_123);
        assert_eq!(parse_web_port("0"), 18_123);
        assert_eq!(parse_web_port("65536"), 18_123);
        assert_eq!(parse_web_port("19123"), 19_123);
    }

    #[test]
    fn web_network_settings_override_lan_fallbacks() {
        assert_eq!(
            configured_address_values("127.0.0.1,::1", "0.0.0.0").unwrap(),
            vec![
                "127.0.0.1".parse::<IpAddr>().unwrap(),
                "::1".parse::<IpAddr>().unwrap()
            ]
        );
        assert_eq!(
            configured_address_values("", "192.168.1.20").unwrap(),
            vec!["192.168.1.20".parse::<IpAddr>().unwrap()]
        );
        assert_eq!(
            configured_network_value("10.8.0.0/24", "192.168.0.0/16"),
            "10.8.0.0/24"
        );
        assert_eq!(
            configured_network_value("", "192.168.0.0/16"),
            "192.168.0.0/16"
        );
    }

    #[test]
    fn explicit_web_hosts_replace_implicit_interface_hosts() {
        let hosts = configured_allowed_hosts(
            "Desk.Example.LAN, [fd00::20],desk.example.lan",
            vec!["192.168.1.20".to_owned()],
        )
        .unwrap();
        assert!(hosts.contains("desk.example.lan"));
        assert!(hosts.contains("fd00::20"));
        assert!(!hosts.contains("192.168.1.20"));
        assert_eq!(
            configured_allowed_hosts("", vec!["192.168.1.20".to_owned()]).unwrap(),
            HashSet::from(["192.168.1.20".to_owned()])
        );
        assert!(configured_allowed_hosts("user@desk.example", Vec::new()).is_err());
    }

    #[test]
    fn explicit_vpn_listener_is_an_implicit_host_and_certificate_name() {
        let vpn_address = "110.110.110.164".parse::<IpAddr>().unwrap();
        let names = build_certificate_subject_alt_names("", &[vpn_address], &[]);

        assert!(names.contains(&vpn_address.to_string()));
        assert!(configured_allowed_hosts("", names)
            .unwrap()
            .contains(&vpn_address.to_string()));
    }

    #[test]
    fn generated_certificate_rotates_when_addresses_change_or_it_ages() {
        let metadata = GeneratedCertificateMetadata {
            subject_alt_names: vec!["192.168.1.20".to_owned(), "subnetdesk.local".to_owned()],
            generated_at_unix_seconds: 1_000,
        };
        assert!(!generated_certificate_needs_rotation(
            &metadata,
            &["192.168.1.20".to_owned(), "subnetdesk.local".to_owned()],
            1_000 + GENERATED_CERTIFICATE_ROTATION_SECONDS - 1,
        ));
        assert!(generated_certificate_needs_rotation(
            &metadata,
            &["192.168.1.21".to_owned(), "subnetdesk.local".to_owned()],
            1_001,
        ));
        assert!(generated_certificate_needs_rotation(
            &metadata,
            &["192.168.1.20".to_owned(), "subnetdesk.local".to_owned()],
            1_000 + GENERATED_CERTIFICATE_ROTATION_SECONDS,
        ));
    }

    #[test]
    fn generated_certificate_authority_requires_a_matching_private_key() {
        let (certificate, private_key) = generate_certificate_authority().unwrap();
        let (_, other_private_key) = generate_certificate_authority().unwrap();
        assert!(certificate_authority_material_valid(
            &certificate,
            &private_key
        ));
        assert!(!certificate_authority_material_valid(
            &certificate,
            &other_private_key
        ));
    }

    #[test]
    fn certificate_dns_names_support_exact_and_single_label_wildcards() {
        assert!(dns_name_matches("desk.example.lan", "desk.example.lan"));
        assert!(dns_name_matches("*.example.lan", "desk.example.lan"));
        assert!(!dns_name_matches("*.example.lan", "deep.desk.example.lan"));
        assert!(!dns_name_matches("*.example.lan", "example.lan"));
    }

    #[test]
    fn static_assets_use_immutable_cache_but_html_and_api_do_not() {
        assert_eq!(cache_control_for_path("/"), "no-store");
        assert_eq!(cache_control_for_path("/api/info"), "no-store");
        assert_eq!(
            cache_control_for_path("/app.0123456789abcdef.js"),
            "public, max-age=31536000, immutable"
        );
        assert_eq!(
            cache_control_for_path("/style.0123456789abcdef.css"),
            "public, max-age=31536000, immutable"
        );
        assert_eq!(
            cache_control_for_path("/video-worker.0123456789abcdef.js"),
            "public, max-age=31536000, immutable"
        );
    }

    #[test]
    fn websocket_connection_budget_limits_each_source_and_recovers_on_drop() {
        let limiter = ConnectionLimiter::new(3, 2);
        let source: IpAddr = "192.168.1.20".parse().unwrap();
        let first = limiter.try_acquire(source).unwrap();
        let second = limiter.try_acquire(source).unwrap();
        assert!(matches!(
            limiter.try_acquire(source),
            Err(ConnectionLimitError::Source)
        ));
        drop(first);
        assert!(limiter.try_acquire(source).is_ok());
        drop(second);
    }

    #[test]
    fn request_rate_budget_rejects_bursts_until_the_window_resets() {
        let mut budget = RequestRateBudget::new(2, Duration::from_secs(60));
        let source: IpAddr = "192.168.1.20".parse().unwrap();
        let start = std::time::Instant::now();
        assert!(budget.allow_at(source, start));
        assert!(budget.allow_at(source, start));
        assert!(!budget.allow_at(source, start));
        assert!(budget.allow_at(source, start + Duration::from_secs(61)));
    }

    #[test]
    fn persisted_runtime_status_expires_without_a_heartbeat() {
        assert!(runtime_status_is_fresh(100, 104));
        assert!(!runtime_status_is_fresh(100, 106));
        assert!(!runtime_status_is_fresh(200, 100));
    }

    #[test]
    fn origin_must_match_the_request_authority_and_transport() {
        assert!(origin_allowed(
            Some("https://192.168.0.123:18123"),
            "192.168.0.123:18123",
            true,
        ));
        assert!(origin_allowed(
            Some("http://subnetdesk.local:18123"),
            "subnetdesk.local:18123",
            false,
        ));
        assert!(!origin_allowed(
            Some("https://evil.example"),
            "192.168.0.123:18123",
            true,
        ));
        assert!(!origin_allowed(None, "192.168.0.123:18123", true));
        assert!(!origin_allowed(
            Some("http://192.168.0.123:18123"),
            "192.168.0.123:18123",
            true,
        ));
    }

    #[test]
    fn authority_validation_rejects_header_injection_and_user_info() {
        assert!(valid_authority("192.168.0.123:18123"));
        assert!(valid_authority("[fd00::20]:18123"));
        assert!(!valid_authority("user@192.168.0.123:18123"));
        assert!(!valid_authority("192.168.0.123:18123\r\nX-Test: bad"));
        assert!(!valid_authority(""));
    }

    #[test]
    fn authority_must_target_the_local_device() {
        let allowed = HashSet::from([
            "192.168.0.123".to_owned(),
            "fd00::20".to_owned(),
            "subnetdesk.local".to_owned(),
        ]);
        assert!(authority_host_allowed("192.168.0.123:18123", &allowed));
        assert!(authority_host_allowed("[fd00::20]:18123", &allowed));
        assert!(authority_host_allowed("subnetdesk.local:18123", &allowed));
        assert!(!authority_host_allowed("attacker.example:18123", &allowed));
    }

    #[test]
    fn request_authority_supports_http1_and_http2_without_host_confusion() {
        let mut http1_headers = HeaderMap::new();
        http1_headers.insert(HOST, HeaderValue::from_static("10.1.1.124:18123"));
        let origin_form = "/".parse().unwrap();
        assert_eq!(
            request_authority(&http1_headers, &origin_form),
            Some("10.1.1.124:18123")
        );

        let http2_headers = HeaderMap::new();
        let absolute_form = "https://10.1.1.124:18123/".parse().unwrap();
        assert_eq!(
            request_authority(&http2_headers, &absolute_form),
            Some("10.1.1.124:18123")
        );

        let mut conflicting_headers = HeaderMap::new();
        conflicting_headers.insert(HOST, HeaderValue::from_static("attacker.example:18123"));
        assert_eq!(
            request_authority(&conflicting_headers, &absolute_form),
            None
        );
    }

    #[test]
    fn content_security_policy_allows_wasm_without_general_eval() {
        let script_sources = CONTENT_SECURITY_POLICY
            .split(';')
            .map(str::trim)
            .find(|directive| directive.starts_with("script-src "))
            .unwrap();
        let sources = script_sources.split_whitespace().collect::<Vec<_>>();

        assert!(sources.contains(&"'self'"));
        assert!(sources.contains(&"'wasm-unsafe-eval'"));
        assert!(!sources.contains(&"'unsafe-eval'"));
        assert!(!sources.contains(&"'unsafe-inline'"));
    }

    #[test]
    fn websocket_payloads_have_a_bounded_size() {
        assert!(validate_websocket_payload_len(1).is_ok());
        assert!(validate_websocket_payload_len(MAX_WEBSOCKET_PAYLOAD_LEN).is_ok());
        assert!(validate_websocket_payload_len(0).is_err());
        assert!(validate_websocket_payload_len(MAX_WEBSOCKET_PAYLOAD_LEN + 1).is_err());
    }

    #[tokio::test]
    async fn generated_certificate_can_configure_the_https_server() {
        ensure_tls_crypto_provider().unwrap();
        let (certificate_authority, mut certificate_authority_key) =
            generate_certificate_authority().unwrap();
        let (certificate, mut private_key) =
            generate_leaf_certificate(&certificate_authority_key, &["localhost".to_owned()])
                .unwrap();
        assert!(!certificate_authority.is_empty());
        assert!(!certificate_authority_key.is_empty());
        assert!(!certificate.is_empty());
        assert!(!private_key.is_empty());
        assert!(RustlsConfig::from_der(
            vec![certificate, certificate_authority],
            private_key.clone()
        )
        .await
        .is_ok());
        private_key.zeroize();
        certificate_authority_key.zeroize();
    }

    #[tokio::test]
    async fn pem_certificate_chain_can_configure_the_https_server() {
        ensure_tls_crypto_provider().unwrap();
        let CertifiedKey { cert, key_pair } =
            rcgen::generate_simple_self_signed(vec!["localhost".to_owned()]).unwrap();
        let certificate = cert.pem().into_bytes();
        let mut private_key = key_pair.serialize_pem().into_bytes();
        assert!(validate_tls_material(&certificate, &private_key).is_ok());
        assert!(RustlsConfig::from_pem(certificate, private_key.clone())
            .await
            .is_ok());
        private_key.zeroize();
    }

    #[test]
    fn custom_certificate_validation_rejects_a_mismatched_private_key() {
        let CertifiedKey { cert, .. } =
            rcgen::generate_simple_self_signed(vec!["localhost".to_owned()]).unwrap();
        let CertifiedKey { key_pair, .. } =
            rcgen::generate_simple_self_signed(vec!["localhost".to_owned()]).unwrap();
        let certificate = cert.pem();
        let mut private_key = key_pair.serialize_pem();
        assert!(validate_tls_material(certificate.as_bytes(), private_key.as_bytes()).is_err());
        private_key.zeroize();
    }
}
