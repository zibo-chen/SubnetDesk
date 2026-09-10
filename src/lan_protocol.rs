use base::message_proto::{message, LanClientHello, LanServerHello, Message, PublicKey, WebrtcIce};
use bytes::Bytes;
use hbb_common::{
    anyhow::{anyhow, bail},
    config::{Config, CONNECT_TIMEOUT, READ_TIMEOUT},
    lan::{NONCE_LEN, PROTOCOL_VERSION},
    log,
    protobuf::Message as _,
    sodiumoxide::{
        crypto::{box_, secretbox, sign},
        randombytes,
    },
    tcp,
    timeout,
    tokio::{
        self,
        sync::mpsc::UnboundedReceiver,
        time::{Duration, Instant},
    },
    webrtc::WebRTCStream,
    ResultType, Stream,
};
use std::collections::VecDeque;

const TRANSCRIPT_PREFIX: &[u8] = b"rustdesk-lan-handshake-v1\0";

/// Pre-session transport race: how long to wait for the WebRTC transport to come up before
/// falling back to the TCP transport. Deliberately short of `CONNECT_TIMEOUT` — on a LAN where
/// UDP is blocked the TCP session must not wait out the full connect timeout.
pub const WEBRTC_SETUP_TIMEOUT: Duration = Duration::from_secs(4);

/// Grace given to the WebRTC channel after the secured TCP stream dies during the race: a
/// peer that adopted WebRTC drops that stream, so its close reaches the other side shortly
/// after its own channel-open — which precedes the drop. If the channel is up by the time
/// the stream dies, both sides must land on WebRTC, not on a dead TCP fallback.
const WEBRTC_STREAM_DIE_GRACE: Duration = Duration::from_millis(500);

pub struct LanPeerIdentity {
    pub device_public_key: Vec<u8>,
    pub fingerprint: String,
}

fn require_protocol_version(remote: u32, role: &str) -> ResultType<()> {
    if remote != PROTOCOL_VERSION {
        bail!(
            "LAN protocol version mismatch: {role} {}, peer {}",
            PROTOCOL_VERSION,
            remote
        );
    }
    Ok(())
}

fn transcript(
    client_nonce: &[u8],
    server_nonce: &[u8],
    ephemeral_public_key: &[u8],
    webrtc_sdp_answer: &str,
) -> ResultType<Vec<u8>> {
    if client_nonce.len() != NONCE_LEN || server_nonce.len() != NONCE_LEN {
        bail!("Handshake failed: invalid nonce length");
    }
    if ephemeral_public_key.len() != box_::PUBLICKEYBYTES {
        bail!("Handshake failed: invalid ephemeral public key length");
    }
    let mut out =
        Vec::with_capacity(TRANSCRIPT_PREFIX.len() + 4 + NONCE_LEN * 2 + box_::PUBLICKEYBYTES);
    out.extend_from_slice(TRANSCRIPT_PREFIX);
    out.extend_from_slice(&PROTOCOL_VERSION.to_be_bytes());
    out.extend_from_slice(client_nonce);
    out.extend_from_slice(server_nonce);
    out.extend_from_slice(ephemeral_public_key);
    // The SDP answer is bound into the transcript only when present, so peers
    // that do not use WebRTC sign a byte-identical transcript and old/new
    // releases interoperate without a protocol version bump.
    if !webrtc_sdp_answer.is_empty() {
        out.extend_from_slice(webrtc_sdp_answer.as_bytes());
    }
    Ok(out)
}

pub fn fingerprint(device_public_key: &[u8]) -> String {
    hbb_common::lan::device_fingerprint(device_public_key)
}

