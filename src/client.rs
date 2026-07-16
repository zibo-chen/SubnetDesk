#[cfg(not(any(target_os = "android", target_os = "ios")))]
use crate::clipboard::clipboard_listener;
use async_trait::async_trait;
use bytes::Bytes;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use clipboard_master::CallbackResult;
#[cfg(not(target_os = "linux"))]
use cpal::{
    traits::{DeviceTrait, HostTrait, StreamTrait},
    Device, Host, StreamConfig,
};
use crossbeam_queue::ArrayQueue;
use magnum_opus::{Channels::*, Decoder as AudioDecoder};
#[cfg(not(target_os = "linux"))]
use ringbuf::{ring_buffer::RbBase, Rb};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    ffi::c_void,
    net::SocketAddr,
    ops::Deref,
    sync::{
        mpsc::{self, RecvTimeoutError},
        Arc, Mutex, RwLock,
    },
};
use zeroize::Zeroize;

#[cfg(feature = "unix-file-copy-paste")]
use crate::{clipboard::check_clipboard_files, clipboard_file::unix_file_clip};
use crate::{
    common::input::{MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_TYPE_DOWN, MOUSE_TYPE_UP},
    is_keyboard_mode_supported,
    ui_interface::{get_builtin_option, use_texture_render},
    ui_session_interface::{InvokeUiSession, Session},
};
pub use file_trait::FileManager;
#[cfg(not(feature = "flutter"))]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use hbb_common::tokio::sync::mpsc::UnboundedSender;
use hbb_common::{
    allow_err,
    anyhow::{anyhow, Context},
    bail,
    config::{
        self, keys, Config, LocalConfig, PeerConfig, PeerInfoSerde, Resolution, CONNECT_TIMEOUT,
        READ_TIMEOUT,
    },
    fs::JobType,
    get_version_number, log,
    message_proto::{option_message::BoolOption, *},
    protobuf::{Enum, Message as _, MessageField},
    rand,
    rendezvous_proto::*,
    socket_client::connect_tcp_local,
    timeout,
    tokio::{
        self,
        sync::mpsc::{unbounded_channel, UnboundedReceiver},
        time::{Duration, Instant},
    },
    AddrMangle, ResultType, Stream,
};
pub use helper::*;
use scrap::{
    codec::Decoder,
    record::{Recorder, RecorderContext},
    CodecFormat, ImageFormat, ImageRgb, ImageTexture,
};

#[cfg(not(target_os = "ios"))]
use crate::clipboard::CLIPBOARD_INTERVAL;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use crate::clipboard::{check_clipboard, ClipboardSide};
#[cfg(not(feature = "flutter"))]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use crate::ui_session_interface::SessionPermissionConfig;

pub use super::lang::*;

pub mod file_trait;
pub mod helper;
pub mod io_loop;
pub mod screenshot;

pub const MILLI1: Duration = Duration::from_millis(1);
pub const SEC30: Duration = Duration::from_secs(30);
// Empirical restart reconnect grace window.
const RESTART_REMOTE_DEVICE_GRACE: Duration = Duration::from_secs(5 * 60);
pub const VIDEO_QUEUE_SIZE: usize = 120;
const MAX_DECODE_FAIL_COUNTER: usize = 3;

#[cfg(target_os = "linux")]
pub const LOGIN_MSG_DESKTOP_NOT_INITED: &str = "Desktop env is not inited";
pub const LOGIN_MSG_DESKTOP_SESSION_NOT_READY: &str = "Desktop session not ready";
pub const LOGIN_MSG_DESKTOP_XSESSION_FAILED: &str = "Desktop xsession failed";
pub const LOGIN_MSG_DESKTOP_SESSION_ANOTHER_USER: &str = "Desktop session another user login";
pub const LOGIN_MSG_DESKTOP_XORG_NOT_FOUND: &str = "Desktop xorg not found";
// ls /usr/share/xsessions/
pub const LOGIN_MSG_DESKTOP_NO_DESKTOP: &str = "Desktop none";
pub const LOGIN_MSG_DESKTOP_SESSION_NOT_READY_PASSWORD_EMPTY: &str =
    "Desktop session not ready, password empty";
pub const LOGIN_MSG_DESKTOP_SESSION_NOT_READY_PASSWORD_WRONG: &str =
    "Desktop session not ready, password wrong";
pub const LOGIN_MSG_PASSWORD_EMPTY: &str = "Empty Password";
pub const LOGIN_MSG_PASSWORD_WRONG: &str = "Wrong Password";
pub const LOGIN_MSG_LAN_CREDENTIALS_WRONG: &str = "Username or password is incorrect";
pub const LOGIN_MSG_OFFLINE: &str = "Offline";
pub const LOGIN_SCREEN_WAYLAND: &str = "Wayland login screen is not supported";
#[cfg(target_os = "linux")]
pub const SCRAP_UBUNTU_HIGHER_REQUIRED: &str = "ubuntu-21-04-required";
#[cfg(target_os = "linux")]
pub const SCRAP_OTHER_VERSION_OR_X11_REQUIRED: &str = "wayland-requires-higher-linux-version";
#[cfg(target_os = "linux")]
pub const SCRAP_XDP_PORTAL_UNAVAILABLE: &str = "xdp-portal-unavailable";
pub const SCRAP_X11_REQUIRED: &str = "x11 expected";

#[cfg(not(target_os = "linux"))]
pub const AUDIO_BUFFER_MS: usize = 3000;

#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub(crate) struct ClientClipboardContext;

#[cfg(not(feature = "flutter"))]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub(crate) struct ClientClipboardContext {
    pub cfg: SessionPermissionConfig,
    pub tx: UnboundedSender<Data>,
    #[cfg(feature = "unix-file-copy-paste")]
    pub is_file_supported: bool,
}

/// Client of the remote desktop.
pub struct Client;

#[cfg(not(target_os = "ios"))]
struct ClipboardState {
    #[cfg(feature = "flutter")]
    is_text_required: bool,
    #[cfg(all(feature = "flutter", feature = "unix-file-copy-paste"))]
    is_file_required: bool,
    running: bool,
}

