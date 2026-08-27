use hbb_common::{
    anyhow::{anyhow, bail, Context},
    config::Config,
    log, ResultType,
};
use reqwest::blocking::{Client, Response};
use ring::signature::{UnparsedPublicKey, ED25519};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    fs::{self, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::{Mutex, Once},
    time::Duration,
};

const DEFAULT_MANIFEST_URL: &str =
    "https://github.com/zibo-chen/SubnetDesk/releases/latest/download/update-stable.json";
const UPDATE_EVENT_NAME: &str = "software_update";
const MAX_MANIFEST_BYTES: u64 = 1024 * 1024;
const MAX_PACKAGE_BYTES: u64 = 1024 * 1024 * 1024;
const HTTP_TIMEOUT: Duration = Duration::from_secs(30);
const AUTO_CHECK_INTERVAL: Duration = Duration::from_secs(24 * 60 * 60);
const INITIAL_CHECK_DELAY: Duration = Duration::from_secs(45);
const OPTION_ACCEPTED_SEQUENCE: &str = "software-update-accepted-sequence";
const OPTION_AUTO_CHECK: &str = "software-update-auto-check";
const OPTION_AUTO_DOWNLOAD: &str = "software-update-auto-download";

#[derive(Clone, Debug, Deserialize)]
struct UpdateArtifact {
    url: String,
    size: u64,
    sha256: String,
}

#[derive(Clone, Debug, Deserialize)]
struct UpdateManifest {
    schema: u32,
    sequence: u64,
    channel: String,
    version: String,
    published_at: String,
    expires_at: String,
    #[serde(default)]
    min_supported_version: Option<String>,
    #[serde(default)]
    mandatory_after: Option<String>,
    #[serde(default)]
    release_notes_url: String,
    artifacts: HashMap<String, UpdateArtifact>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "snake_case")]
enum UpdatePhase {
    Idle,
    Checking,
    UpToDate,
    Available,
    Downloading,
    Ready,
    Installing,
    Deferred,
    Failed,
    Disabled,
}

#[derive(Clone, Debug, Serialize)]
struct PublicUpdateState {
    state: UpdatePhase,
    current_version: String,
    available_version: String,
    progress: u8,
    message: String,
    release_notes_url: String,
    mandatory: bool,
    auto_check: bool,
    auto_download: bool,
}

struct UpdateState {
    public: PublicUpdateState,
    artifact: Option<UpdateArtifact>,
    downloaded_file: Option<PathBuf>,
    busy: bool,
}

impl Default for UpdateState {
    fn default() -> Self {
        Self {
            public: PublicUpdateState {
                state: UpdatePhase::Idle,
                current_version: env!("CARGO_PKG_VERSION").to_owned(),
                available_version: String::new(),
                progress: 0,
                message: String::new(),
                release_notes_url: String::new(),
                mandatory: false,
                auto_check: auto_check_enabled(),
                auto_download: auto_download_enabled(),
            },
            artifact: None,
            downloaded_file: None,
            busy: false,
        }
    }
}

lazy_static::lazy_static! {
    static ref STATE: Mutex<UpdateState> = Mutex::new(UpdateState::default());
}

static START_SCHEDULER: Once = Once::new();

pub fn start_scheduler() {
    START_SCHEDULER.call_once(|| {
        std::thread::spawn(|| {
            std::thread::sleep(INITIAL_CHECK_DELAY);
            loop {
                if auto_check_enabled() {
                    let _ = check(false);
                }
                std::thread::sleep(AUTO_CHECK_INTERVAL);
            }
        });
    });
}

pub fn state_json() -> String {
    match STATE.lock() {
        Ok(state) => serde_json::to_string(&state.public).unwrap_or_default(),
        Err(e) => {
            log::error!("Failed to lock software update state: {e}");
            String::new()
        }
    }
}

pub fn set_preferences(auto_check: bool, auto_download: bool) {
    let auto_check = auto_check || auto_download;
    Config::set_option(
        OPTION_AUTO_CHECK.to_owned(),
        if auto_check { "Y" } else { "N" }.to_owned(),
    );
    Config::set_option(
        OPTION_AUTO_DOWNLOAD.to_owned(),
        if auto_download { "Y" } else { "N" }.to_owned(),
    );
    if let Ok(mut state) = STATE.lock() {
        state.public.auto_check = auto_check;
        state.public.auto_download = auto_download;
        push_state(&state.public);
    }
}