/// Runs the LAN handshake. `webrtc_sdp_offer` carries the client's WebRTC SDP
/// offer (empty when the client does not want a WebRTC transport). Returns the
/// peer identity, the server's SDP answer (bound into the handshake signature),
/// and the session key, so a WebRTC transport that wins the pre-session race
/// can be secured with the same key as the TCP transport.
pub async fn client_handshake(
    stream: &mut Stream,
    webrtc_sdp_offer: &str,
) -> ResultType<(LanPeerIdentity, String, secretbox::Key)> {
    let client_nonce = randombytes::randombytes(NONCE_LEN);
    let mut hello = Message::new();
    hello.set_lan_client_hello(LanClientHello {
        protocol_version: PROTOCOL_VERSION,
        client_nonce: Bytes::from(client_nonce.clone()),
        client_capabilities: 0,
        webrtc_sdp_offer: webrtc_sdp_offer.to_owned(),
        ..Default::default()
    });
    timeout(CONNECT_TIMEOUT, stream.send(&hello)).await??;

    let bytes = timeout(READ_TIMEOUT, stream.next())
        .await?
        .ok_or_else(|| anyhow!("Handshake failed: server closed the connection"))??;
    let message = Message::parse_from_bytes(&bytes)
        .map_err(|_| anyhow!("Handshake failed: invalid server hello"))?;
    let server_hello = match message.union {
        Some(message::Union::LanServerHello(value)) => value,
        _ => bail!("Handshake failed: LAN protocol required"),
    };
    require_protocol_version(server_hello.protocol_version, "client")?;
    if server_hello.device_public_key.len() != sign::PUBLICKEYBYTES {
        bail!("Handshake failed: invalid device public key length");
    }
    let mut device_pk = [0u8; sign::PUBLICKEYBYTES];
    device_pk.copy_from_slice(&server_hello.device_public_key);
    let device_pk = sign::PublicKey(device_pk);
    let expected = transcript(
        &client_nonce,
        &server_hello.server_nonce,
        &server_hello.ephemeral_public_key,
        &server_hello.webrtc_sdp_answer,
    )?;
    let signed = sign::verify(&server_hello.signature, &device_pk)
        .map_err(|_| anyhow!("Handshake failed: device signature mismatch"))?;
    if signed != expected {
        bail!("Handshake failed: signed transcript mismatch");
    }

    let mut ephemeral_pk = [0u8; box_::PUBLICKEYBYTES];
    ephemeral_pk.copy_from_slice(&server_hello.ephemeral_public_key);
    let (asymmetric_value, symmetric_value, key) = crate::create_symmetric_key_msg(ephemeral_pk);
    let mut key_message = Message::new();
    key_message.set_public_key(PublicKey {
        asymmetric_value,
        symmetric_value,
        ..Default::default()
    });
    timeout(CONNECT_TIMEOUT, stream.send(&key_message)).await??;
    let session_key = key.clone();
    stream.set_key(key);

    let device_public_key = server_hello.device_public_key.to_vec();
    let webrtc_sdp_answer = server_hello.webrtc_sdp_answer.to_owned();
    Ok((
        LanPeerIdentity {
            fingerprint: fingerprint(&device_public_key),
            device_public_key,
        },
        webrtc_sdp_answer,
        session_key,
    ))
}

/// Runs the server side of the LAN handshake. Returns the WebRTC answerer
/// when the client sent an SDP offer, so the caller can race the WebRTC
/// connection against the TCP transport before the session starts.
pub async fn server_handshake(stream: &mut Stream) -> ResultType<Option<WebRTCStream>> {
    let (secret_key, public_key) = Config::get_key_pair();
    if secret_key.len() != sign::SECRETKEYBYTES || public_key.len() != sign::PUBLICKEYBYTES {
        bail!("Handshake failed: invalid device identity key");
    }
    let mut secret = [0u8; sign::SECRETKEYBYTES];
    secret.copy_from_slice(&secret_key);
    let mut public = [0u8; sign::PUBLICKEYBYTES];
    public.copy_from_slice(&public_key);
    server_handshake_with_identity(stream, &sign::SecretKey(secret), &sign::PublicKey(public)).await
}