#[cfg(not(target_os = "linux"))]
lazy_static::lazy_static! {
    static ref AUDIO_HOST: Host = cpal::default_host();
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
lazy_static::lazy_static! {
    static ref ENIGO: Arc<Mutex<enigo::Enigo>> = Arc::new(Mutex::new(enigo::Enigo::new()));
}

#[cfg(not(target_os = "ios"))]
lazy_static::lazy_static! {
    static ref CLIPBOARD_STATE: Arc<Mutex<ClipboardState>> = Arc::new(Mutex::new(ClipboardState::new()));
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn get_key_state(key: enigo::Key) -> bool {
    use enigo::KeyboardControllable;
    #[cfg(target_os = "macos")]
    if key == enigo::Key::NumLock {
        return true;
    }
    ENIGO.lock().unwrap().get_key_state(key)
}

impl Client {
    const CLIENT_CLIPBOARD_NAME: &'static str = "client-clipboard";

    /// Start a new encrypted LAN connection.
    pub async fn start(
        peer: &str,
        _conn_type: ConnType,
        interface: impl Interface,
    ) -> ResultType<(Stream, Vec<u8>)> {
        if config::is_incoming_only() {
            bail!("Incoming only mode");
        }
        if let Some(remaining) = interface.get_lch().read().unwrap().auth_retry_remaining() {
            bail!(
                "Authentication retry is blocked for {} seconds",
                remaining.as_secs().max(1)
            );
        }
        debug_assert!(peer == interface.get_id());
        interface.update_direct(Some(true));
        interface.update_received(false);

        let endpoint = hbb_common::lan::Endpoint::parse(peer)?;
        let mut stream = connect_tcp_local(endpoint.authority(), None, CONNECT_TIMEOUT)
            .await
            .with_context(|| format!("Failed to connect to {endpoint}"))?;
        let identity = crate::lan_protocol::client_handshake(&mut stream).await?;
        log::info!(
            "Established encrypted LAN connection to {} with fingerprint {}",
            endpoint,
            identity.fingerprint
        );
        Ok((stream, identity.device_public_key))
    }

    #[inline]
    #[cfg(feature = "flutter")]
    #[cfg(not(target_os = "ios"))]
    pub fn set_is_text_clipboard_required(b: bool) {
        CLIPBOARD_STATE.lock().unwrap().is_text_required = b;
    }

    #[inline]
    #[cfg(all(feature = "flutter", feature = "unix-file-copy-paste"))]
    pub fn set_is_file_clipboard_required(b: bool) {
        CLIPBOARD_STATE.lock().unwrap().is_file_required = b;
    }

    #[cfg(not(target_os = "ios"))]
    fn try_stop_clipboard() {
        // Disconnected Flutter sessions may keep UI handlers alive, so only connected sessions
        // should block clipboard cleanup.
        #[cfg(feature = "flutter")]
        if crate::flutter::sessions::has_connected_sessions_running(ConnType::DEFAULT_CONN) {
            return;
        }
        #[cfg(not(target_os = "android"))]
        clipboard_listener::unsubscribe(Self::CLIENT_CLIPBOARD_NAME);
        CLIPBOARD_STATE.lock().unwrap().running = false;
        #[cfg(all(feature = "unix-file-copy-paste", target_os = "linux"))]
        if let Err(e) = crate::clipboard::try_empty_clipboard_files_sync(
            crate::clipboard::ClipboardSide::Client,
            0,
        ) {
            log::error!("Failed to empty client clipboard files: {}", e);
        }
        #[cfg(all(feature = "unix-file-copy-paste", target_os = "linux"))]
        clipboard::platform::unix::fuse::uninit_fuse_context(true);
    }

    // `try_start_clipboard` is called by all session when connection is established. (When handling peer info).
    // This function only create one thread with a loop, the loop is shared by all sessions.
    // After all sessions are end, the loop exists.
    //
    // If clipboard update is detected, the text will be sent to all sessions by `send_clipboard_msg`.
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    fn try_start_clipboard(
        _client_clip_ctx: Option<ClientClipboardContext>,
    ) -> Option<UnboundedReceiver<()>> {
        let mut clipboard_lock = CLIPBOARD_STATE.lock().unwrap();
        if clipboard_lock.running {
            return None;
        }

        let (tx_cb_result, rx_cb_result) = mpsc::channel();
        if let Err(e) =
            clipboard_listener::subscribe(Self::CLIENT_CLIPBOARD_NAME.to_owned(), tx_cb_result)
        {
            log::error!("Failed to subscribe clipboard listener: {}", e);
            return None;
        }

        clipboard_lock.running = true;
        let (tx_started, rx_started) = unbounded_channel();

        log::info!("Start client clipboard loop");
        std::thread::spawn(move || {
            let mut handler = ClientClipboardHandler {
                ctx: None,
                #[cfg(not(feature = "flutter"))]
                client_clip_ctx: _client_clip_ctx,
            };

            tx_started.send(()).ok();
            loop {
                if !CLIPBOARD_STATE.lock().unwrap().running {
                    break;
                }
                match rx_cb_result.recv_timeout(Duration::from_millis(CLIPBOARD_INTERVAL)) {
                    Ok(CallbackResult::Next) => {
                        handler.check_clipboard();
                    }
                    Ok(CallbackResult::Stop) => {
                        log::debug!("Clipboard listener stopped");
                        break;
                    }
                    Ok(CallbackResult::StopWithError(err)) => {
                        log::error!("Clipboard listener stopped with error: {}", err);
                        break;
                    }
                    Err(RecvTimeoutError::Timeout) => {}
                    Err(RecvTimeoutError::Disconnected) => {
                        log::error!("Clipboard listener disconnected");
                        break;
                    }
                }
            }
            log::info!("Stop client clipboard loop");
            CLIPBOARD_STATE.lock().unwrap().running = false;
        });

        Some(rx_started)
    }

    #[cfg(target_os = "android")]
    fn try_start_clipboard(_p: Option<()>) -> Option<UnboundedReceiver<()>> {
        let mut clipboard_lock = CLIPBOARD_STATE.lock().unwrap();
        if clipboard_lock.running {
            return None;
        }
        clipboard_lock.running = true;

        log::info!("Start client clipboard loop");
        std::thread::spawn(move || {
            loop {
                if !CLIPBOARD_STATE.lock().unwrap().running {
                    break;
                }
                if !CLIPBOARD_STATE.lock().unwrap().is_text_required {
                    std::thread::sleep(Duration::from_millis(CLIPBOARD_INTERVAL));
                    continue;
                }

                if let Some(msg) = crate::clipboard::get_clipboards_msg(true) {
                    crate::flutter::send_clipboard_msg(msg, false);
                }

                std::thread::sleep(Duration::from_millis(CLIPBOARD_INTERVAL));
            }
            log::info!("Stop client clipboard loop");
            CLIPBOARD_STATE.lock().unwrap().running = false;
        });

        None
    }
}

#[cfg(not(target_os = "ios"))]
impl ClipboardState {
    fn new() -> Self {
        Self {
            #[cfg(feature = "flutter")]
            is_text_required: true,
            #[cfg(all(feature = "flutter", feature = "unix-file-copy-paste"))]
            is_file_required: true,
            running: false,
        }
    }
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
struct ClientClipboardHandler {
    ctx: Option<crate::clipboard::ClipboardContext>,
    #[cfg(not(feature = "flutter"))]
    client_clip_ctx: Option<ClientClipboardContext>,
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
impl ClientClipboardHandler {
    fn is_text_required(&self) -> bool {
        #[cfg(feature = "flutter")]
        {
            CLIPBOARD_STATE.lock().unwrap().is_text_required
        }
        #[cfg(not(feature = "flutter"))]
        {
            self.client_clip_ctx
                .as_ref()
                .map(|ctx| ctx.cfg.is_text_clipboard_required())
                .unwrap_or(false)
        }
    }

    #[cfg(feature = "unix-file-copy-paste")]
    fn is_file_required(&self) -> bool {
        #[cfg(feature = "flutter")]
        {
            CLIPBOARD_STATE.lock().unwrap().is_file_required
        }
        #[cfg(not(feature = "flutter"))]
        {
            self.client_clip_ctx
                .as_ref()
                .map(|ctx| ctx.cfg.is_file_clipboard_required())
                .unwrap_or(false)
        }
    }

    fn check_clipboard(&mut self) {
        if CLIPBOARD_STATE.lock().unwrap().running {
            #[cfg(feature = "unix-file-copy-paste")]
            if let Some(urls) = check_clipboard_files(&mut self.ctx, ClipboardSide::Client, false) {
                if !urls.is_empty() {
                    #[cfg(target_os = "macos")]
                    if crate::clipboard::is_file_url_set_by_rustdesk(&urls) {
                        return;
                    }
                    if self.is_file_required() {
                        match clipboard::platform::unix::serv_files::sync_files(&urls) {
                            Ok(()) => {
                                let msg = crate::clipboard_file::clip_2_msg(
                                    unix_file_clip::get_format_list(),
                                );
                                self.send_msg(msg, true);
                            }
                            Err(e) => {
                                log::error!("Failed to sync clipboard files: {}", e);
                            }
                        }
                        return;
                    }
                }
            }

            if let Some(msg) = check_clipboard(&mut self.ctx, ClipboardSide::Client, false) {
                if self.is_text_required() {
                    self.send_msg(msg, false);
                }
            }
        }
    }

    #[inline]
    #[cfg(feature = "flutter")]
    fn send_msg(&self, msg: Message, _is_file: bool) {
        crate::flutter::send_clipboard_msg(msg, _is_file);
    }

    #[cfg(not(feature = "flutter"))]
    fn send_msg(&self, msg: Message, _is_file: bool) {
        if let Some(ctx) = &self.client_clip_ctx {
            #[cfg(feature = "unix-file-copy-paste")]
            if _is_file {
                if ctx.is_file_supported {
                    let _ = ctx.tx.send(Data::Message(msg));
                }
                return;
            }

            let pi = ctx.cfg.lc.read().unwrap().peer_info.clone();
            if let Some(pi) = pi.as_ref() {
                if let Some(message::Union::MultiClipboards(multi_clipboards)) = &msg.union {
                    if let Some(msg_out) = crate::clipboard::get_msg_if_not_support_multi_clip(
                        &pi.version,
                        &pi.platform,
                        multi_clipboards,
                    ) {
                        let _ = ctx.tx.send(Data::Message(msg_out));
                        return;
                    }
                }
            }
            let _ = ctx.tx.send(Data::Message(msg));
        }
    }
}

/// Audio handler for the [`Client`].
#[derive(Default)]
pub struct AudioHandler {
    audio_decoder: Option<(AudioDecoder, Vec<f32>)>,
    #[cfg(target_os = "linux")]
    simple: Option<psimple::Simple>,
    #[cfg(not(target_os = "linux"))]
    audio_buffer: AudioBuffer,
    sample_rate: (u32, u32),
    #[cfg(not(target_os = "linux"))]
    audio_stream: Option<Box<dyn StreamTrait>>,
    channels: u16,
    #[cfg(not(target_os = "linux"))]
    device_channel: u16,
    #[cfg(not(target_os = "linux"))]
    ready: Arc<std::sync::Mutex<bool>>,
}

#[cfg(not(target_os = "linux"))]
struct AudioBuffer(
    pub Arc<std::sync::Mutex<ringbuf::HeapRb<f32>>>,
    usize,
    [usize; 30],
);

#[cfg(not(target_os = "linux"))]
impl Default for AudioBuffer {
    fn default() -> Self {
        Self(
            Arc::new(std::sync::Mutex::new(
                ringbuf::HeapRb::<f32>::new(48000 * 2 * AUDIO_BUFFER_MS / 1000), // 48000hz, 2 channel
            )),
            48000 * 2,
            [0; 30],
        )
    }
}

#[cfg(not(target_os = "linux"))]
impl AudioBuffer {
    pub fn resize(&mut self, sample_rate: usize, channels: usize) {
        let capacity = sample_rate * channels * AUDIO_BUFFER_MS / 1000;
        let old_capacity = self.0.lock().unwrap().capacity();
        if capacity != old_capacity {
            *self.0.lock().unwrap() = ringbuf::HeapRb::<f32>::new(capacity);
            self.1 = sample_rate * channels;
            log::info!("Audio buffer resized from {old_capacity} to {capacity}");
        }
    }

    fn try_shrink(&mut self, having: usize) {
        extern crate chrono;
        use chrono::prelude::*;

        let mut i = (having * 10) / self.1;
        if i > 29 {
            i = 29;
        }
        self.2[i] += 1;

        #[allow(non_upper_case_globals)]
        static mut tms: i64 = 0;
        let dt = Local::now().timestamp_millis();
        unsafe {
            if tms == 0 {
                tms = dt;
                return;
            } else if dt < tms + 12000 {
                return;
            }
            tms = dt;
        }

        // the safer water mark to drop
        let mut zero = 0;
        // the water mark taking most of time
        let mut max = 0;
        for i in 0..30 {
            if self.2[i] == 0 && zero == i {
                zero += 1;
            }

            if self.2[i] > self.2[max] {
                self.2[max] = 0;
                max = i;
            } else {
                self.2[i] = 0;
            }
        }
        zero = zero * 2 / 3;

        // how many data can be dropped:
        // 1. will not drop if buffered data is less than 600ms
        // 2. choose based on min(zero, max)
        const N: usize = 4;
        self.2[max] = 0;
        if max < 6 {
            return;
        } else if max > zero * N {
            max = zero * N;
        }

        let mut lock = self.0.lock().unwrap();
        let cap = lock.capacity();
        let having = lock.occupied_len();
        let skip = (cap * max / (30 * N) + 1) & (!1);
        if (having > skip * 3) && (skip > 0) {
            lock.skip(skip);
            log::info!("skip {skip}, based {max} {zero}");
        }
    }

    /// append pcm to audio buffer, if buffered data
    /// exceeds AUDIO_BUFFER_MS,  only AUDIO_BUFFER_MS
    /// will be kept.
    fn append_pcm2(&self, buffer: &[f32]) -> usize {
        let mut lock = self.0.lock().unwrap();
        let cap = lock.capacity();
        if buffer.len() > cap {
            lock.push_slice_overwrite(buffer);
            return cap;
        }

        let having = lock.occupied_len() + buffer.len();
        if having > cap {
            lock.skip(having - cap);
        }
        lock.push_slice_overwrite(buffer);
        lock.occupied_len()
    }

    /// append pcm to audio buffer, trying to drop data
    /// when data is too much (per 12 seconds) based
    /// statistics.
    pub fn append_pcm(&mut self, buffer: &[f32]) {
        let having = self.append_pcm2(buffer);
        self.try_shrink(having);
    }
}

impl AudioHandler {
    #[cfg(target_os = "linux")]
    fn start_audio(&mut self, format0: AudioFormat) -> ResultType<()> {
        use psimple::Simple;
        use pulse::sample::{Format, Spec};
        use pulse::stream::Direction;

        let spec = Spec {
            format: Format::F32le,
            channels: format0.channels as _,
            rate: format0.sample_rate as _,
        };
        if !spec.is_valid() {
            bail!("Invalid audio format");
        }

        self.simple = Some(Simple::new(
            None,                   // Use the default server
            &crate::get_app_name(), // Our application’s name
            Direction::Playback,    // We want a playback stream
            None,                   // Use the default device
            "playback",             // Description of our stream
            &spec,                  // Our sample format
            None,                   // Use default channel map
            None,                   // Use default buffering attributes
        )?);
        self.sample_rate = (format0.sample_rate, format0.sample_rate);
        Ok(())
    }

    /// Start the audio playback.
    #[cfg(not(target_os = "linux"))]
    fn start_audio(&mut self, format0: AudioFormat) -> ResultType<()> {
        let device = AUDIO_HOST
            .default_output_device()
            .with_context(|| "Failed to get default output device")?;
        log::info!(
            "Using default output device: \"{}\"",
            device.name().unwrap_or("".to_owned())
        );
        let config = device.default_output_config().map_err(|e| anyhow!(e))?;
        let sample_format = config.sample_format();
        log::info!("Default output format: {:?}", config);
        log::info!("Remote input format: {:?}", format0);
        #[allow(unused_mut)]
        let mut config: StreamConfig = config.into();
        #[cfg(not(target_os = "ios"))]
        {
            // this makes ios audio output not work
            config.buffer_size = cpal::BufferSize::Fixed(64);
        }

        self.sample_rate = (format0.sample_rate, config.sample_rate.0);
        let mut build_output_stream = |config: StreamConfig| match sample_format {
            cpal::SampleFormat::I8 => self.build_output_stream::<i8>(&config, &device),
            cpal::SampleFormat::I16 => self.build_output_stream::<i16>(&config, &device),
            cpal::SampleFormat::I32 => self.build_output_stream::<i32>(&config, &device),
            cpal::SampleFormat::I64 => self.build_output_stream::<i64>(&config, &device),
            cpal::SampleFormat::U8 => self.build_output_stream::<u8>(&config, &device),
            cpal::SampleFormat::U16 => self.build_output_stream::<u16>(&config, &device),
            cpal::SampleFormat::U32 => self.build_output_stream::<u32>(&config, &device),
            cpal::SampleFormat::U64 => self.build_output_stream::<u64>(&config, &device),
            cpal::SampleFormat::F32 => self.build_output_stream::<f32>(&config, &device),
            cpal::SampleFormat::F64 => self.build_output_stream::<f64>(&config, &device),
            f => bail!("unsupported audio format: {:?}", f),
        };
        if config.channels > format0.channels as _ {
            let no_rechannel_config = StreamConfig {
                channels: format0.channels as _,
                ..config.clone()
            };
            if let Err(_) = build_output_stream(no_rechannel_config) {
                build_output_stream(config)?;
            }
        } else {
            build_output_stream(config)?;
        }

        Ok(())
    }

    /// Handle audio format and create an audio decoder.
    pub fn handle_format(&mut self, f: AudioFormat) {
        match AudioDecoder::new(f.sample_rate, if f.channels > 1 { Stereo } else { Mono }) {
            Ok(d) => {
                let buffer = vec![0.; f.sample_rate as usize * f.channels as usize];
                self.audio_decoder = Some((d, buffer));
                self.channels = f.channels as _;
                allow_err!(self.start_audio(f));
            }
            Err(err) => {
                log::error!("Failed to create audio decoder: {}", err);
            }
        }
    }

    /// Handle audio frame and play it.
    #[inline]
    pub fn handle_frame(&mut self, frame: AudioFrame) {
        #[cfg(not(target_os = "linux"))]
        if self.audio_stream.is_none() || !self.ready.lock().unwrap().clone() {
            return;
        }
        #[cfg(target_os = "linux")]
        if self.simple.is_none() {
            log::debug!("PulseAudio simple binding does not exists");
            return;
        }
        self.audio_decoder.as_mut().map(|(d, buffer)| {
            if let Ok(n) = d.decode_float(&frame.data, buffer, false) {
                let channels = self.channels;
                let n = n * (channels as usize);
                #[cfg(not(target_os = "linux"))]
                {
                    let sample_rate0 = self.sample_rate.0;
                    let sample_rate = self.sample_rate.1;
                    let mut buffer = buffer[0..n].to_owned();
                    if sample_rate != sample_rate0 {
                        buffer = crate::audio_resample(
                            &buffer[0..n],
                            sample_rate0,
                            sample_rate,
                            channels,
                        );
                    }
                    if self.channels != self.device_channel {
                        buffer = crate::audio_rechannel(
                            buffer,
                            sample_rate,
                            sample_rate,
                            self.channels,
                            self.device_channel,
                        );
                    }
                    self.audio_buffer.append_pcm(&buffer);
                }
                #[cfg(target_os = "linux")]
                {
                    let data_u8 =
                        unsafe { std::slice::from_raw_parts::<u8>(buffer.as_ptr() as _, n * 4) };
                    self.simple.as_mut().map(|x| x.write(data_u8));
                }
            }
        });
    }

    /// Build audio output stream for current device.
    #[cfg(not(target_os = "linux"))]
    fn build_output_stream<T: cpal::Sample + cpal::SizedSample + cpal::FromSample<f32>>(
        &mut self,
        config: &StreamConfig,
        device: &Device,
    ) -> ResultType<()> {
        self.device_channel = config.channels;
        let err_fn = move |err| {
            // too many errors, will improve later
            log::trace!("an error occurred on stream: {}", err);
        };
        self.audio_buffer
            .resize(config.sample_rate.0 as _, config.channels as _);
        let audio_buffer = self.audio_buffer.0.clone();
        let ready = self.ready.clone();
        let timeout = None;
        let stream = device.build_output_stream(
            config,
            move |data: &mut [T], info: &cpal::OutputCallbackInfo| {
                if !*ready.lock().unwrap() {
                    *ready.lock().unwrap() = true;
                }

                let mut n = data.len();
                let mut lock = audio_buffer.lock().unwrap();
                let mut having = lock.occupied_len();
                // android two timestamps, one from zero, another not
                #[cfg(not(target_os = "android"))]
                if having < n {
                    let tms = info.timestamp();
                    let how_long = tms
                        .playback
                        .duration_since(&tms.callback)
                        .unwrap_or(Duration::from_millis(0));

                    // must long enough to fight back scheuler delay
                    if how_long > Duration::from_millis(6) && how_long < Duration::from_millis(3000)
                    {
                        drop(lock);
                        std::thread::sleep(how_long.div_f32(1.2));
                        lock = audio_buffer.lock().unwrap();
                        having = lock.occupied_len();
                    }

                    if having < n {
                        n = having;
                    }
                }
                #[cfg(target_os = "android")]
                if having < n {
                    n = having;
                }
                let mut elems = vec![0.0f32; n];
                if n > 0 {
                    lock.pop_slice(&mut elems);
                }
                drop(lock);

                let mut input = elems.into_iter();
                for sample in data.iter_mut() {
                    *sample = match input.next() {
                        Some(x) => T::from_sample(x),
                        _ => T::from_sample(0.),
                    };
                }
            },
            err_fn,
            timeout,
        )?;
        stream.play()?;
        self.audio_stream = Some(Box::new(stream));
        Ok(())
    }
}

/// Video handler for the [`Client`].
pub struct VideoHandler {
    decoder: Decoder,
    pub rgb: ImageRgb,
    pub texture: ImageTexture,
    recorder: Arc<Mutex<Option<Recorder>>>,
    record: bool,
    _display: usize, // useful for debug
    fail_counter: usize,
    first_frame: bool,
}

impl VideoHandler {
    #[cfg(feature = "flutter")]
    pub fn get_adapter_luid() -> Option<i64> {
        crate::flutter::get_adapter_luid()
    }

    #[cfg(not(feature = "flutter"))]
    pub fn get_adapter_luid() -> Option<i64> {
        None
    }

    /// Create a new video handler.
    pub fn new(format: CodecFormat, _display: usize) -> Self {
        let luid = Self::get_adapter_luid();
        log::info!("new video handler for display #{_display}, format: {format:?}, luid: {luid:?}");
        let rgba_format =
            if cfg!(feature = "flutter") && (cfg!(windows) || cfg!(target_os = "linux")) {
                ImageFormat::ABGR
            } else {
                ImageFormat::ARGB
            };
        VideoHandler {
            decoder: Decoder::new(format, luid),
            rgb: ImageRgb::new(rgba_format, crate::get_dst_align_rgba()),
            texture: Default::default(),
            recorder: Default::default(),
            record: false,
            _display,
            fail_counter: 0,
            first_frame: true,
        }
    }

    /// Handle a new video frame.
    #[inline]
    pub fn handle_frame(
        &mut self,
        vf: VideoFrame,
        pixelbuffer: &mut bool,
        chroma: &mut Option<Chroma>,
    ) -> ResultType<bool> {
        let format = CodecFormat::from(&vf);
        if format != self.decoder.format() {
            self.reset(Some(format));
        }
        match &vf.union {
            Some(frame) => {
                let res = self.decoder.handle_video_frame(
                    frame,
                    &mut self.rgb,
                    &mut self.texture,
                    pixelbuffer,
                    chroma,
                );
                if res.as_ref().is_ok_and(|x| *x) {
                    self.fail_counter = 0;
                } else {
                    if self.fail_counter < usize::MAX {
                        if self.first_frame && self.fail_counter < MAX_DECODE_FAIL_COUNTER {
                            log::error!("decode first frame failed");
                            self.fail_counter = MAX_DECODE_FAIL_COUNTER;
                        } else {
                            self.fail_counter += 1;
                        }
                        log::error!(
                            "Failed to handle video frame, fail counter: {}",
                            self.fail_counter
                        );
                    }
                }
                self.first_frame = false;
                if self.record {
                    self.recorder.lock().unwrap().as_mut().map(|r| {
                        let (w, h) = if *pixelbuffer {
                            (self.rgb.w, self.rgb.h)
                        } else {
                            (self.texture.w, self.texture.h)
                        };
                        r.write_frame(frame, w, h).ok();
                    });
                }
                res
            }
            _ => Ok(false),
        }
    }

    /// Reset the decoder, change format if it is Some
    pub fn reset(&mut self, format: Option<CodecFormat>) {
        log::info!(
            "reset video handler for display #{}, format: {format:?}",
            self._display
        );
        #[cfg(target_os = "macos")]
        self.rgb.set_align(crate::get_dst_align_rgba());
        let luid = Self::get_adapter_luid();
        let format = format.unwrap_or(self.decoder.format());
        self.decoder = Decoder::new(format, luid);
        self.fail_counter = 0;
        self.first_frame = true;
    }

    /// Start or stop screen record.
    pub fn record_screen(&mut self, start: bool, id: String, display_idx: usize, camera: bool) {
        self.record = false;
        if start {
            self.recorder = Recorder::new(RecorderContext {
                server: false,
                id,
                dir: crate::ui_interface::video_save_directory(false),
                display_idx,
                camera,
                tx: None,
            })
            .map_or(Default::default(), |r| Arc::new(Mutex::new(Some(r))));
        } else {
            self.recorder = Default::default();
        }

        self.record = start;
    }
}

/// Login config handler for [`Client`].
#[derive(Default)]
pub struct LoginConfigHandler {
    id: String,
    pub conn_type: ConnType,
    pub is_terminal_admin: bool,
    config: PeerConfig,
    pub port_forward: (String, i32),
    pub version: i64,
    features: Option<Features>,
    pub session_id: u64, // used for local <-> server communication
    pub supported_encoding: SupportedEncoding,
    restarting_remote_device: bool,
    // Start time of the restart grace window. On Windows the peer may briefly
    // reconnect before the real reboot disconnect.
    restart_remote_device_at: Option<Instant>,
    pub direct: Option<bool>,
    pub received: bool,
    auth_retry_until: Option<Instant>,
    pub save_ab_password_to_recent: bool, // true: connected with ab password
    pub custom_fps: Arc<Mutex<Option<usize>>>,
    pub last_auto_fps: Option<usize>,
    pub adapter_luid: Option<i64>,
    pub mark_unsupported: Vec<CodecFormat>,
    pub selected_windows_session_id: Option<u32>,
    pub peer_info: Option<PeerInfo>,
    pub lan_access_username: String,
    pub lan_fingerprint: String,
    pub record_state: bool,
    pub record_permission: bool,
}

impl Deref for LoginConfigHandler {
    type Target = PeerConfig;

    fn deref(&self) -> &Self::Target {
        &self.config
    }
}

impl LoginConfigHandler {
    /// Initialize the login config handler.
    ///
    /// # Arguments
    ///
    /// * `id` - id of peer
    /// * `conn_type` - Connection type enum.
    pub fn initialize(&mut self, id: String, conn_type: ConnType, adapter_luid: Option<i64>) {
        self.id = id;
        self.conn_type = conn_type;
        let config = self.load_config();
        self.config = config;

        let mut sid = 0;
        if sid == 0 {
            sid = rand::random();
            if sid == 0 {
                // you won the lottery
                sid = 1;
            }
        }
        self.session_id = sid;
        self.supported_encoding = Default::default();
        self.clear_restarting_remote_device();
        self.direct = None;
        self.received = false;
        self.auth_retry_until = None;
        self.adapter_luid = adapter_luid;
        self.selected_windows_session_id = None;
        self.lan_fingerprint.clear();
        self.record_state = false;
        self.record_permission = true;

        // `std::env::remove_var("IS_TERMINAL_ADMIN");` is called in `session_add_sync()` - `flutter_ffi.rs`.
        let is_terminal_admin = conn_type == ConnType::TERMINAL
            && std::env::var("IS_TERMINAL_ADMIN").map_or(false, |v| v == "Y");
        self.is_terminal_admin = is_terminal_admin;
    }

    /// Check if the client should auto login.
    /// Return password if the client should auto login, otherwise return empty string.
    pub fn should_auto_login(&self) -> String {
        let l = self.lock_after_session_end.v;
        let a = !self.get_option("auto-login").is_empty();
        let p = self.get_option("os-password");
        if !p.is_empty() && l && a {
            p
        } else {
            "".to_owned()
        }
    }

    /// Load [`PeerConfig`].
    pub fn load_config(&self) -> PeerConfig {
        debug_assert!(self.id.len() > 0);
        PeerConfig::load(&self.id)
    }

    /// Save a [`PeerConfig`] into the handler.
    ///
    /// # Arguments
    ///
    /// * `config` - [`PeerConfig`] to save.
    pub fn save_config(&mut self, config: PeerConfig) {
        config.store(&self.id);
        self.config = config;
    }

    /// Set an option for handler's [`PeerConfig`].
    ///
    /// # Arguments
    ///
    /// * `k` - key of option
    /// * `v` - value of option
    pub fn set_option(&mut self, k: String, v: String) {
        let mut config = self.load_config();
        if v == self.get_option(&k) {
            return;
        }
        config.options.insert(k, v);
        self.save_config(config);
    }

    //to-do: too many dup code below.

    /// Save view style to the current config.
    ///
    /// # Arguments
    ///
    /// * `value` - The view style to be saved.
    pub fn save_view_style(&mut self, value: String) {
        let mut config = self.load_config();
        config.view_style = value;
        self.save_config(config);
    }

    /// Save keyboard mode to the current config.
    ///
    /// # Arguments
    ///
    /// * `value` - The view style to be saved.
    pub fn save_keyboard_mode(&mut self, value: String) {
        let mut config = self.load_config();
        config.keyboard_mode = value;
        self.save_config(config);
    }

    /// Save reverse mouse wheel ("", "Y") to the current config.
    ///
    /// # Arguments
    ///
    /// * `value` - The reverse mouse wheel ("", "Y").
    pub fn save_reverse_mouse_wheel(&mut self, value: String) {
        let mut config = self.load_config();
        config.reverse_mouse_wheel = value;
        self.save_config(config);
    }

    /// Save "displays_as_individual_windows" ("", "Y") to the current config.
    ///
    /// # Arguments
    ///
    /// * `value` - The "displays_as_individual_windows" value ("", "Y").
    pub fn save_displays_as_individual_windows(&mut self, value: String) {
        let mut config = self.load_config();
        config.displays_as_individual_windows = value;
        self.save_config(config);
    }

    /// Save "use_all_my_displays_for_the_remote_session" ("", "Y") to the current config.
    ///
    /// # Arguments
    ///
    /// * `value` - The "use_all_my_displays_for_the_remote_session" value ("", "Y").
    pub fn save_use_all_my_displays_for_the_remote_session(&mut self, value: String) {
        let mut config = self.load_config();
        config.use_all_my_displays_for_the_remote_session = value;
        self.save_config(config);
    }

    /// Save scroll style to the current config.
    ///
    /// # Arguments
    ///
    /// * `value` - The scroll style to be saved.
    pub fn save_scroll_style(&mut self, value: String) {
        let mut config = self.load_config();
        config.scroll_style = value;
        self.save_config(config);
    }

    /// Save edge scroll edge thickness to the current config.
    ///
    /// # Arguments
    ///
    /// * `value` - The edge thickness to be saved.
    pub fn save_edge_scroll_edge_thickness(&mut self, value: i32) {
        let mut config = self.load_config();
        config.edge_scroll_edge_thickness = value;
        self.save_config(config);
    }

    /// Set a ui config of flutter for handler's [`PeerConfig`].
    ///
    /// # Arguments
    ///
    /// * `k` - key of option
    /// * `v` - value of option
    pub fn save_ui_flutter(&mut self, k: String, v: String) {
        let mut config = self.load_config();
        if v.is_empty() {
            config.ui_flutter.remove(&k);
        } else {
            config.ui_flutter.insert(k, v);
        }
        self.save_config(config);
    }

    pub fn set_direct_failure(&mut self, value: i32) {
        let mut config = self.load_config();
        config.direct_failures = value;
        self.save_config(config);
    }

    /// Get a ui config of flutter for handler's [`PeerConfig`].
    /// Return String if the option is found, otherwise return "".
    ///
    /// # Arguments
    ///
    /// * `k` - key of option
    pub fn get_ui_flutter(&self, k: &str) -> String {
        if let Some(v) = self.config.ui_flutter.get(k) {
            v.clone()
        } else {
            "".to_owned()
        }
    }

    /// Toggle an option in the handler.
    ///
    /// # Arguments
    ///
    /// * `name` - The name of the option to toggle.
    ///
    // It's Ok to check the option empty in this function.
    // `toggle_option()` is only called in a session.
    // Custom client advanced settings will not effect this function.
    pub fn toggle_option(&mut self, name: String) -> Option<Message> {
        let mut option = OptionMessage::default();
        let mut config = self.load_config();
        if name == "show-remote-cursor" {
            config.show_remote_cursor.v = !config.show_remote_cursor.v;
            option.show_remote_cursor = (if config.show_remote_cursor.v {
                BoolOption::Yes
            } else {
                BoolOption::No
            })
            .into();
        } else if name == "follow-remote-cursor" {
            config.follow_remote_cursor.v = !config.follow_remote_cursor.v;
            option.follow_remote_cursor = (if config.follow_remote_cursor.v {
                BoolOption::Yes
            } else {
                BoolOption::No
            })
            .into();
        } else if name == "follow-remote-window" {
            config.follow_remote_window.v = !config.follow_remote_window.v;
            option.follow_remote_window = (if config.follow_remote_window.v {
                BoolOption::Yes
            } else {
                BoolOption::No
            })
            .into();
        } else if name == "disable-audio" {
            config.disable_audio.v = !config.disable_audio.v;
            option.disable_audio = (if config.disable_audio.v {
                BoolOption::Yes
            } else {
                BoolOption::No
            })
            .into();
        } else if name == "disable-clipboard" {
            config.disable_clipboard.v = !config.disable_clipboard.v;
            option.disable_clipboard = (if config.disable_clipboard.v {
                BoolOption::Yes
            } else {
                BoolOption::No
            })
            .into();
        } else if name == "lock-after-session-end" {
            config.lock_after_session_end.v = !config.lock_after_session_end.v;
            option.lock_after_session_end = (if config.lock_after_session_end.v {
                BoolOption::Yes
            } else {
                BoolOption::No
            })
            .into();
        } else if name == keys::OPTION_TERMINAL_PERSISTENT {
            config.terminal_persistent.v = !config.terminal_persistent.v;
            option.terminal_persistent = (if config.terminal_persistent.v {
                BoolOption::Yes
            } else {
                BoolOption::No
            })
            .into();
        } else if name == "privacy-mode" {
            // try toggle privacy mode
            option.privacy_mode = (if config.privacy_mode.v {
                BoolOption::No
            } else {
                BoolOption::Yes
            })
            .into();
        } else if name == "enable-file-copy-paste" {
            config.enable_file_copy_paste.v = !config.enable_file_copy_paste.v;
            option.enable_file_transfer = (if config.enable_file_copy_paste.v {
                BoolOption::Yes
            } else {
                BoolOption::No
            })
            .into();
        } else if name == "block-input" {
            option.block_input = BoolOption::Yes.into();
        } else if name == "unblock-input" {
            option.block_input = BoolOption::No.into();
        } else if name == "show-quality-monitor" {
            config.show_quality_monitor.v = !config.show_quality_monitor.v;
        } else if name == "allow_swap_key" {
            config.allow_swap_key.v = !config.allow_swap_key.v;
        } else if name == "view-only" {
            config.view_only.v = !config.view_only.v;
            let f = |b: bool| {
                if b {
                    BoolOption::Yes.into()
                } else {
                    BoolOption::No.into()
                }
            };
            if config.view_only.v {
                option.disable_keyboard = f(true);
                option.disable_clipboard = f(true);
                option.show_remote_cursor = f(true);
                option.enable_file_transfer = f(false);
                option.lock_after_session_end = f(false);
            } else {
                option.disable_keyboard = f(false);
                option.disable_clipboard = f(self.get_toggle_option("disable-clipboard"));
                option.show_remote_cursor = f(self.get_toggle_option("show-remote-cursor"));
                option.enable_file_transfer = f(self.config.enable_file_copy_paste.v);
                option.lock_after_session_end = f(self.config.lock_after_session_end.v);
                if config.show_my_cursor.v {
                    config.show_my_cursor.v = false;
                    option.show_my_cursor = BoolOption::No.into();
                }
            }
        } else if name == "show-my-cursor" {
            config.show_my_cursor.v = !config.show_my_cursor.v;
            option.show_my_cursor = if config.show_my_cursor.v {
                BoolOption::Yes
            } else {
                BoolOption::No
            }
            .into();
        } else {
            let is_set = self
                .options
                .get(&name)
                .map(|o| !o.is_empty())
                .unwrap_or(false);
            if is_set {
                self.config.options.remove(&name);
            } else {
                self.config.options.insert(name, "Y".to_owned());
            }
            self.config.store(&self.id);
            return None;
        }

        #[cfg(feature = "unix-file-copy-paste")]
        if option.enable_file_transfer.enum_value() == Ok(BoolOption::No) {
            crate::clipboard::try_empty_clipboard_files(crate::clipboard::ClipboardSide::Client, 0);
        }

        if !name.contains("block-input") {
            self.save_config(config);
        }
        let mut misc = Misc::new();
        misc.set_option(option);
        let mut msg_out = Message::new();
        msg_out.set_misc(misc);
        Some(msg_out)
    }

    /// Get [`PeerConfig`] of the current [`LoginConfigHandler`].
    ///
    /// # Arguments
    pub fn get_config(&mut self) -> &mut PeerConfig {
        &mut self.config
    }

    /// Get [`OptionMessage`] of the current [`LoginConfigHandler`].
    /// Return `None` if there's no option, for example, when the session is only for file transfer.
    ///
    /// # Arguments
    ///
    /// * `ignore_default` - If `true`, ignore the default value of the option.
    fn get_option_message(&self, ignore_default: bool) -> Option<OptionMessage> {
        if self.conn_type.eq(&ConnType::PORT_FORWARD)
            || self.conn_type.eq(&ConnType::RDP)
            || self.conn_type.eq(&ConnType::FILE_TRANSFER)
        {
            return None;
        }
        let mut msg = OptionMessage::new();
        if self.conn_type.eq(&ConnType::TERMINAL) {
            if self.get_toggle_option(keys::OPTION_TERMINAL_PERSISTENT) {
                msg.terminal_persistent = BoolOption::Yes.into();
                return Some(msg);
            } else {
                return None;
            }
        }
        let q = self.image_quality.clone();
        if let Some(q) = self.get_image_quality_enum(&q, ignore_default) {
            msg.image_quality = q.into();
        } else if q == "custom" {
            let config = self.load_config();
            let quality = if config.custom_image_quality.is_empty() {
                50
            } else {
                config.custom_image_quality[0]
            };
            msg.custom_image_quality = quality << 8;
            #[cfg(feature = "flutter")]
            if let Some(custom_fps) = self.options.get("custom-fps") {
                let custom_fps = custom_fps.parse().unwrap_or(30);
                msg.custom_fps = custom_fps;
                *self.custom_fps.lock().unwrap() = Some(custom_fps as _);
            }
        }
        let view_only = self.get_toggle_option("view-only");
        if view_only {
            msg.disable_keyboard = BoolOption::Yes.into();
        }
        if view_only || self.get_toggle_option("show-remote-cursor") {
            msg.show_remote_cursor = BoolOption::Yes.into();
        }
        if view_only && self.get_toggle_option("show-my-cursor") {
            msg.show_my_cursor = BoolOption::Yes.into();
        }
        if self.get_toggle_option("follow-remote-cursor") {
            msg.follow_remote_cursor = BoolOption::Yes.into();
        }
        if self.get_toggle_option("follow-remote-window") {
            msg.follow_remote_window = BoolOption::Yes.into();
        }
        if !view_only && self.get_toggle_option("lock-after-session-end") {
            msg.lock_after_session_end = BoolOption::Yes.into();
        }
        if self.get_toggle_option("disable-audio") {
            msg.disable_audio = BoolOption::Yes.into();
        }
        if !view_only && self.get_toggle_option(keys::OPTION_ENABLE_FILE_COPY_PASTE) {
            msg.enable_file_transfer = BoolOption::Yes.into();
        }
        if view_only || self.get_toggle_option("disable-clipboard") {
            msg.disable_clipboard = BoolOption::Yes.into();
        }
        msg.supported_decoding = MessageField::some(self.get_supported_decoding());
        Some(msg)
    }

    pub fn get_supported_decoding(&self) -> SupportedDecoding {
        Decoder::supported_decodings(
            Some(&self.id),
            use_texture_render(),
            self.adapter_luid,
            &self.mark_unsupported,
        )
    }

    /// Parse the image quality option.
    /// Return [`ImageQuality`] if the option is valid, otherwise return `None`.
    ///
    /// # Arguments
    ///
    /// * `q` - The image quality option.
    /// * `ignore_default` - Ignore the default value.
    fn get_image_quality_enum(&self, q: &str, ignore_default: bool) -> Option<ImageQuality> {
        if q == "low" {
            Some(ImageQuality::Low)
        } else if q == "best" {
            Some(ImageQuality::Best)
        } else if q == "balanced" {
            if ignore_default {
                None
            } else {
                Some(ImageQuality::Balanced)
            }
        } else {
            None
        }
    }

    /// Get the status of a toggle option.
    ///
    /// # Arguments
    ///
    /// * `name` - The name of the toggle option.
    ///
    // It's Ok to check the option empty in this function.
    // `get_toggle_option()` is only called in a session.
    // Custom client advanced settings will not effect this function.
    pub fn get_toggle_option(&self, name: &str) -> bool {
        if name == "show-remote-cursor" {
            self.config.show_remote_cursor.v
        } else if name == "lock-after-session-end" {
            self.config.lock_after_session_end.v
        } else if name == keys::OPTION_TERMINAL_PERSISTENT {
            self.config.terminal_persistent.v
        } else if name == "privacy-mode" {
            self.config.privacy_mode.v
        } else if name == keys::OPTION_ENABLE_FILE_COPY_PASTE {
            self.config.enable_file_copy_paste.v
        } else if name == "disable-audio" {
            self.config.disable_audio.v
        } else if name == "disable-clipboard" {
            self.config.disable_clipboard.v
        } else if name == "show-quality-monitor" {
            self.config.show_quality_monitor.v
        } else if name == "allow_swap_key" {
            self.config.allow_swap_key.v
        } else if name == "view-only" {
            self.config.view_only.v
        } else if name == "show-my-cursor" {
            self.config.show_my_cursor.v
        } else if name == "follow-remote-cursor" {
            self.config.follow_remote_cursor.v
        } else if name == "follow-remote-window" {
            self.config.follow_remote_window.v
        } else {
            !self.get_option(name).is_empty()
        }
    }

    pub fn is_privacy_mode_supported(&self) -> bool {
        if let Some(features) = &self.features {
            features.privacy_mode
        } else {
            false
        }
    }

    /// Create a [`Message`] for refreshing video.
    pub fn refresh() -> Message {
        let mut misc = Misc::new();
        misc.set_refresh_video(true);
        let mut msg_out = Message::new();
        msg_out.set_misc(misc);
        msg_out
    }

    /// Create a [`Message`] for refreshing video.
    pub fn refresh_display(display: usize) -> Message {
        let mut misc = Misc::new();
        misc.set_refresh_video_display(display as _);
        let mut msg_out = Message::new();
        msg_out.set_misc(misc);
        msg_out
    }

    /// Create a [`Message`] for saving custom image quality.
    ///
    /// # Arguments
    ///
    /// * `bitrate` - The given bitrate.
    /// * `quantizer` - The given quantizer.
    pub fn save_custom_image_quality(&mut self, image_quality: i32) -> Message {
        let mut misc = Misc::new();
        misc.set_option(OptionMessage {
            custom_image_quality: image_quality << 8,
            ..Default::default()
        });
        let mut msg_out = Message::new();
        msg_out.set_misc(misc);
        let mut config = self.load_config();
        config.image_quality = "custom".to_owned();
        config.custom_image_quality = vec![image_quality as _];
        self.save_config(config);
        msg_out
    }

    /// Save the given image quality to the config.
    /// Return a [`Message`] that contains image quality, or `None` if the image quality is not valid.
    /// # Arguments
    ///
    /// * `value` - The image quality.
    pub fn save_image_quality(&mut self, value: String) -> Option<Message> {
        let mut res = None;
        if let Some(q) = self.get_image_quality_enum(&value, false) {
            let mut misc = Misc::new();
            misc.set_option(OptionMessage {
                image_quality: q.into(),
                ..Default::default()
            });
            let mut msg_out = Message::new();
            msg_out.set_misc(misc);
            res = Some(msg_out);
        }
        let mut config = self.load_config();
        config.image_quality = value;
        self.save_config(config);
        res
    }

    pub fn save_trackpad_speed(&mut self, speed: i32) {
        let mut config = self.load_config();
        config.trackpad_speed = speed;
        self.save_config(config);
    }

    /// Create a [`Message`] for saving custom fps.
    ///
    /// # Arguments
    ///
    /// * `fps` - The given fps.
    /// * `save_config` - Save the config.
    pub fn set_custom_fps(&mut self, fps: i32, save_config: bool) -> Message {
        let mut misc = Misc::new();
        misc.set_option(OptionMessage {
            custom_fps: fps,
            ..Default::default()
        });
        let mut msg_out = Message::new();
        msg_out.set_misc(misc);
        if save_config {
            let mut config = self.load_config();
            config
                .options
                .insert("custom-fps".to_owned(), fps.to_string());
            self.save_config(config);
        }
        *self.custom_fps.lock().unwrap() = Some(fps as _);
        msg_out
    }

    pub fn get_option(&self, k: &str) -> String {
        if let Some(v) = self.config.options.get(k) {
            v.clone()
        } else {
            "".to_owned()
        }
    }

    #[inline]
    pub fn get_custom_resolution(&self, display: i32) -> Option<(i32, i32)> {
        self.config
            .custom_resolutions
            .get(&display.to_string())
            .map(|r| (r.w, r.h))
    }

    #[inline]
    pub fn set_custom_resolution(&mut self, display: i32, wh: Option<(i32, i32)>) {
        let display = display.to_string();
        let mut config = self.load_config();
        match wh {
            Some((w, h)) => {
                config
                    .custom_resolutions
                    .insert(display, Resolution { w, h });
            }
            None => {
                config.custom_resolutions.remove(&display);
            }
        }
        self.save_config(config);
    }

    /// Get user name.
    /// Return the name of the given peer. If the peer has no name, return the name in the config.
    ///
    /// # Arguments
    ///
    /// * `pi` - peer info.
    pub fn get_username(&self, pi: &PeerInfo) -> String {
        return if pi.username.is_empty() {
            self.info.username.clone()
        } else {
            pi.username.clone()
        };
    }

    /// Handle peer info.
    ///
    /// # Arguments
    ///
    /// * `username` - The name of the peer.
    /// * `pi` - The peer info.
    pub fn handle_peer_info(&mut self, pi: &PeerInfo) {
        if !pi.version.is_empty() {
            self.version = hbb_common::get_version_number(&pi.version);
        }
        self.features = pi.features.clone().into_option();
        let serde = PeerInfoSerde {
            username: pi.username.clone(),
            hostname: pi.hostname.clone(),
            platform: pi.platform.clone(),
        };
        let mut config = self.load_config();
        config.info = serde;
        // Legacy peer passwords and address-book hashes are never credentials in LAN-only mode.
        config.password.clear();
        if config.keyboard_mode.is_empty() {
            if is_keyboard_mode_supported(
                &KeyboardMode::Map,
                get_version_number(&pi.version),
                &pi.platform,
            ) {
                config.keyboard_mode = KeyboardMode::Map.to_string();
            } else {
                config.keyboard_mode = KeyboardMode::Legacy.to_string();
            }
        } else {
            let keyboard_modes =
                crate::get_supported_keyboard_modes(get_version_number(&pi.version), &pi.platform);
            let current_mode = &KeyboardMode::from_str(&config.keyboard_mode).unwrap_or_default();
            if !keyboard_modes.contains(current_mode) {
                config.keyboard_mode = KeyboardMode::Legacy.to_string();
            }
        }
        // no matter if change, for update file time
        self.save_config(config);
        if !self.lan_fingerprint.is_empty() && !self.lan_access_username.is_empty() {
            if let Err(err) = LocalConfig::record_recent_lan_endpoint(
                &self.id,
                &self.lan_access_username,
                &pi.hostname,
                &pi.platform,
                &self.lan_fingerprint,
            ) {
                log::error!("Failed to store recent LAN endpoint: {err}");
            }
        }
        self.supported_encoding = pi.encoding.clone().unwrap_or_default();
        log::info!("peer info supported_encoding:{:?}", self.supported_encoding);
    }

    pub fn get_remote_dir(&self) -> String {
        serde_json::from_str::<HashMap<String, String>>(&self.get_option("remote_dir"))
            .unwrap_or_default()
            .remove(&self.info.username)
            .unwrap_or_default()
    }

    pub fn get_all_remote_dir(&self, path: String) -> String {
        let d = self.get_option("remote_dir");
        let user = self.info.username.clone();
        let mut x = serde_json::from_str::<HashMap<String, String>>(&d).unwrap_or_default();
        if path.is_empty() {
            x.remove(&user);
        } else {
            x.insert(user, path);
        }
        serde_json::to_string::<HashMap<String, String>>(&x).unwrap_or_default()
    }

    /// Create a [`Message`] for login.
    fn create_login_msg(
        &self,
        os_username: String,
        os_password: String,
        password: Vec<u8>,
    ) -> Message {
        let my_id = crate::lan_protocol::fingerprint(&Config::get_key_pair().1);
        let pure_id = self.id.clone();
        let avatar = String::new();
        let mut display_name = get_builtin_option(keys::OPTION_DISPLAY_NAME);
        if display_name.is_empty() {
            display_name = crate::username();
        }
        let display_name = display_name
            .split_whitespace()
            .map(|word| {
                word.chars()
                    .enumerate()
                    .map(|(i, c)| {
                        if i == 0 {
                            c.to_uppercase().to_string()
                        } else {
                            c.to_string()
                        }
                    })
                    .collect::<String>()
            })
            .collect::<Vec<_>>()
            .join(" ");
        #[cfg(not(target_os = "android"))]
        let my_platform = hbb_common::whoami::platform().to_string();
        #[cfg(target_os = "android")]
        let my_platform = "Android".into();
        let hwid = Bytes::new();
        let mut lr = LoginRequest {
            username: pure_id,
            password: password.into(),
            my_id,
            my_name: display_name,
            my_platform,
            option: self.get_option_message(true).into(),
            session_id: self.session_id,
            version: crate::VERSION.to_string(),
            os_login: Some(OSLogin {
                username: os_username,
                password: os_password,
                ..Default::default()
            })
            .into(),
            hwid,
            avatar,
            ..Default::default()
        };
        match self.conn_type {
            ConnType::FILE_TRANSFER => lr.set_file_transfer(FileTransfer {
                dir: self.get_remote_dir(),
                show_hidden: !self.get_option("remote_show_hidden").is_empty(),
                ..Default::default()
            }),
            ConnType::VIEW_CAMERA => lr.set_view_camera(Default::default()),
            ConnType::PORT_FORWARD | ConnType::RDP => lr.set_port_forward(PortForward {
                host: self.port_forward.0.clone(),
                port: self.port_forward.1,
                ..Default::default()
            }),
            ConnType::TERMINAL => {
                let mut terminal = Terminal::new();
                terminal.service_id = self.get_option(self.get_key_terminal_service_id());
                lr.set_terminal(terminal);
            }
            _ => {}
        }

        let mut msg_out = Message::new();
        msg_out.set_login_request(lr);
        msg_out
    }

    pub fn update_supported_decodings(&self) -> Message {
        let decoding = scrap::codec::Decoder::supported_decodings(
            Some(&self.id),
            use_texture_render(),
            self.adapter_luid,
            &self.mark_unsupported,
        );
        let mut misc = Misc::new();
        misc.set_option(OptionMessage {
            supported_decoding: hbb_common::protobuf::MessageField::some(decoding),
            ..Default::default()
        });
        let mut msg_out = Message::new();
        msg_out.set_misc(misc);
        msg_out
    }

    pub fn restart_remote_device(&self) -> Message {
        let mut misc = Misc::new();
        misc.set_restart_remote_device(true);
        let mut msg_out = Message::new();
        msg_out.set_misc(misc);
        msg_out
    }

    pub fn mark_restarting_remote_device(&mut self) {
        self.restarting_remote_device = true;
        self.restart_remote_device_at = Some(Instant::now());
    }

    pub fn clear_restarting_remote_device(&mut self) {
        self.restarting_remote_device = false;
        self.restart_remote_device_at = None;
    }

    pub fn is_restarting_remote_device(&self) -> bool {
        if !self.restarting_remote_device {
            return false;
        }
        // Keep this flag alive for a short grace window instead of clearing it on
        // connection_ready or the first peer bytes. During OS restart the peer can
        // briefly reconnect before the real reboot disconnect, and clearing it too
        // early would let the next disconnect escape the restart flow and fall back
        // to the normal error dialog / manual reconnect path.
        self.restart_remote_device_at
            .map(|started_at| started_at.elapsed() < RESTART_REMOTE_DEVICE_GRACE)
            .unwrap_or(false)
    }

    fn set_auth_retry_after(&mut self, seconds: u32) {
        self.auth_retry_until =
            (seconds > 0).then(|| Instant::now() + Duration::from_secs(seconds.into()));
    }

    fn auth_retry_remaining(&self) -> Option<Duration> {
        self.auth_retry_until
            .and_then(|until| until.checked_duration_since(Instant::now()))
    }

    pub fn get_id(&self) -> &str {
        &self.id
    }

    pub fn get_key_terminal_service_id(&self) -> &'static str {
        if self.is_terminal_admin {
            "terminal-admin-service-id"
        } else {
            "terminal-service-id"
        }
    }
}

/// Media data.
pub enum MediaData {
    VideoQueue,
    VideoFrame(Box<VideoFrame>),
    AudioFrame(Box<AudioFrame>),
    AudioFormat(AudioFormat),
    Reset,
    RecordScreen(bool),
}

pub type MediaSender = mpsc::Sender<MediaData>;

/// Start video thread.
///
/// # Arguments
///
/// * `video_callback` - The callback for video frame. Being called when a video frame is ready.
pub fn start_video_thread<F, T>(
    session: Session<T>,
    display: usize,
    video_receiver: mpsc::Receiver<MediaData>,
    video_queue: Arc<RwLock<ArrayQueue<VideoFrame>>>,
    fps: Arc<RwLock<Option<usize>>>,
    chroma: Arc<RwLock<Option<Chroma>>>,
    discard_queue: Arc<RwLock<bool>>,
    video_callback: F,
) where
    F: 'static + FnMut(usize, &mut scrap::ImageRgb, *mut c_void, bool) + Send,
    T: InvokeUiSession,
{
    let mut video_callback = video_callback;
    let mut last_chroma = None;
    let is_view_camera = session.is_view_camera();

    std::thread::spawn(move || {
        #[cfg(windows)]
        sync_cpu_usage();
        get_hwcodec_config();
        let mut video_handler = None;
        let mut count = 0;
        let mut duration = std::time::Duration::ZERO;
        let mut skip_beginning = 0;
        loop {
            if let Ok(data) = video_receiver.recv() {
                match data {
                    MediaData::VideoFrame(_) | MediaData::VideoQueue => {
                        let vf = match data {
                            MediaData::VideoFrame(vf) => {
                                *discard_queue.write().unwrap() = false;
                                *vf
                            }
                            MediaData::VideoQueue => {
                                if let Some(vf) = video_queue.read().unwrap().pop() {
                                    if discard_queue.read().unwrap().clone() {
                                        continue;
                                    }
                                    vf
                                } else {
                                    continue;
                                }
                            }
                            _ => {
                                // unreachable!();
                                continue;
                            }
                        };
                        let display = vf.display as usize;
                        let start = std::time::Instant::now();
                        let format = CodecFormat::from(&vf);
                        if video_handler.is_none() {
                            let mut handler = VideoHandler::new(format, display);
                            let record_state = session.lc.read().unwrap().record_state;
                            let record_permission = session.lc.read().unwrap().record_permission;
                            let id = session.lc.read().unwrap().id.clone();
                            if record_state && record_permission {
                                handler.record_screen(true, id, display, is_view_camera);
                            }
                            video_handler = Some(handler);
                        }
                        if let Some(handler) = video_handler.as_mut() {
                            let mut pixelbuffer = true;
                            let mut tmp_chroma = None;
                            let format_changed = handler.decoder.format() != format;
                            match handler.handle_frame(vf, &mut pixelbuffer, &mut tmp_chroma) {
                                Ok(true) => {
                                    video_callback(
                                        display,
                                        &mut handler.rgb,
                                        handler.texture.texture,
                                        pixelbuffer,
                                    );

                                    // chroma
                                    if tmp_chroma.is_some() && last_chroma != tmp_chroma {
                                        last_chroma = tmp_chroma;
                                        *chroma.write().unwrap() = tmp_chroma;
                                    }

                                    // fps calculation
                                    fps_calculate(
                                        &mut skip_beginning,
                                        &fps,
                                        format_changed,
                                        start.elapsed(),
                                        &mut count,
                                        &mut duration,
                                    );
                                }
                                Err(e) => {
                                    // This is a simple workaround.
                                    //
                                    // I only see the following error:
                                    // FailedCall("errcode=1 scrap::common::vpxcodec:libs\\scrap\\src\\common\\vpxcodec.rs:433:9")
                                    // When switching from all displays to one display, the error occurs.
                                    // eg:
                                    // 1. Connect to a device with two displays (A and B).
                                    // 2. Switch to display A. The error occurs.
                                    // 3. If the error does not occur. Switch from A to display B. The error occurs.
                                    //
                                    // to-do: fix the error
                                    log::error!("handle video frame error, {}", e);
                                    session.refresh_video(display as _);
                                }
                                _ => {}
                            }
                        }

                        // check invalid decoders
                        let mut should_update_supported = false;
                        if let Some(handler) = video_handler.as_mut() {
                            if !handler.decoder.valid()
                                || handler.fail_counter >= MAX_DECODE_FAIL_COUNTER
                            {
                                let mut lc = session.lc.write().unwrap();
                                let format = handler.decoder.format();
                                if !lc.mark_unsupported.contains(&format) {
                                    lc.mark_unsupported.push(format);
                                    should_update_supported = true;
                                    log::info!("mark {format:?} decoder as unsupported, valid:{}, fail_counter:{}, all unsupported:{:?}", handler.decoder.valid(), handler.fail_counter, lc.mark_unsupported);
                                }
                            }
                        }
                        if should_update_supported {
                            session.send(Data::Message(
                                session.lc.read().unwrap().update_supported_decodings(),
                            ));
                        }
                    }
                    MediaData::Reset => {
                        if let Some(handler) = video_handler.as_mut() {
                            handler.reset(None);
                        }
                    }
                    MediaData::RecordScreen(start) => {
                        let id = session.lc.read().unwrap().id.clone();
                        if let Some(handler) = video_handler.as_mut() {
                            handler.record_screen(start, id, display, is_view_camera);
                        }
                    }
                    _ => {}
                }
            } else {
                break;
            }
        }
        log::info!("Video decoder loop exits");
    });
}

/// Start an audio thread
/// Return a audio [`MediaSender`]
pub fn start_audio_thread() -> MediaSender {
    let (audio_sender, audio_receiver) = mpsc::channel::<MediaData>();
    std::thread::spawn(move || {
        let mut audio_handler = AudioHandler::default();
        loop {
            if let Ok(data) = audio_receiver.recv() {
                match data {
                    MediaData::AudioFrame(af) => {
                        audio_handler.handle_frame(*af);
                    }
                    MediaData::AudioFormat(f) => {
                        log::debug!("recved audio format, sample rate={}", f.sample_rate);
                        audio_handler.handle_format(f);
                    }
                    _ => {}
                }
            } else {
                break;
            }
        }
        log::info!("Audio decoder loop exits");
    });
    audio_sender
}

#[inline]
fn fps_calculate(
    skip_beginning: &mut usize,
    fps: &Arc<RwLock<Option<usize>>>,
    format_changed: bool,
    elapsed: std::time::Duration,
    count: &mut usize,
    duration: &mut std::time::Duration,
) {
    if format_changed {
        *count = 0;
        *duration = std::time::Duration::ZERO;
        *skip_beginning = 0;
    }
    // // The first frame will be very slow
    if *skip_beginning < 3 {
        *skip_beginning += 1;
        return;
    }
    *duration += elapsed;
    *count += 1;
    let ms = duration.as_millis();
    if *count % 10 == 0 && ms > 0 {
        *fps.write().unwrap() = Some((*count as usize) * 1000 / (ms as usize));
    }
    // Clear to get real-time fps
    if *count >= 30 {
        *count = 0;
        *duration = Duration::ZERO;
    }
}

fn get_hwcodec_config() {
    // for sciter and unilink
    #[cfg(feature = "hwcodec")]
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        use std::sync::Once;
        static ONCE: Once = Once::new();
        ONCE.call_once(|| {
            let start = std::time::Instant::now();
            if let Err(e) = crate::ipc::get_hwcodec_config_from_server() {
                log::error!(
                    "Failed to get hwcodec config: {e:?}, elapsed: {:?}",
                    start.elapsed()
                );
            } else {
                log::info!("{:?} used to get hwcodec config", start.elapsed());
            }
        });
    }
}

#[cfg(windows)]
fn sync_cpu_usage() {
    use std::sync::Once;
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let t = std::thread::spawn(do_sync_cpu_usage);
        t.join().ok();
    });
}