pub fn check(manual: bool) -> ResultType<()> {
    begin_operation(UpdatePhase::Checking, "")?;
    std::thread::spawn(move || {
        if let Err(e) = check_inner(manual) {
            finish_error(e);
        }
    });
    Ok(())
}

pub fn download() -> ResultType<()> {
    let artifact = {
        let mut state = STATE.lock().map_err(|e| anyhow!(e.to_string()))?;
        if state.busy {
            bail!("Another software update operation is already running");
        }
        let artifact = state
            .artifact
            .clone()
            .ok_or_else(|| anyhow!("No update is available"))?;
        state.busy = true;
        state.public.state = UpdatePhase::Downloading;
        state.public.progress = 0;
        state.public.message.clear();
        push_state(&state.public);
        artifact
    };
    std::thread::spawn(move || {
        if let Err(e) = download_inner(artifact) {
            finish_error(e);
        }
    });
    Ok(())
}

pub fn install() -> ResultType<()> {
    if has_active_connections() {
        let mut state = STATE.lock().map_err(|e| anyhow!(e.to_string()))?;
        state.public.state = UpdatePhase::Deferred;
        state.public.message = "An active remote session is preventing installation".to_owned();
        push_state(&state.public);
        bail!("An active remote session is preventing installation");
    }
    let file = {
        let mut state = STATE.lock().map_err(|e| anyhow!(e.to_string()))?;
        if state.busy {
            bail!("Another software update operation is already running");
        }
        let file = state
            .downloaded_file
            .clone()
            .ok_or_else(|| anyhow!("No verified update has been downloaded"))?;
        state.busy = true;
        state.public.state = UpdatePhase::Installing;
        state.public.message.clear();
        push_state(&state.public);
        file
    };
    std::thread::spawn(move || {
        if let Err(e) = install_inner(&file) {
            finish_error(e);
        }
    });
    Ok(())
}

fn check_inner(_manual: bool) -> ResultType<()> {
    let manifest_url = manifest_url()?;
    let signature_url = format!("{manifest_url}.sig");
    let client = http_client()?;
    let manifest_bytes = read_limited(client.get(&manifest_url).send()?, MAX_MANIFEST_BYTES)?;
    let signature = read_limited(client.get(signature_url).send()?, 4096)?;
    verify_manifest_signature(&manifest_bytes, &signature)?;
    let manifest: UpdateManifest = serde_json::from_slice(&manifest_bytes)?;
    validate_manifest(&manifest)?;

    if hbb_common::get_version_number(&manifest.version)
        <= hbb_common::get_version_number(env!("CARGO_PKG_VERSION"))
    {
        let mut state = STATE.lock().map_err(|e| anyhow!(e.to_string()))?;
        state.busy = false;
        state.artifact = None;
        discard_download(&mut state);
        state.public.state = UpdatePhase::UpToDate;
        state.public.available_version.clear();
        state.public.progress = 0;
        state.public.message.clear();
        push_state(&state.public);
        return Ok(());
    }

    let artifact_key = artifact_key()?;
    let artifact = manifest
        .artifacts
        .get(&artifact_key)
        .cloned()
        .ok_or_else(|| anyhow!("Release does not contain an artifact for {artifact_key}"))?;
    validate_artifact(&artifact)?;
    Config::set_option(
        OPTION_ACCEPTED_SEQUENCE.to_owned(),
        manifest.sequence.to_string(),
    );
    let auto_download = auto_download_enabled();
    {
        let mut state = STATE.lock().map_err(|e| anyhow!(e.to_string()))?;
        state.busy = false;
        state.public.state = UpdatePhase::Available;
        state.public.available_version = manifest.version.clone();
        state.public.release_notes_url = manifest.release_notes_url.clone();
        state.public.mandatory = is_mandatory(&manifest);
        state.public.progress = 0;
        state.public.message.clear();
        state.artifact = Some(artifact);
        discard_download(&mut state);
        push_state(&state.public);
    }
    if auto_download {
        download()?;
    }
    Ok(())
}