async fn server_handshake_with_identity(
    stream: &mut Stream,
    device_secret_key: &sign::SecretKey,
    device_public_key: &sign::PublicKey,
) -> ResultType<Option<WebRTCStream>> {
    let bytes = timeout(READ_TIMEOUT, stream.next())
        .await?
        .ok_or_else(|| anyhow!("Handshake failed: client closed the connection"))??;
    let message = Message::parse_from_bytes(&bytes)
        .map_err(|_| anyhow!("Handshake failed: invalid client hello"))?;
    let client_hello = match message.union {
        Some(message::Union::LanClientHello(value)) => value,
        _ => bail!("Handshake failed: LAN protocol required"),
    };
    require_protocol_version(client_hello.protocol_version, "server")?;
    if client_hello.client_nonce.len() != NONCE_LEN {
        bail!("Handshake failed: invalid client nonce length");
    }

    // Answer the client's WebRTC offer, if any. The answer is bound into the
    // signed transcript below, so the device key authenticates it.
    let mut webrtc: Option<WebRTCStream> = None;
    let mut webrtc_sdp_answer = String::new();
    if !client_hello.webrtc_sdp_offer.is_empty() {
        webrtc = Some(
            WebRTCStream::new(&client_hello.webrtc_sdp_offer, false, CONNECT_TIMEOUT)
                .await?,
        );
        webrtc_sdp_answer = webrtc
            .as_ref()
            .ok_or_else(|| anyhow!("Handshake failed: missing WebRTC answerer"))?
            .local_endpoint()
            .to_owned();
    }

    let (ephemeral_public_key, ephemeral_secret_key) = box_::gen_keypair();
    let server_nonce = randombytes::randombytes(NONCE_LEN);
    let transcript = transcript(
        &client_hello.client_nonce,
        &server_nonce,
        &ephemeral_public_key.0,
        &webrtc_sdp_answer,
    )?;
    let signature = sign::sign(&transcript, device_secret_key);

    let mut server_hello = Message::new();
    server_hello.set_lan_server_hello(LanServerHello {
        protocol_version: PROTOCOL_VERSION,
        server_nonce: Bytes::from(server_nonce),
        device_public_key: Bytes::from(device_public_key.0.to_vec()),
        ephemeral_public_key: Bytes::from(ephemeral_public_key.0.to_vec()),
        signature: Bytes::from(signature),
        webrtc_sdp_answer: webrtc_sdp_answer.clone().into(),
        ..Default::default()
    });
    timeout(CONNECT_TIMEOUT, stream.send(&server_hello)).await??;

    let bytes = timeout(READ_TIMEOUT, stream.next())
        .await?
        .ok_or_else(|| anyhow!("Handshake failed: client closed during key exchange"))??;
    let message = Message::parse_from_bytes(&bytes)
        .map_err(|_| anyhow!("Handshake failed: invalid client key message"))?;
    let client_key = match message.union {
        Some(message::Union::PublicKey(value)) => value,
        _ => bail!("Handshake failed: client key message required"),
    };
    let key = tcp::Encrypt::decode(
        &client_key.symmetric_value,
        &client_key.asymmetric_value,
        &ephemeral_secret_key,
    )?;
    stream.set_key(key.clone());
    // Mark the answerer peer-verified too: its DTLS binding was established by the
    // handshake signature over the signed answer, mirroring the TCP key exchange.
    if let Some(webrtc) = webrtc.as_mut() {
        webrtc.set_key(key);
    }
    Ok(webrtc)
}

/// Settles the transport decision once the secured TCP stream is already gone: a peer that
/// adopted WebRTC drops the stream (the winning branch of [`race_webrtc_transport`] does),
/// so a dead stream is not by itself a vote for TCP. Returns whether the WebRTC channel is
/// up now or comes up within [`WEBRTC_STREAM_DIE_GRACE`].
async fn webrtc_up_after_stream_death(webrtc: &mut WebRTCStream) -> bool {
    match webrtc
        .wait_connected(WEBRTC_STREAM_DIE_GRACE.as_millis() as u64)
        .await
    {
        Ok(()) => {
            log::info!("WebRTC transport established after TCP close, using it for the session");
            true
        }
        Err(err) => {
            log::debug!("WebRTC not established after TCP close, using TCP: {err}");
            false
        }
    }
}