#[cfg(windows)]
#[tokio::main(flavor = "current_thread")]
async fn do_sync_cpu_usage() {
    use crate::ipc::{connect, Data};
    let start = std::time::Instant::now();
    match connect(50, "").await {
        Ok(mut conn) => {
            if conn.send(&&Data::SyncWinCpuUsage(None)).await.is_ok() {
                if let Ok(Some(data)) = conn.next_timeout(50).await {
                    match data {
                        Data::SyncWinCpuUsage(cpu_usage) => {
                            hbb_common::platform::windows::sync_cpu_usage(cpu_usage);
                        }
                        _ => {}
                    }
                }
            }
        }
        _ => {}
    }
    log::info!("{:?} used to sync cpu usage", start.elapsed());
}

/// Handle latency test.
///
/// # Arguments
///
/// * `t` - The latency test message.
/// * `peer` - The peer.
pub async fn handle_test_delay(t: TestDelay, peer: &mut Stream) {
    if !t.from_client {
        let mut msg_out = Message::new();
        msg_out.set_test_delay(t);
        allow_err!(peer.send(&msg_out).await);
    }
}

/// Whether is track pad scrolling.
#[inline]
#[cfg(all(target_os = "macos", not(feature = "flutter")))]
fn check_scroll_on_mac(mask: i32, x: i32, y: i32) -> bool {
    // flutter version we set mask type bit to 4 when track pad scrolling.
    if mask & 7 == crate::input::MOUSE_TYPE_TRACKPAD {
        return true;
    }
    if mask & 3 != crate::input::MOUSE_TYPE_WHEEL {
        return false;
    }
    let btn = mask >> 3;
    if y == -1 {
        btn != 0xff88 && btn != -0x780000
    } else if y == 1 {
        btn != 0x78 && btn != 0x780000
    } else if x != 0 {
        // No mouse support horizontal scrolling.
        true
    } else {
        false
    }
}