fn download_inner(artifact: UpdateArtifact) -> ResultType<()> {
    let response = http_client()?.get(&artifact.url).send()?;
    if !response.status().is_success() {
        bail!("Update download failed with HTTP {}", response.status());
    }
    if artifact.size == 0 || artifact.size > MAX_PACKAGE_BYTES {
        bail!("Invalid update package size");
    }
    if let Some(length) = response.content_length() {
        if length != artifact.size {
            bail!("Update package size does not match the signed manifest");
        }
    }

    let filename = filename_from_url(&artifact.url)?;
    let update_dir = std::env::temp_dir().join(format!(
        "subnetdesk-update-{}",
        uuid::Uuid::new_v4().simple()
    ));
    fs::create_dir_all(&update_dir)?;
    let final_path = update_dir.join(filename);
    let part_path = final_path.with_extension(format!(
        "{}.part",
        final_path
            .extension()
            .and_then(|v| v.to_str())
            .unwrap_or_default()
    ));
    let result = stream_package(response, &part_path, &artifact);
    if let Err(e) = result {
        let _ = fs::remove_file(&part_path);
        let _ = fs::remove_dir(&update_dir);
        return Err(e);
    }
    if let Err(e) = verify_platform_signature(&part_path) {
        let _ = fs::remove_file(&part_path);
        let _ = fs::remove_dir(&update_dir);
        return Err(e);
    }
    if final_path.exists() {
        fs::remove_file(&final_path)?;
    }
    fs::rename(&part_path, &final_path)?;

    let mut state = STATE.lock().map_err(|e| anyhow!(e.to_string()))?;
    state.busy = false;
    state.downloaded_file = Some(final_path);
    state.public.state = UpdatePhase::Ready;
    state.public.progress = 100;
    state.public.message.clear();
    push_state(&state.public);
    Ok(())
}

fn stream_package(
    mut response: Response,
    path: &Path,
    artifact: &UpdateArtifact,
) -> ResultType<()> {
    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(path)?;
    let mut hasher = Sha256::new();
    let mut downloaded = 0_u64;
    let mut last_progress = 0_u8;
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = response.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        downloaded = downloaded
            .checked_add(count as u64)
            .ok_or_else(|| anyhow!("Update package size overflow"))?;
        if downloaded > artifact.size || downloaded > MAX_PACKAGE_BYTES {
            bail!("Update package exceeds the signed size");
        }
        file.write_all(&buffer[..count])?;
        hasher.update(&buffer[..count]);
        let progress = ((downloaded.saturating_mul(100)) / artifact.size) as u8;
        if progress != last_progress {
            last_progress = progress;
            update_progress(progress);
        }
    }
    file.sync_all()?;
    if downloaded != artifact.size {
        bail!("Downloaded update package is incomplete");
    }
    let actual = hex::encode(hasher.finalize());
    if !actual.eq_ignore_ascii_case(&artifact.sha256) {
        bail!("Downloaded update package failed SHA-256 verification");
    }
    Ok(())
}

fn install_inner(file: &Path) -> ResultType<()> {
    let path = file
        .to_str()
        .ok_or_else(|| anyhow!("Update path is not valid UTF-8"))?;
    #[cfg(target_os = "windows")]
    crate::platform::update_to(path)?;
    #[cfg(target_os = "macos")]
    crate::platform::update_from_dmg(path)?;
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    bail!("Automatic installation is not supported on this platform");
    Ok(())
}