/// Pre-session transport race, shared by client and server: while the WebRTC data channel
/// is being set up, the secured TCP stream carries only `WebrtcIce` messages, so this loop
/// owns it. When the channel comes up within [`WEBRTC_SETUP_TIMEOUT`] the peer connection
/// is returned as the session transport; otherwise it is closed and the TCP stream is
/// returned, so the session runs exactly as before. If the TCP stream dies before the
/// decision (a peer that adopted WebRTC drops it), the channel is given
/// [`WEBRTC_STREAM_DIE_GRACE`] before the TCP fallback.
///
/// `local_ice_rx` is the peer connection's local candidate channel, already taken.
/// Candidates are buffered and shuttled between `select!` iterations so that no branch
/// borrows a variable another branch holds.
pub async fn race_webrtc_transport(
    mut stream: Stream,
    mut webrtc: WebRTCStream,
    mut local_ice_rx: UnboundedReceiver<String>,
) -> Stream {
    let ice_session_key = webrtc.session_key().to_owned();
    let deadline = Instant::now() + WEBRTC_SETUP_TIMEOUT;
    let mut pending_remote_candidates: VecDeque<String> = VecDeque::new();
    let mut pending_local_candidates: VecDeque<String> = VecDeque::new();
    let mut outcome: Option<bool> = None;
    // Set inside the select! (which holds `webrtc` across the branches) and settled after
    // the loop, where `webrtc` is free to borrow again.
    let mut stream_died = false;
    loop {
        // Local candidates out, remote candidates in; both run outside the select!, so the
        // stream and the pc are free to borrow.
        while let Some(candidate) = pending_local_candidates.pop_front() {
            let mut message = Message::new();
            message.set_webrtc_ice(WebrtcIce {
                session_key: ice_session_key.clone(),
                candidate,
                ..Default::default()
            });
            let send_failed = match timeout(3_000, stream.send(&message)).await {
                Ok(Ok(())) => false,
                _ => true,
            };
            if send_failed {
                // The peer may have already adopted WebRTC and dropped this stream; settle
                // on the channel state before falling back to a stream that is now dead.
                outcome = Some(webrtc_up_after_stream_death(&mut webrtc).await);
                break;
            }
        }
        if outcome.is_none() {
            while let Some(candidate) = pending_remote_candidates.pop_front() {
                if let Err(err) = webrtc.add_remote_ice_candidate(&candidate).await {
                    log::debug!("Failed to add remote WebRTC ICE candidate: {err}");
                }
            }
            while let Ok(candidate) = local_ice_rx.try_recv() {
                pending_local_candidates.push_back(candidate);
            }
        }
        if outcome.is_some() {
            break;
        }
        let now = Instant::now();
        if now >= deadline {
            log::debug!("WebRTC setup timed out, using TCP");
            break;
        }
        let remaining = (deadline - now).as_millis().max(1) as u64;
        // The short tick cap keeps local candidates flowing even while the peer is silent.
        tokio::select! {
            result = webrtc.wait_connected(remaining) => {
                match result {
                    Ok(()) => {
                        log::info!("WebRTC transport established, using it for the session");
                        outcome = Some(true);
                    }
                    Err(err) => {
                        log::debug!("WebRTC setup failed, using TCP: {err}");
                        outcome = Some(false);
                    }
                }
            }
            maybe_bytes = stream.next() => {
                match maybe_bytes {
                    Some(Ok(bytes)) => {
                        let Ok(message) = Message::parse_from_bytes(&bytes) else {
                            continue;
                        };
                        match message.union {
                            Some(message::Union::WebrtcIce(ice))
                                if ice.session_key == ice_session_key =>
                            {
                                pending_remote_candidates.push_back(ice.candidate);
                            }
                            _ => {
                                log::debug!(
                                    "Ignoring unexpected message during the pre-session ICE window"
                                );
                            }
                        }
                    }
                    _ => {
                        // The secured stream died before the decision. A peer that adopted
                        // WebRTC drops it, so settle on the channel state after the loop
                        // before falling back to a stream that is now dead.
                        stream_died = true;
                        break;
                    }
                }
            }
            _ = tokio::time::sleep(Duration::from_millis(remaining.min(200))) => {}
        }
    }
    if stream_died {
        outcome = Some(webrtc_up_after_stream_death(&mut webrtc).await);
    }
    if outcome == Some(true) {
        return Stream::WebRTC(webrtc);
    }
    webrtc.close_detached();
    stream
}

#[cfg(test)]
mod tests {
    use super::*;
    use base::message_proto::{message, ChatMessage, Misc};
    use hbb_common::tokio::{
        self,
        io::{AsyncReadExt, AsyncWriteExt},
        net::{TcpListener, TcpStream},
    };
    use std::sync::{Arc, Mutex};

    #[test]
    fn transcript_binds_every_handshake_value() {
        let (pk, _) = box_::gen_keypair();
        let first = transcript(&[1; NONCE_LEN], &[2; NONCE_LEN], &pk.0, "").unwrap();
        let second = transcript(&[3; NONCE_LEN], &[2; NONCE_LEN], &pk.0, "").unwrap();
        assert_ne!(first, second);
    }

    #[test]
    fn rejects_malformed_transcript_inputs() {
        assert!(transcript(&[], &[2; NONCE_LEN], &[0; box_::PUBLICKEYBYTES], "").is_err());
        assert!(transcript(&[1; NONCE_LEN], &[2; NONCE_LEN], &[], "").is_err());
    }

    #[test]
    fn signature_rejects_tampered_handshake() {
        let (ephemeral, _) = box_::gen_keypair();
        let (device_pk, device_sk) = sign::gen_keypair();
        let original = transcript(&[1; NONCE_LEN], &[2; NONCE_LEN], &ephemeral.0, "").unwrap();
        let signed = sign::sign(&original, &device_sk);
        let mut tampered = original.clone();
        tampered[TRANSCRIPT_PREFIX.len() + 4] ^= 1;
        assert_eq!(sign::verify(&signed, &device_pk).unwrap(), original);
        assert_ne!(sign::verify(&signed, &device_pk).unwrap(), tampered);
    }