/// Send mouse data.
///
/// # Arguments
///
/// * `mask` - Mouse event.
///     * mask = buttons << 3 | type
///     * type, 1: down, 2: up, 3: wheel, 4: trackpad
///     * buttons, 1: left, 2: right, 4: middle
/// * `x` - X coordinate.
/// * `y` - Y coordinate.
/// * `alt` - Whether the alt key is pressed.
/// * `ctrl` - Whether the ctrl key is pressed.
/// * `shift` - Whether the shift key is pressed.
/// * `command` - Whether the command key is pressed.
/// * `interface` - The interface for sending data.
#[inline]
pub fn send_mouse(
    mask: i32,
    x: i32,
    y: i32,
    alt: bool,
    ctrl: bool,
    shift: bool,
    command: bool,
    interface: &impl Interface,
) {
    let mut msg_out = Message::new();
    let mut mouse_event = MouseEvent {
        mask,
        x,
        y,
        ..Default::default()
    };
    if alt {
        mouse_event.modifiers.push(ControlKey::Alt.into());
    }
    if shift {
        mouse_event.modifiers.push(ControlKey::Shift.into());
    }
    if ctrl {
        mouse_event.modifiers.push(ControlKey::Control.into());
    }
    if command {
        mouse_event.modifiers.push(ControlKey::Meta.into());
    }
    #[cfg(all(target_os = "macos", not(feature = "flutter")))]
    if check_scroll_on_mac(mask, x, y) {
        let factor = 3;
        mouse_event.mask = crate::input::MOUSE_TYPE_TRACKPAD;
        mouse_event.x *= factor;
        mouse_event.y *= factor;
    }
    interface.swap_modifier_mouse(&mut mouse_event);
    msg_out.set_mouse_event(mouse_event);
    interface.send(Data::Message(msg_out));
}