fn validate_manifest(manifest: &UpdateManifest) -> ResultType<()> {
    if manifest.schema != 1 || manifest.channel != "stable" {
        bail!("Unsupported software update manifest");
    }
    if !is_supported_version(&manifest.version) {
        bail!("Software update manifest has an invalid version");
    }
    let published = chrono::DateTime::parse_from_rfc3339(&manifest.published_at)
        .context("Invalid update manifest publication time")?;
    let now = chrono::Utc::now();
    if published > now + chrono::Duration::days(1) {
        bail!("Software update manifest publication time is in the future");
    }
    let expires = chrono::DateTime::parse_from_rfc3339(&manifest.expires_at)
        .context("Invalid update manifest expiration")?;
    if expires <= published {
        bail!("Software update manifest is incomplete");
    }
    if expires < now {
        bail!("Software update manifest has expired");
    }
    let accepted = Config::get_option(OPTION_ACCEPTED_SEQUENCE)
        .parse::<u64>()
        .unwrap_or_default();
    if manifest.sequence < accepted {
        bail!("Rejected a rolled-back software update manifest");
    }
    if let Some(minimum) = &manifest.min_supported_version {
        if !is_supported_version(minimum)
            || hbb_common::get_version_number(minimum)
                > hbb_common::get_version_number(&manifest.version)
        {
            bail!("Invalid minimum supported version");
        }
    }
    Ok(())
}

fn validate_artifact(artifact: &UpdateArtifact) -> ResultType<()> {
    let url = url::Url::parse(&artifact.url)?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        bail!("Update artifact URL is not a safe HTTPS URL");
    }
    if artifact.size == 0 || artifact.size > MAX_PACKAGE_BYTES {
        bail!("Update artifact has an invalid size");
    }
    let digest = artifact.sha256.as_bytes();
    if digest.len() != 64 || !digest.iter().all(u8::is_ascii_hexdigit) {
        bail!("Update artifact has an invalid SHA-256 digest");
    }
    Ok(())
}

fn verify_manifest_signature(manifest: &[u8], signature: &[u8]) -> ResultType<()> {
    let public_key_hex = option_env!("SUBNETDESK_UPDATE_PUBLIC_KEY").unwrap_or_default();
    if public_key_hex.is_empty() {
        bail!("Automatic updates are not configured in this build");
    }
    verify_manifest_signature_with_key(public_key_hex, manifest, signature)
}

fn verify_manifest_signature_with_key(
    public_key_hex: &str,
    manifest: &[u8],
    signature: &[u8],
) -> ResultType<()> {
    let public_key = hex::decode(public_key_hex.trim()).context("Invalid update public key")?;
    if public_key.len() != 32 {
        bail!("Invalid update public key length");
    }
    let signature = hex::decode(
        std::str::from_utf8(signature)
            .context("Update signature is not UTF-8")?
            .trim(),
    )
    .context("Invalid update signature encoding")?;
    UnparsedPublicKey::new(&ED25519, public_key)
        .verify(manifest, &signature)
        .map_err(|_| anyhow!("Update manifest signature verification failed"))
}

fn read_limited(response: Response, limit: u64) -> ResultType<Vec<u8>> {
    if !response.status().is_success() {
        bail!("Update request failed with HTTP {}", response.status());
    }
    if response.content_length().map_or(false, |v| v > limit) {
        bail!("Update response is too large");
    }
    let mut bytes = Vec::new();
    response.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        bail!("Update response is too large");
    }
    Ok(bytes)
}

fn http_client() -> ResultType<Client> {
    Ok(Client::builder()
        .connect_timeout(HTTP_TIMEOUT)
        .timeout(Duration::from_secs(10 * 60))
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() >= 10 {
                attempt.error("too many software update redirects")
            } else if attempt.url().scheme() != "https" {
                attempt.error("software update redirect is not HTTPS")
            } else {
                attempt.follow()
            }
        }))
        .user_agent(format!("SubnetDesk/{} updater", env!("CARGO_PKG_VERSION")))
        .build()?)
}

fn manifest_url() -> ResultType<String> {
    let configured = option_env!("SUBNETDESK_UPDATE_MANIFEST_URL")
        .unwrap_or(DEFAULT_MANIFEST_URL)
        .trim();
    let parsed = url::Url::parse(configured)?;
    if parsed.scheme() != "https"
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.query().is_some()
        || parsed.fragment().is_some()
    {
        bail!("Software update manifest URL must be a plain HTTPS URL");
    }
    Ok(configured.to_owned())
}

