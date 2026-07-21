import { expect, test } from "bun:test";
import sodium from "libsodium-wrappers";
import { hash as sha256 } from "fast-sha256";
import { LanCryptoSession } from "../src/crypto";
import { Message } from "../src/generated/message";
import { buildHandshakeTranscript, bytesToHex, nonceForSequence } from "../src/protocol";

test("browser handshake interoperates with libsodium box and secretbox primitives", async () => {
  await sodium.ready;
  const client = await LanCryptoSession.create();
  const device = sodium.crypto_sign_keypair();
  const ephemeral = sodium.crypto_box_keypair();
  const serverNonce = sodium.randombytes_buf(32);
  const transcript = buildHandshakeTranscript(client.clientNonce, serverNonce, ephemeral.publicKey);
  const signature = sodium.crypto_sign(transcript, device.privateKey);

  const accepted = await client.acceptServerHello({
    protocol_version: 1,
    server_nonce: serverNonce,
    device_public_key: device.publicKey,
    ephemeral_public_key: ephemeral.publicKey,
    signature,
  });
  expect(accepted.fingerprint).toBe(bytesToHex(sha256(device.publicKey)));
  expect(client.clientIdentifier()).toMatch(/^web-[0-9a-f]{32}$/);

  const keyMessage = Message.decode(accepted.keyMessage).public_key;
  expect(keyMessage).toBeDefined();
  if (!keyMessage) return;
  const sharedKey = sodium.crypto_box_open_easy(
    keyMessage.symmetric_value,
    new Uint8Array(24),
    keyMessage.asymmetric_value,
    ephemeral.privateKey,
  );
  expect(sharedKey.length).toBe(sodium.crypto_secretbox_KEYBYTES);

  const outbound = client.encrypt(Message.create({ misc: { video_received: true } }));
  const opened = sodium.crypto_secretbox_open_easy(outbound, nonceForSequence(1n), sharedKey);
  expect(Message.decode(opened).misc?.video_received).toBe(true);

  const reply = sodium.crypto_secretbox_easy(
    Message.encode(Message.create({ test_delay: { time: 42n } })).finish(),
    nonceForSequence(1n),
    sharedKey,
  );
  expect(client.decrypt(reply).test_delay?.time).toBe(42n);
});