#[inline]
pub fn send_pointer_device_event(
    mut evt: PointerDeviceEvent,
    alt: bool,
    ctrl: bool,
    shift: bool,
    command: bool,
    interface: &impl Interface,
) {
    let mut msg_out = Message::new();
    if alt {
        evt.modifiers.push(ControlKey::Alt.into());
    }
    if shift {
        evt.modifiers.push(ControlKey::Shift.into());
    }
    if ctrl {
        evt.modifiers.push(ControlKey::Control.into());
    }
    if command {
        evt.modifiers.push(ControlKey::Meta.into());
    }
    msg_out.set_pointer_device_event(evt);
    interface.send(Data::Message(msg_out));
}

/// Activate OS by sending mouse movement.
///
/// # Arguments
///
/// * `interface` - The interface for sending data.
/// * `send_left_click` - Whether to send a click event.
fn activate_os(interface: &impl Interface, send_left_click: bool) {
    let left_down = MOUSE_BUTTON_LEFT << 3 | MOUSE_TYPE_DOWN;
    let left_up = MOUSE_BUTTON_LEFT << 3 | MOUSE_TYPE_UP;
    let right_down = MOUSE_BUTTON_RIGHT << 3 | MOUSE_TYPE_DOWN;
    let right_up = MOUSE_BUTTON_RIGHT << 3 | MOUSE_TYPE_UP;
    send_mouse(left_up, 0, 0, false, false, false, false, interface);
    std::thread::sleep(Duration::from_millis(50));
    send_mouse(0, 0, 0, false, false, false, false, interface);
    std::thread::sleep(Duration::from_millis(50));
    send_mouse(0, 3, 3, false, false, false, false, interface);
    let (click_down, click_up) = if send_left_click {
        (left_down, left_up)
    } else {
        (right_down, right_up)
    };
    std::thread::sleep(Duration::from_millis(50));
    send_mouse(click_down, 0, 0, false, false, false, false, interface);
    send_mouse(click_up, 0, 0, false, false, false, false, interface);
    /*
    let mut key_event = KeyEvent::new();
    // do not use Esc, which has problem with Linux
    key_event.set_control_key(ControlKey::RightArrow);
    key_event.press = true;
    let mut msg_out = Message::new();
    msg_out.set_key_event(key_event.clone());
    interface.send(Data::Message(msg_out.clone()));
    */
}