fn artifact_key() -> ResultType<String> {
    let arch = match std::env::consts::ARCH {
        "x86_64" => "x86_64",
        "aarch64" => "aarch64",
        other => bail!("Unsupported update architecture: {other}"),
    };
    #[cfg(target_os = "windows")]
    {
        let package = if crate::platform::is_msi_installed()? {
            "msi"
        } else {
            "exe"
        };
        return Ok(format!("windows-{arch}-{package}"));
    }
    #[cfg(target_os = "macos")]
    return Ok(format!("macos-{arch}-dmg"));
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    bail!("Automatic updates are not supported on this platform")
}

fn filename_from_url(value: &str) -> ResultType<String> {
    let parsed = url::Url::parse(value)?;
    let filename = parsed
        .path_segments()
        .and_then(|mut segments| segments.next_back())
        .filter(|name| !name.is_empty())
        .ok_or_else(|| anyhow!("Update URL does not contain a filename"))?;
    if filename.contains('/') || filename.contains('\\') || filename.contains(':') {
        bail!("Update filename is unsafe");
    }
    let mut components = Path::new(filename).components();
    if !matches!(components.next(), Some(std::path::Component::Normal(_)))
        || components.next().is_some()
    {
        bail!("Update filename is unsafe");
    }
    Ok(filename.to_owned())
}

fn verify_platform_signature(path: &Path) -> ResultType<()> {
    #[cfg(target_os = "windows")]
    {
        let script = "$s=Get-AuthenticodeSignature -LiteralPath $args[0]; if ($s.Status -ne 'Valid') { Write-Error $s.StatusMessage; exit 1 }";
        let status = std::process::Command::new("powershell.exe")
            .args(["-NoProfile", "-NonInteractive", "-Command", script])
            .arg(path)
            .status()?;
        if !status.success() {
            bail!("Windows Authenticode verification failed");
        }
    }
    #[cfg(target_os = "macos")]
    {
        let codesign = std::process::Command::new("codesign")
            .args(["--verify", "--strict", "--verbose=2"])
            .arg(path)
            .status()?;
        if !codesign.success() {
            bail!("macOS code signature verification failed");
        }
        let gatekeeper = std::process::Command::new("spctl")
            .args([
                "--assess",
                "--type",
                "open",
                "--context",
                "context:primary-signature",
            ])
            .arg(path)
            .status()?;
        if !gatekeeper.success() {
            bail!("macOS Gatekeeper verification failed");
        }
    }
    Ok(())
}

fn has_active_connections() -> bool {
    if !crate::Connection::alive_conns().is_empty() {
        return true;
    }
    crate::flutter::sessions::get_sessions()
        .iter()
        .any(|session| {
            session
                .connection_round_state
                .lock()
                .map_or(true, |state| state.is_connected())
        })
}

fn is_mandatory(manifest: &UpdateManifest) -> bool {
    let below_minimum = manifest
        .min_supported_version
        .as_ref()
        .map_or(false, |minimum| {
            hbb_common::get_version_number(env!("CARGO_PKG_VERSION"))
                < hbb_common::get_version_number(minimum)
        });
    below_minimum
        || manifest.mandatory_after.as_ref().map_or(false, |value| {
            chrono::DateTime::parse_from_rfc3339(value)
                .map(|deadline| deadline <= chrono::Utc::now())
                .unwrap_or(false)
        })
}

fn is_supported_version(version: &str) -> bool {
    let mut parts = version.split('-');
    let Some(core) = parts.next() else {
        return false;
    };
    let core_parts = core.split('.').collect::<Vec<_>>();
    if core_parts.len() != 3
        || core_parts
            .iter()
            .any(|part| part.is_empty() || part.parse::<u32>().is_err())
    {
        return false;
    }
    if let Some(patch) = parts.next() {
        if patch.is_empty() || patch.parse::<u32>().is_err() {
            return false;
        }
    }
    parts.next().is_none()
}

fn auto_check_enabled() -> bool {
    Config::get_option(OPTION_AUTO_CHECK) != "N"
}

fn auto_download_enabled() -> bool {
    Config::get_option(OPTION_AUTO_DOWNLOAD) == "Y"
}