    #[test]
    fn replayed_server_hello_is_bound_to_client_nonce() {
        let (ephemeral, _) = box_::gen_keypair();
        let first = transcript(&[7; NONCE_LEN], &[9; NONCE_LEN], &ephemeral.0, "").unwrap();
        let replay_target = transcript(&[8; NONCE_LEN], &[9; NONCE_LEN], &ephemeral.0, "").unwrap();
        assert_ne!(first, replay_target);
    }

    #[test]
    fn transcript_binds_webrtc_answer_only_when_present() {
        let (pk, _) = box_::gen_keypair();
        let base = transcript(&[1; NONCE_LEN], &[2; NONCE_LEN], &pk.0, "").unwrap();
        // An empty answer leaves the pre-WebRTC transcript bytes untouched, so
        // peers that do not use WebRTC still verify against the old layout.
        assert_eq!(
            base.len(),
            TRANSCRIPT_PREFIX.len() + 4 + NONCE_LEN * 2 + box_::PUBLICKEYBYTES
        );
        let with_answer = transcript(&[1; NONCE_LEN], &[2; NONCE_LEN], &pk.0, "v=0\r\n").unwrap();
        assert_ne!(base, with_answer);
    }

    #[test]
    fn protocol_downgrade_is_rejected() {
        assert!(require_protocol_version(PROTOCOL_VERSION, "client").is_ok());
        assert!(require_protocol_version(PROTOCOL_VERSION.saturating_sub(1), "client").is_err());
        assert!(require_protocol_version(PROTOCOL_VERSION + 1, "server").is_err());
    }

    #[tokio::test]
    async fn loopback_handshake_encrypts_application_payload() {
        let _ = hbb_common::sodiumoxide::init();
        let (device_public_key, device_secret_key) = sign::gen_keypair();
        let server_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let server_addr = server_listener.local_addr().unwrap();
        let proxy_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let proxy_addr = proxy_listener.local_addr().unwrap();
        let captured_client_bytes = Arc::new(Mutex::new(Vec::new()));

        let expected_public_key = device_public_key.0.to_vec();
        let server_task = tokio::spawn(async move {
            let (socket, _) = server_listener.accept().await.unwrap();
            let local_addr = socket.local_addr().unwrap();
            let mut stream = Stream::from(socket, local_addr);
            server_handshake_with_identity(&mut stream, &device_secret_key, &device_public_key)
                .await
                .unwrap();
            assert!(stream.is_secured());
            let bytes = stream.next().await.unwrap().unwrap();
            let message = Message::parse_from_bytes(&bytes).unwrap();
            let Some(message::Union::Misc(misc)) = message.union else {
                panic!("expected encrypted misc message");
            };
            let Some(base::message_proto::misc::Union::ChatMessage(chat)) = misc.union else {
                panic!("expected encrypted chat message");
            };
            chat.text
        });

        let capture = captured_client_bytes.clone();
        let proxy_task = tokio::spawn(async move {
            let (client, _) = proxy_listener.accept().await.unwrap();
            let upstream = TcpStream::connect(server_addr).await.unwrap();
            let (mut client_read, mut client_write) = client.into_split();
            let (mut server_read, mut server_write) = upstream.into_split();
            let to_server = async move {
                let mut buffer = [0u8; 4096];
                loop {
                    let read = client_read.read(&mut buffer).await?;
                    if read == 0 {
                        break;
                    }
                    {
                        capture.lock().unwrap().extend_from_slice(&buffer[..read]);
                    }
                    server_write.write_all(&buffer[..read]).await?;
                }
                server_write.shutdown().await
            };
            let to_client = async move {
                tokio::io::copy(&mut server_read, &mut client_write).await?;
                client_write.shutdown().await
            };
            tokio::try_join!(to_server, to_client)
        });

        let socket = TcpStream::connect(proxy_addr).await.unwrap();
        let local_addr = socket.local_addr().unwrap();
        let mut stream = Stream::from(socket, local_addr);
        let (identity, webrtc_sdp_answer, _key) =
            client_handshake(&mut stream, "").await.unwrap();
        assert!(stream.is_secured());
        assert!(webrtc_sdp_answer.is_empty());
        assert_eq!(identity.device_public_key, expected_public_key);

        let marker = "lan-only-secret-payload-7f79f9";
        let mut misc = Misc::new();
        misc.set_chat_message(ChatMessage {
            text: marker.to_owned(),
            ..Default::default()
        });
        let mut message = Message::new();
        message.set_misc(misc);
        stream.send(&message).await.unwrap();
        drop(stream);

        assert_eq!(server_task.await.unwrap(), marker);
        proxy_task.await.unwrap().unwrap();
        let captured = captured_client_bytes.lock().unwrap();
        assert!(!captured
            .windows(marker.len())
            .any(|window| window == marker.as_bytes()));
    }
}