/// Input the OS's password.
///
/// # Arguments
///
/// * `p` - The password.
/// * `activate` - Whether to activate OS.
/// * `interface` - The interface for sending data.
pub fn input_os_password(p: String, activate: bool, interface: impl Interface) {
    std::thread::spawn(move || {
        _input_os_password(p, activate, interface);
    });
}

/// Input the OS's password.
///
/// # Arguments
///
/// * `p` - The password.
/// * `activate` - Whether to activate OS.
/// * `interface` - The interface for sending data.
fn _input_os_password(p: String, activate: bool, interface: impl Interface) {
    let input_password = !p.is_empty();
    if activate {
        // Click event is used to bring up the password input box.
        activate_os(&interface, input_password);
        std::thread::sleep(Duration::from_millis(1200));
    }
    if !input_password {
        return;
    }
    let mut key_event = KeyEvent::new();
    key_event.mode = KeyboardMode::Legacy.into();
    key_event.press = true;
    let mut msg_out = Message::new();
    key_event.set_seq(p);
    msg_out.set_key_event(key_event.clone());
    interface.send(Data::Message(msg_out.clone()));
    key_event.set_control_key(ControlKey::Return);
    msg_out.set_key_event(key_event);
    interface.send(Data::Message(msg_out));
}

#[derive(Copy, Clone)]
struct LoginErrorMsgBox {
    msgtype: &'static str,
    title: &'static str,
    text: &'static str,
    link: &'static str,
    try_again: bool,
}