fn discard_download(state: &mut UpdateState) {
    let Some(path) = state.downloaded_file.take() else {
        return;
    };
    let parent = path.parent().map(Path::to_path_buf);
    let _ = fs::remove_file(path);
    if let Some(parent) = parent {
        if parent
            .file_name()
            .and_then(|name| name.to_str())
            .map_or(false, |name| name.starts_with("subnetdesk-update-"))
        {
            let _ = fs::remove_dir(parent);
        }
    }
}

fn begin_operation(phase: UpdatePhase, message: &str) -> ResultType<()> {
    let mut state = STATE.lock().map_err(|e| anyhow!(e.to_string()))?;
    if state.busy {
        bail!("Another software update operation is already running");
    }
    state.busy = true;
    state.public.state = phase;
    state.public.message = message.to_owned();
    state.public.progress = 0;
    push_state(&state.public);
    Ok(())
}

fn update_progress(progress: u8) {
    if let Ok(mut state) = STATE.lock() {
        state.public.progress = progress.min(100);
        push_state(&state.public);
    }
}

fn finish_error(error: impl std::fmt::Display) {
    log::error!("Software update failed: {error}");
    if let Ok(mut state) = STATE.lock() {
        state.busy = false;
        state.public.state = if option_env!("SUBNETDESK_UPDATE_PUBLIC_KEY")
            .unwrap_or_default()
            .is_empty()
        {
            UpdatePhase::Disabled
        } else if state.downloaded_file.is_some() {
            UpdatePhase::Ready
        } else {
            UpdatePhase::Failed
        };
        state.public.message = error.to_string();
        push_state(&state.public);
    }
}

fn push_state(state: &PublicUpdateState) {
    let mut value = match serde_json::to_value(state) {
        Ok(serde_json::Value::Object(value)) => value,
        _ => return,
    };
    value.insert(
        "name".to_owned(),
        serde_json::Value::String(UPDATE_EVENT_NAME.to_owned()),
    );
    let _ = crate::flutter::push_global_event(
        crate::flutter::APP_TYPE_MAIN,
        serde_json::Value::Object(value).to_string(),
    );
}

#[cfg(test)]
mod tests {
    use super::{
        filename_from_url, is_supported_version, validate_artifact,
        verify_manifest_signature_with_key, UpdateArtifact,
    };
    use ring::signature::{Ed25519KeyPair, KeyPair};

    #[test]
    fn accepts_safe_update_filename() {
        assert_eq!(
            filename_from_url("https://example.com/releases/subnetdesk-1.3.0-x86_64.msi")
                .expect("safe URL"),
            "subnetdesk-1.3.0-x86_64.msi"
        );
    }

    #[test]
    fn validates_signed_artifact_shape() {
        let artifact = UpdateArtifact {
            url: "https://example.com/subnetdesk.dmg".to_owned(),
            size: 42,
            sha256: "ab".repeat(32),
        };
        assert!(validate_artifact(&artifact).is_ok());
    }

    #[test]
    fn rejects_unsafe_artifact_urls() {
        let artifact = UpdateArtifact {
            url: "http://example.com/subnetdesk.dmg".to_owned(),
            size: 42,
            sha256: "ab".repeat(32),
        };
        assert!(validate_artifact(&artifact).is_err());
    }

    #[test]
    fn validates_supported_release_versions() {
        assert!(is_supported_version("1.3.0"));
        assert!(is_supported_version("1.3.0-1"));
        assert!(!is_supported_version("v1.3.0"));
        assert!(!is_supported_version("1.3"));
        assert!(!is_supported_version("1.3.0-beta"));
    }

    #[test]
    fn verifies_manifest_signatures_and_rejects_tampering() {
        let key = Ed25519KeyPair::from_seed_unchecked(&[7_u8; 32]).expect("test key");
        let manifest = br#"{"schema":1,"version":"1.3.0"}"#;
        let signature = hex::encode(key.sign(manifest).as_ref());
        let public_key = hex::encode(key.public_key().as_ref());
        assert!(
            verify_manifest_signature_with_key(&public_key, manifest, signature.as_bytes()).is_ok()
        );
        assert!(verify_manifest_signature_with_key(
            &public_key,
            br#"{"schema":1,"version":"1.3.1"}"#,
            signature.as_bytes()
        )
        .is_err());
    }
}
