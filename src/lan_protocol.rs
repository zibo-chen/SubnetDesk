use bytes::Bytes;
use hbb_common::{
    anyhow::{anyhow, bail},
    config::{Config, CONNECT_TIMEOUT, READ_TIMEOUT},
    lan::{NONCE_LEN, PROTOCOL_VERSION},
    message_proto::{message, LanClientHello, LanServerHello, Message, PublicKey},
    protobuf::Message as _,
    sodiumoxide::{
        crypto::{box_, sign},
        randombytes,
    },
    tcp, timeout, ResultType, Stream,
};

const TRANSCRIPT_PREFIX: &[u8] = b"rustdesk-lan-handshake-v1\0";

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
    Ok(out)
}

pub fn fingerprint(device_public_key: &[u8]) -> String {
    hbb_common::lan::device_fingerprint(device_public_key)
}

pub async fn client_handshake(stream: &mut Stream) -> ResultType<LanPeerIdentity> {
    let client_nonce = randombytes::randombytes(NONCE_LEN);
    let mut hello = Message::new();
    hello.set_lan_client_hello(LanClientHello {
        protocol_version: PROTOCOL_VERSION,
        client_nonce: Bytes::from(client_nonce.clone()),
        client_capabilities: 0,
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
    stream.set_key(key);

    let device_public_key = server_hello.device_public_key.to_vec();
    Ok(LanPeerIdentity {
        fingerprint: fingerprint(&device_public_key),
        device_public_key,
    })
}

pub async fn server_handshake(stream: &mut Stream) -> ResultType<()> {
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
) -> ResultType<()> {
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

    let (ephemeral_public_key, ephemeral_secret_key) = box_::gen_keypair();
    let server_nonce = randombytes::randombytes(NONCE_LEN);
    let transcript = transcript(
        &client_hello.client_nonce,
        &server_nonce,
        &ephemeral_public_key.0,
    )?;
    let signature = sign::sign(&transcript, device_secret_key);

    let mut server_hello = Message::new();
    server_hello.set_lan_server_hello(LanServerHello {
        protocol_version: PROTOCOL_VERSION,
        server_nonce: Bytes::from(server_nonce),
        device_public_key: Bytes::from(device_public_key.0.to_vec()),
        ephemeral_public_key: Bytes::from(ephemeral_public_key.0.to_vec()),
        signature: Bytes::from(signature),
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
    stream.set_key(key);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{
        message_proto::{message, ChatMessage, Misc},
        tokio::{
            self,
            io::{AsyncReadExt, AsyncWriteExt},
            net::{TcpListener, TcpStream},
        },
    };
    use std::sync::{Arc, Mutex};

    #[test]
    fn transcript_binds_every_handshake_value() {
        let (pk, _) = box_::gen_keypair();
        let first = transcript(&[1; NONCE_LEN], &[2; NONCE_LEN], &pk.0).unwrap();
        let second = transcript(&[3; NONCE_LEN], &[2; NONCE_LEN], &pk.0).unwrap();
        assert_ne!(first, second);
    }

    #[test]
    fn rejects_malformed_transcript_inputs() {
        assert!(transcript(&[], &[2; NONCE_LEN], &[0; box_::PUBLICKEYBYTES]).is_err());
        assert!(transcript(&[1; NONCE_LEN], &[2; NONCE_LEN], &[]).is_err());
    }

    #[test]
    fn signature_rejects_tampered_handshake() {
        let (ephemeral, _) = box_::gen_keypair();
        let (device_pk, device_sk) = sign::gen_keypair();
        let original = transcript(&[1; NONCE_LEN], &[2; NONCE_LEN], &ephemeral.0).unwrap();
        let signed = sign::sign(&original, &device_sk);
        let mut tampered = original.clone();
        tampered[TRANSCRIPT_PREFIX.len() + 4] ^= 1;
        assert_eq!(sign::verify(&signed, &device_pk).unwrap(), original);
        assert_ne!(sign::verify(&signed, &device_pk).unwrap(), tampered);
    }

    #[test]
    fn replayed_server_hello_is_bound_to_client_nonce() {
        let (ephemeral, _) = box_::gen_keypair();
        let first = transcript(&[7; NONCE_LEN], &[9; NONCE_LEN], &ephemeral.0).unwrap();
        let replay_target = transcript(&[8; NONCE_LEN], &[9; NONCE_LEN], &ephemeral.0).unwrap();
        assert_ne!(first, replay_target);
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
            let Some(hbb_common::message_proto::misc::Union::ChatMessage(chat)) = misc.union else {
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
        let identity = client_handshake(&mut stream).await.unwrap();
        assert!(stream.is_secured());
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