lazy_static::lazy_static! {
    static ref LOGIN_ERROR_MAP: Arc<HashMap<&'static str, LoginErrorMsgBox>> = {
        let map = HashMap::from([(LOGIN_SCREEN_WAYLAND, LoginErrorMsgBox{
            msgtype: "error",
            title: "Login Error",
            text: "Login screen using Wayland is not supported",
            link: "",
            try_again: true,
        }), (LOGIN_MSG_DESKTOP_SESSION_NOT_READY, LoginErrorMsgBox{
            msgtype: "session-login",
            title: "",
            text: "",
            link: "",
            try_again: true,
        }), (LOGIN_MSG_DESKTOP_XSESSION_FAILED, LoginErrorMsgBox{
            msgtype: "session-re-login",
            title: "",
            text: "",
            link: "",
            try_again: true,
        }), (LOGIN_MSG_DESKTOP_SESSION_ANOTHER_USER, LoginErrorMsgBox{
            msgtype: "info-nocancel",
            title: "another_user_login_title_tip",
            text: "another_user_login_text_tip",
            link: "",
            try_again: false,
        }), (LOGIN_MSG_DESKTOP_XORG_NOT_FOUND, LoginErrorMsgBox{
            msgtype: "info-nocancel",
            title: "xorg_not_found_title_tip",
            text: "xorg_not_found_text_tip",
            link: "",
            try_again: true,
        }), (LOGIN_MSG_DESKTOP_NO_DESKTOP, LoginErrorMsgBox{
            msgtype: "info-nocancel",
            title: "no_desktop_title_tip",
            text: "no_desktop_text_tip",
            link: "",
            try_again: true,
        }), (LOGIN_MSG_DESKTOP_SESSION_NOT_READY_PASSWORD_EMPTY, LoginErrorMsgBox{
            msgtype: "session-login-password",
            title: "",
            text: "",
            link: "",
            try_again: true,
        }), (LOGIN_MSG_DESKTOP_SESSION_NOT_READY_PASSWORD_WRONG, LoginErrorMsgBox{
            msgtype: "session-login-re-password",
            title: "",
            text: "",
            link: "",
            try_again: true,
        })]);
        Arc::new(map)
    };
}

/// Handle login error.
/// Return true if the password is wrong, return false if there's an actual error.
pub fn handle_login_error(
    _lc: Arc<RwLock<LoginConfigHandler>>,
    err: &str,
    interface: &impl Interface,
) -> bool {
    if err == LOGIN_MSG_PASSWORD_EMPTY {
        interface.msgbox("input-password", "Password Required", "", "");
        true
    } else if err == LOGIN_MSG_LAN_CREDENTIALS_WRONG {
        interface.msgbox(
            "lan-login-required",
            "Username or password is incorrect",
            "Enter the access username and password configured on the remote device.",
            "",
        );
        true
    } else if err == LOGIN_MSG_PASSWORD_WRONG {
        interface.msgbox("re-input-password", err, "Do you want to enter again?", "");
        true
    } else if LOGIN_ERROR_MAP.contains_key(err) {
        if let Some(msgbox_info) = LOGIN_ERROR_MAP.get(err) {
            interface.msgbox(
                msgbox_info.msgtype,
                msgbox_info.title,
                msgbox_info.text,
                msgbox_info.link,
            );
            msgbox_info.try_again
        } else {
            // unreachable!
            false
        }
    } else {
        if err.contains(SCRAP_X11_REQUIRED) {
            interface.msgbox("error", "Login Error", err, "");
        } else {
            interface.msgbox("error", "Login Error", err, "");
        }
        false
    }
}

pub async fn send_lan_login(
    lc: Arc<RwLock<LoginConfigHandler>>,
    username: String,
    password: Vec<u8>,
    peer: &mut Stream,
) {
    send_lan_login_with_os_login(lc, username, password, String::new(), String::new(), peer).await;
}

pub async fn send_lan_login_with_os_login(
    lc: Arc<RwLock<LoginConfigHandler>>,
    username: String,
    mut password: Vec<u8>,
    os_username: String,
    os_password: String,
    peer: &mut Stream,
) {
    let username = match hbb_common::lan::validate_username(&username) {
        Ok(value) => value,
        Err(_) => {
            password.zeroize();
            return;
        }
    };
    if hbb_common::lan::validate_password(&password).is_err() {
        password.zeroize();
        return;
    }
    let mut request = lc
        .read()
        .unwrap()
        .create_login_msg(os_username, os_password, Vec::new())
        .login_request()
        .clone();
    request.username.clear();
    request.password.clear();
    request.lan_login = MessageField::some(LanLoginRequest {
        access_username: username,
        access_password: Bytes::copy_from_slice(&password),
        credential_revision_hint: 0,
        ..Default::default()
    });
    request.my_id = crate::lan_protocol::fingerprint(&Config::get_key_pair().1);
    let mut message = Message::new();
    message.set_login_request(request);
    let result = peer.send(&message).await;
    password.zeroize();
    scrub_lan_password(&mut message);
    if let Err(err) = result {
        log::debug!("Failed to send LAN login request: {err}");
    }
}

fn scrub_lan_password(message: &mut Message) {
    let Some(message::Union::LoginRequest(request)) = message.union.as_mut() else {
        return;
    };
    let Some(login) = request.lan_login.as_mut() else {
        return;
    };
    let bytes = std::mem::take(&mut login.access_password);
    if let Ok(mut bytes) = bytes.try_into_mut() {
        bytes.as_mut().zeroize();
    }
}

/// Handle login request made from ui.
///
/// # Arguments
///
/// * `lc` - Login config.
/// * `os_username` - OS username.
/// * `os_password` - OS password.
/// * `password` - Password.
/// * `remember` - Whether to remember password.
/// * `peer` - [`Stream`] for communicating with peer.
pub async fn handle_login_from_ui(
    lc: Arc<RwLock<LoginConfigHandler>>,
    os_username: String,
    os_password: String,
    _password: String,
    remember: bool,
    access_username: String,
    access_password: Vec<u8>,
    peer: &mut Stream,
) {
    let _ = remember;
    send_lan_login_with_os_login(
        lc,
        access_username,
        access_password,
        os_username,
        os_password,
        peer,
    )
    .await;
}

/// Interface for client to send data and commands.
#[async_trait]
pub trait Interface: Send + Clone + 'static + Sized {
    /// Send message data to remote peer.
    fn send(&self, data: Data);
    fn msgbox(&self, msgtype: &str, title: &str, text: &str, link: &str);
    fn handle_login_error(&self, err: &str) -> bool;
    fn handle_peer_info(&self, pi: PeerInfo);
    fn set_multiple_windows_session(&self, sessions: Vec<WindowsSession>);
    fn on_error(&self, err: &str) {
        self.msgbox("error", "Error", err, "");
    }
    async fn send_initial_lan_login(&self, peer: &mut Stream);
    async fn handle_login_from_ui(
        &self,
        os_username: String,
        os_password: String,
        password: String,
        remember: bool,
        peer: &mut Stream,
    );
    async fn handle_test_delay(&self, t: TestDelay, peer: &mut Stream);

    fn get_lch(&self) -> Arc<RwLock<LoginConfigHandler>>;

    fn get_id(&self) -> String {
        self.get_lch().read().unwrap().id.clone()
    }

    fn swap_modifier_mouse(&self, _msg: &mut hbb_common::protos::message::MouseEvent) {}

    fn update_direct(&self, direct: Option<bool>) {
        self.get_lch().write().unwrap().direct = direct;
    }

    fn update_received(&self, received: bool) {
        self.get_lch().write().unwrap().received = received;
    }

    fn set_auth_retry_after(&self, seconds: u32) {
        self.get_lch()
            .write()
            .unwrap()
            .set_auth_retry_after(seconds);
    }

    fn on_establish_connection_error(&self, err: String) {
        let title = "Connection Error";
        let text = err.to_string();
        let lch = self.get_lch();
        let is_restarting = {
            let lc = lch.read().unwrap();
            lc.is_restarting_remote_device()
        };
        if is_restarting {
            log::info!("Restart remote device, suppress connection error: {err}");
            // Flutter treats this as a reconnect control event. The text is kept
            // for legacy UI and existing translation reuse.
            self.msgbox(
                "restarting",
                "Restarting remote device",
                "Connection in progress. Please wait.",
                "",
            );
            return;
        }

        let errno = errno::errno().0;
        log::error!("Connection closed: {err}({errno})");
        self.msgbox("error", title, &text, "");
    }
}

