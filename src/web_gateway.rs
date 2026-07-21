use std::{
    collections::HashSet,
    fs::{self, OpenOptions},
    future::Future,
    io::{self, Write},
    net::{IpAddr, Ipv4Addr, SocketAddr},
    path::{Path, PathBuf},
    pin::Pin,
    sync::Arc,
    time::Duration,
};

use axum::{
    body::Body,
    extract::{
        ws::{Message as WebSocketMessage, WebSocket, WebSocketUpgrade},
        ConnectInfo, State,
    },
    http::{
        header::{CACHE_CONTROL, CONTENT_TYPE, HOST, ORIGIN},
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
    log, tcp,
    tokio::{
        self,
        io::{duplex, AsyncReadExt, AsyncWriteExt},
        net::TcpStream,
        sync::watch,
        time::timeout,
    },
    tokio_util::codec::Framed,
    ResultType, Stream,
};
use rcgen::CertifiedKey;
use rustls::pki_types::{pem::PemObject, CertificateDer, PrivateKeyDer};
use zeroize::Zeroize;

use crate::server::ServerPtr;

pub const DEFAULT_WEB_PORT: u16 = 18_123;
pub const MAX_WEBSOCKET_PAYLOAD_LEN: usize = 32 * 1024 * 1024;
const WEB_CERTIFICATE_FILENAME: &str = "web-cert.der";
const WEB_PRIVATE_KEY_FILENAME: &str = "web-key.der";
const MAX_HTTP_REDIRECT_REQUEST_LEN: usize = 16 * 1024;
const MAX_CUSTOM_CERTIFICATE_LEN: u64 = 4 * 1024 * 1024;
const MAX_CUSTOM_PRIVATE_KEY_LEN: u64 = 1024 * 1024;
const HTTP_REDIRECT_TIMEOUT: Duration = Duration::from_secs(5);
const INDEX_HTML: &str = include_str!("../web/dist/index.html");
const APP_JS: &[u8] = include_bytes!("../web/dist/app.js");
const STYLE_CSS: &str = include_str!("../web/dist/style.css");
const CONTENT_SECURITY_POLICY: &str = "default-src 'self'; base-uri 'none'; connect-src 'self'; frame-ancestors 'none'; img-src 'self' data:; object-src 'none'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; worker-src 'self' blob:";

#[derive(Clone)]
struct WebState {
    server: ServerPtr,
    secure: bool,
    allowed_hosts: Arc<HashSet<String>>,
}

fn option_enabled(value: &str) -> bool {
    value == "Y"
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

fn certificate_subject_alt_names() -> Vec<String> {
    let mut names = vec!["localhost".to_owned(), "subnetdesk.local".to_owned()];
    for interface in default_net::get_interfaces() {
        names.extend(
            interface
                .ipv4
                .into_iter()
                .map(|network| network.addr.to_string()),
        );
        names.extend(
            interface
                .ipv6
                .into_iter()
                .map(|network| network.addr.to_string()),
        );
    }
    names.sort();
    names.dedup();
    names
}

fn allowed_hosts() -> Arc<HashSet<String>> {
    Arc::new(
        certificate_subject_alt_names()
            .into_iter()
            .map(|host| host.to_ascii_lowercase())
            .collect(),
    )
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

fn generate_self_signed_certificate() -> ResultType<(Vec<u8>, Vec<u8>)> {
    let CertifiedKey { cert, key_pair } =
        rcgen::generate_simple_self_signed(certificate_subject_alt_names())
            .context("Failed to generate the self-signed Web certificate")?;
    Ok((cert.der().to_vec(), key_pair.serialize_der()))
}

fn load_or_generate_certificate() -> ResultType<(Vec<u8>, Vec<u8>)> {
    let (certificate_path, private_key_path) = certificate_paths();
    match (fs::read(&certificate_path), fs::read(&private_key_path)) {
        (Ok(certificate), Ok(private_key))
            if !certificate.is_empty() && !private_key.is_empty() =>
        {
            secure_private_file_permissions(&private_key_path)?;
            return Ok((certificate, private_key));
        }
        _ => {}
    }
    let (certificate, mut private_key) = generate_self_signed_certificate()?;
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
    let (certificate, mut private_key) = load_or_generate_certificate()?;
    let result = RustlsConfig::from_der(vec![certificate], private_key.clone())
        .await
        .context("Failed to load the Web TLS certificate");
    private_key.zeroize();
    if let Ok(config) = result {
        return Ok(config);
    }

    log::warn!("Regenerating an invalid Web TLS certificate");
    let (certificate, mut private_key) = generate_self_signed_certificate()?;
    let (certificate_path, private_key_path) = certificate_paths();
    if let Err(err) = write_private_file(&private_key_path, &private_key) {
        private_key.zeroize();
        return Err(err);
    }
    if let Err(err) = write_private_file(&certificate_path, &certificate) {
        private_key.zeroize();
        return Err(err);
    }
    let result = RustlsConfig::from_der(vec![certificate], private_key.clone())
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

fn configured_addresses() -> ResultType<Vec<IpAddr>> {
    let values: Vec<_> = Config::get_option("lan-listen-addresses")
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
    if !crate::lan_server::source_allowed(remote_addr.ip()) {
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
    Router::new()
        .route("/", get(index))
        .route("/app.js", get(app_javascript))
        .route("/style.css", get(stylesheet))
        .route("/api/info", get(info))
        .route("/ws", get(websocket_upgrade))
        .fallback(not_found)
        .layer(middleware::from_fn(security_headers))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            restrict_request,
        ))
        .with_state(state)
}

async fn index() -> Response {
    ([(CONTENT_TYPE, "text/html; charset=utf-8")], INDEX_HTML).into_response()
}

async fn app_javascript() -> Response {
    (
        [(CONTENT_TYPE, "text/javascript; charset=utf-8")],
        Body::from(APP_JS),
    )
        .into_response()
}

async fn stylesheet() -> Response {
    ([(CONTENT_TYPE, "text/css; charset=utf-8")], STYLE_CSS).into_response()
}

async fn info(State(state): State<WebState>) -> Response {
    Json(serde_json::json!({
        "app_name": crate::get_app_name(),
        "device_name": crate::lan::device_display_name(),
        "fingerprint": crate::lan_protocol::fingerprint(&Config::get_key_pair().1),
        "version": crate::VERSION,
        "secure": state.secure,
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
        .map(|connect| crate::lan_server::source_allowed(connect.0.ip()))
        .unwrap_or(false);
    let authority = request_authority(request.headers(), request.uri()).unwrap_or_default();
    if !source_allowed || !authority_host_allowed(authority, &state.allowed_hosts) {
        return (StatusCode::FORBIDDEN, "Forbidden").into_response();
    }
    next.run(request).await
}

async fn security_headers(request: Request<Body>, next: Next) -> Response {
    let mut response = next.run(request).await;
    let headers = response.headers_mut();
    headers.insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
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
    if !crate::lan_server::source_allowed(remote_addr.ip())
        || !authority_host_allowed(authority, &state.allowed_hosts)
        || !origin_allowed(origin, authority, state.secure)
    {
        return (StatusCode::FORBIDDEN, "Forbidden").into_response();
    }
    websocket
        .max_frame_size(MAX_WEBSOCKET_PAYLOAD_LEN)
        .max_message_size(MAX_WEBSOCKET_PAYLOAD_LEN)
        .on_upgrade(move |socket| bridge_websocket(socket, state.server, remote_addr))
}

async fn bridge_websocket(mut socket: WebSocket, server: ServerPtr, remote_addr: SocketAddr) {
    let (server_stream, bridge_stream) = duplex(4 * 1024 * 1024);
    let local_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), configured_port());
    let stream = Stream::from_framed(tcp::FramedStream::from(server_stream, local_addr));
    let server_task = tokio::spawn(async move {
        if let Err(err) = crate::server::create_lan_connection(server, stream, remote_addr).await {
            log::warn!("Web LAN connection from {remote_addr} failed: {err}");
        }
    });
    let mut framed = Framed::new(bridge_stream, BytesCodec::new());

    loop {
        tokio::select! {
            incoming = socket.recv() => {
                match incoming {
                    Some(Ok(WebSocketMessage::Binary(bytes))) => {
                        if validate_websocket_payload_len(bytes.len()).is_err() {
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
    if let Err(err) = server_task.await {
        log::debug!("Web connection task ended unexpectedly: {err}");
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
        return Ok(Vec::new());
    }
    let port = configured_port();
    let native_port = Config::get_option("lan-listen-port")
        .parse::<u16>()
        .ok()
        .filter(|value| *value > 0)
        .unwrap_or(hbb_common::lan::DEFAULT_PORT);
    if port == native_port {
        bail!("Web listen port must differ from the native LAN port");
    }
    let tls_config = load_tls_config().await?;
    let mut listeners = Vec::new();
    for address in configured_addresses()? {
        let socket_addr = SocketAddr::new(address, port);
        let listener = std::net::TcpListener::bind(socket_addr)
            .with_context(|| format!("Failed to bind Web access on {socket_addr}"))?;
        listener.set_nonblocking(true)?;
        listeners.push((socket_addr, listener));
    }

    let mut handles = Vec::with_capacity(listeners.len());
    let allowed_hosts = allowed_hosts();
    for (socket_addr, listener) in listeners {
        let state = WebState {
            server: server.clone(),
            secure: true,
            allowed_hosts: allowed_hosts.clone(),
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
    Ok(handles)
}

#[cfg(test)]
mod tests {
    use super::*;

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
        let (certificate, mut private_key) = generate_self_signed_certificate().unwrap();
        assert!(!certificate.is_empty());
        assert!(!private_key.is_empty());
        assert!(
            RustlsConfig::from_der(vec![certificate], private_key.clone())
                .await
                .is_ok()
        );
        private_key.zeroize();
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
