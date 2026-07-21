import sodium from "libsodium-wrappers";
import { hash as sha256 } from "fast-sha256";
import { Message, type LanServerHello } from "./generated/message";
import { buildHandshakeTranscript, bytesToHex, nonceForSequence } from "./protocol";

const PROTOCOL_VERSION = 1;
const ZERO_NONCE = new Uint8Array(24);

function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

export class LanCryptoSession {
  readonly clientNonce: Uint8Array;
  private symmetricKey?: Uint8Array;
  private sendSequence = 0n;
  private receiveSequence = 0n;

  private constructor(clientNonce: Uint8Array) {
    this.clientNonce = clientNonce;
  }

  static async create(): Promise<LanCryptoSession> {
    await sodium.ready;
    return new LanCryptoSession(sodium.randombytes_buf(32));
  }

  clientHello(): Uint8Array {
    return Message.encode(
      Message.create({
        lan_client_hello: {
          protocol_version: PROTOCOL_VERSION,
          client_nonce: this.clientNonce,
          client_capabilities: 0n,
        },
      }),
    ).finish();
  }

  async acceptServerHello(
    hello: LanServerHello,
  ): Promise<{ keyMessage: Uint8Array; fingerprint: string }> {
    if (hello.protocol_version !== PROTOCOL_VERSION) {
      throw new Error(`协议版本不匹配（服务器 ${hello.protocol_version}，浏览器 ${PROTOCOL_VERSION}）`);
    }
    if (hello.device_public_key.length !== 32 || hello.ephemeral_public_key.length !== 32) {
      throw new Error("服务器公钥格式无效");
    }

    const transcript = buildHandshakeTranscript(
      this.clientNonce,
      hello.server_nonce,
      hello.ephemeral_public_key,
    );
    const opened = sodium.crypto_sign_open(hello.signature, hello.device_public_key);
    if (!opened || !equalBytes(opened, transcript)) {
      throw new Error("设备签名校验失败，连接可能被篡改");
    }

    const keyPair = sodium.crypto_box_keypair();
    const symmetricKey = sodium.randombytes_buf(sodium.crypto_secretbox_KEYBYTES);
    const sealedKey = sodium.crypto_box_easy(
      symmetricKey,
      ZERO_NONCE,
      hello.ephemeral_public_key,
      keyPair.privateKey,
    );
    this.symmetricKey = symmetricKey;
    const digest = sha256(hello.device_public_key);
    const keyMessage = Message.encode(
      Message.create({
        public_key: {
          asymmetric_value: keyPair.publicKey,
          symmetric_value: sealedKey,
        },
      }),
    ).finish();
    return { keyMessage, fingerprint: bytesToHex(digest) };
  }

  clientIdentifier(): string {
    return `web-${bytesToHex(sodium.randombytes_buf(16))}`;
  }

  encrypt(message: Message): Uint8Array {
    if (!this.symmetricKey) throw new Error("安全通道尚未建立");
    this.sendSequence += 1n;
    return sodium.crypto_secretbox_easy(
      Message.encode(message).finish(),
      nonceForSequence(this.sendSequence),
      this.symmetricKey,
    );
  }

  decrypt(payload: Uint8Array): Message {
    if (!this.symmetricKey) throw new Error("安全通道尚未建立");
    this.receiveSequence += 1n;
    const opened = sodium.crypto_secretbox_open_easy(
      payload,
      nonceForSequence(this.receiveSequence),
      this.symmetricKey,
    );
    if (!opened) throw new Error("加密消息校验失败");
    return Message.decode(opened);
  }
}