/// Data used by the client interface.
#[derive(Clone)]
pub enum Data {
    Close,
    RejectLanDevice,
    SubmitLanCredentials,
    Login((String, String, String, bool)),
    Message(Message),
    SendFiles((i32, JobType, String, String, i32, bool, bool)),
    RemoveDirAll((i32, String, bool, bool)),
    ConfirmDeleteFiles((i32, i32)),
    SetNoConfirm(i32),
    RemoveDir((i32, String)),
    RemoveFile((i32, String, i32, bool)),
    CreateDir((i32, String, bool)),
    CancelJob(i32),
    RemovePortForward(i32),
    AddPortForward((i32, String, i32)),
    #[cfg(all(target_os = "windows", not(feature = "flutter")))]
    ToggleClipboardFile,
    NewRDP,
    SetConfirmOverrideFile((i32, i32, bool, bool, bool)),
    AddJob((i32, JobType, String, String, i32, bool, bool)),
    ResumeJob((i32, bool)),
    RecordScreen(bool),
    ElevateDirect,
    ElevateWithLogon(String, String),
    NewVoiceCall,
    CloseVoiceCall,
    TrustLanDevice,
    ResetDecoder(Option<usize>),
    RenameFile((i32, String, String, bool)),
    TakeScreenshot((i32, String)),
}

pub async fn confirm_lan_device(
    interface: &impl Interface,
    receiver: &mut UnboundedReceiver<Data>,
    endpoint: &str,
    device_public_key: &[u8],
) -> bool {
    let endpoint = match hbb_common::lan::Endpoint::parse(endpoint) {
        Ok(value) => value,
        Err(err) => {
            log::error!("Invalid LAN endpoint during trust check: {err}");
            return false;
        }
    };
    let fingerprint = crate::lan_protocol::fingerprint(device_public_key);
    let trusted = Config::get_trusted_lan_fingerprint(endpoint.authority());
    if trusted.as_deref() == Some(fingerprint.as_str()) {
        return true;
    }
    if trusted.is_none() && Config::is_trusted_lan_fingerprint(&fingerprint) {
        if let Err(err) = Config::trust_lan_fingerprint(endpoint.authority(), &fingerprint) {
            log::error!("Failed to update the trusted endpoint for a known LAN device: {err}");
            return false;
        }
        return true;
    }
    let (kind, title, text) = if let Some(expected) = trusted {
        (
            "lan-device-key-changed",
            "Device identity changed",
            format!(
                "The saved fingerprint for {} was {}. The device now presents {}. Continue only if you verified the change on the remote device.",
                endpoint, expected, fingerprint
            ),
        )
    } else {
        (
            "lan-device-first-use",
            "Confirm device identity",
            format!(
                "First connection to {}. Verify this fingerprint on the remote device before continuing: {}",
                endpoint, fingerprint
            ),
        )
    };
    interface.msgbox(kind, title, &text, "");
    while let Some(data) = receiver.recv().await {
        match data {
            Data::TrustLanDevice => {
                if let Err(err) = Config::trust_lan_fingerprint(endpoint.authority(), &fingerprint)
                {
                    log::error!("Failed to save LAN device fingerprint: {err}");
                    return false;
                }
                return true;
            }
            Data::RejectLanDevice | Data::Close => return false,
            _ => {}
        }
    }
    false
}

/// Keycode for key events.
#[derive(Clone, Debug)]
pub enum Key {
    ControlKey(ControlKey),
    Chr(u32),
    _Raw(u32),
}

lazy_static::lazy_static! {
    pub static ref KEY_MAP: HashMap<&'static str, Key> =
    [
        ("VK_A", Key::Chr('a' as _)),
        ("VK_B", Key::Chr('b' as _)),
        ("VK_C", Key::Chr('c' as _)),
        ("VK_D", Key::Chr('d' as _)),
        ("VK_E", Key::Chr('e' as _)),
        ("VK_F", Key::Chr('f' as _)),
        ("VK_G", Key::Chr('g' as _)),
        ("VK_H", Key::Chr('h' as _)),
        ("VK_I", Key::Chr('i' as _)),
        ("VK_J", Key::Chr('j' as _)),
        ("VK_K", Key::Chr('k' as _)),
        ("VK_L", Key::Chr('l' as _)),
        ("VK_M", Key::Chr('m' as _)),
        ("VK_N", Key::Chr('n' as _)),
        ("VK_O", Key::Chr('o' as _)),
        ("VK_P", Key::Chr('p' as _)),
        ("VK_Q", Key::Chr('q' as _)),
        ("VK_R", Key::Chr('r' as _)),
        ("VK_S", Key::Chr('s' as _)),
        ("VK_T", Key::Chr('t' as _)),
        ("VK_U", Key::Chr('u' as _)),
        ("VK_V", Key::Chr('v' as _)),
        ("VK_W", Key::Chr('w' as _)),
        ("VK_X", Key::Chr('x' as _)),
        ("VK_Y", Key::Chr('y' as _)),
        ("VK_Z", Key::Chr('z' as _)),
        ("VK_0", Key::Chr('0' as _)),
        ("VK_1", Key::Chr('1' as _)),
        ("VK_2", Key::Chr('2' as _)),
        ("VK_3", Key::Chr('3' as _)),
        ("VK_4", Key::Chr('4' as _)),
        ("VK_5", Key::Chr('5' as _)),
        ("VK_6", Key::Chr('6' as _)),
        ("VK_7", Key::Chr('7' as _)),
        ("VK_8", Key::Chr('8' as _)),
        ("VK_9", Key::Chr('9' as _)),
        ("VK_COMMA", Key::Chr(',' as _)),
        ("VK_SLASH", Key::Chr('/' as _)),
        ("VK_SEMICOLON", Key::Chr(';' as _)),
        ("VK_QUOTE", Key::Chr('\'' as _)),
        ("VK_LBRACKET", Key::Chr('[' as _)),
        ("VK_RBRACKET", Key::Chr(']' as _)),
        ("VK_BACKSLASH", Key::Chr('\\' as _)),
        ("VK_MINUS", Key::Chr('-' as _)),
        ("VK_PLUS", Key::Chr('=' as _)), // it is =, but sciter return VK_PLUS
        ("VK_DIVIDE", Key::ControlKey(ControlKey::Divide)), // numpad
        ("VK_MULTIPLY", Key::ControlKey(ControlKey::Multiply)), // numpad
        ("VK_SUBTRACT", Key::ControlKey(ControlKey::Subtract)), // numpad
        ("VK_ADD", Key::ControlKey(ControlKey::Add)), // numpad
        ("VK_DECIMAL", Key::ControlKey(ControlKey::Decimal)), // numpad
        ("VK_F1", Key::ControlKey(ControlKey::F1)),
        ("VK_F2", Key::ControlKey(ControlKey::F2)),
        ("VK_F3", Key::ControlKey(ControlKey::F3)),
        ("VK_F4", Key::ControlKey(ControlKey::F4)),
        ("VK_F5", Key::ControlKey(ControlKey::F5)),
        ("VK_F6", Key::ControlKey(ControlKey::F6)),
        ("VK_F7", Key::ControlKey(ControlKey::F7)),
        ("VK_F8", Key::ControlKey(ControlKey::F8)),
        ("VK_F9", Key::ControlKey(ControlKey::F9)),
        ("VK_F10", Key::ControlKey(ControlKey::F10)),
        ("VK_F11", Key::ControlKey(ControlKey::F11)),
        ("VK_F12", Key::ControlKey(ControlKey::F12)),
        ("VK_ENTER", Key::ControlKey(ControlKey::Return)),
        ("VK_CANCEL", Key::ControlKey(ControlKey::Cancel)),
        ("VK_BACK", Key::ControlKey(ControlKey::Backspace)),
        ("VK_TAB", Key::ControlKey(ControlKey::Tab)),
        ("VK_CLEAR", Key::ControlKey(ControlKey::Clear)),
        ("VK_RETURN", Key::ControlKey(ControlKey::Return)),
        ("VK_SHIFT", Key::ControlKey(ControlKey::Shift)),
        ("VK_CONTROL", Key::ControlKey(ControlKey::Control)),
        ("VK_MENU", Key::ControlKey(ControlKey::Alt)),
        ("VK_PAUSE", Key::ControlKey(ControlKey::Pause)),
        ("VK_CAPITAL", Key::ControlKey(ControlKey::CapsLock)),
        ("VK_KANA", Key::ControlKey(ControlKey::Kana)),
        ("VK_HANGUL", Key::ControlKey(ControlKey::Hangul)),
        ("VK_JUNJA", Key::ControlKey(ControlKey::Junja)),
        ("VK_FINAL", Key::ControlKey(ControlKey::Final)),
        ("VK_HANJA", Key::ControlKey(ControlKey::Hanja)),
        ("VK_KANJI", Key::ControlKey(ControlKey::Kanji)),
        ("VK_ESCAPE", Key::ControlKey(ControlKey::Escape)),
        ("VK_CONVERT", Key::ControlKey(ControlKey::Convert)),
        ("VK_SPACE", Key::ControlKey(ControlKey::Space)),
        ("VK_PRIOR", Key::ControlKey(ControlKey::PageUp)),
        ("VK_NEXT", Key::ControlKey(ControlKey::PageDown)),
        ("VK_END", Key::ControlKey(ControlKey::End)),
        ("VK_HOME", Key::ControlKey(ControlKey::Home)),
        ("VK_LEFT", Key::ControlKey(ControlKey::LeftArrow)),
        ("VK_UP", Key::ControlKey(ControlKey::UpArrow)),
        ("VK_RIGHT", Key::ControlKey(ControlKey::RightArrow)),
        ("VK_DOWN", Key::ControlKey(ControlKey::DownArrow)),
        ("VK_SELECT", Key::ControlKey(ControlKey::Select)),
        ("VK_PRINT", Key::ControlKey(ControlKey::Print)),
        ("VK_EXECUTE", Key::ControlKey(ControlKey::Execute)),
        ("VK_SNAPSHOT", Key::ControlKey(ControlKey::Snapshot)),
        ("VK_SCROLL", Key::ControlKey(ControlKey::Scroll)),
        ("VK_INSERT", Key::ControlKey(ControlKey::Insert)),
        ("VK_DELETE", Key::ControlKey(ControlKey::Delete)),
        ("VK_HELP", Key::ControlKey(ControlKey::Help)),
        ("VK_SLEEP", Key::ControlKey(ControlKey::Sleep)),
        ("VK_SEPARATOR", Key::ControlKey(ControlKey::Separator)),
        ("VK_NUMPAD0", Key::ControlKey(ControlKey::Numpad0)),
        ("VK_NUMPAD1", Key::ControlKey(ControlKey::Numpad1)),
        ("VK_NUMPAD2", Key::ControlKey(ControlKey::Numpad2)),
        ("VK_NUMPAD3", Key::ControlKey(ControlKey::Numpad3)),
        ("VK_NUMPAD4", Key::ControlKey(ControlKey::Numpad4)),
        ("VK_NUMPAD5", Key::ControlKey(ControlKey::Numpad5)),
        ("VK_NUMPAD6", Key::ControlKey(ControlKey::Numpad6)),
        ("VK_NUMPAD7", Key::ControlKey(ControlKey::Numpad7)),
        ("VK_NUMPAD8", Key::ControlKey(ControlKey::Numpad8)),
        ("VK_NUMPAD9", Key::ControlKey(ControlKey::Numpad9)),
        ("Apps", Key::ControlKey(ControlKey::Apps)),
        ("Meta", Key::ControlKey(ControlKey::Meta)),
        ("RAlt", Key::ControlKey(ControlKey::RAlt)),
        ("RWin", Key::ControlKey(ControlKey::RWin)),
        ("RControl", Key::ControlKey(ControlKey::RControl)),
        ("RShift", Key::ControlKey(ControlKey::RShift)),
        ("CTRL_ALT_DEL", Key::ControlKey(ControlKey::CtrlAltDel)),
        ("LOCK_SCREEN", Key::ControlKey(ControlKey::LockScreen)),
    ].iter().cloned().collect();
}

/// Check if the given message is an error and can be retried.
///
/// # Arguments
///
/// * `msgtype` - The message type.
/// * `title` - The title of the message.
/// * `text` - The text of the message.
#[inline]
pub fn check_if_retry(msgtype: &str, title: &str, text: &str) -> bool {
    msgtype == "error"
        && title == "Connection Error"
        && (!text.to_lowercase().contains("offline")
            && !text.to_lowercase().contains("not exist")
            && !text.to_lowercase().contains("handshake")
            && !text.to_lowercase().contains("failed")
            && !text.to_lowercase().contains("resolve")
            && !text.to_lowercase().contains("mismatch")
            && !text.to_lowercase().contains("manually")
            && !text.to_lowercase().contains("restricted")
            && !text.to_lowercase().contains("not allowed"))
}
