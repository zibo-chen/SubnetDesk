const TRANSCRIPT_PREFIX = new TextEncoder().encode("rustdesk-lan-handshake-v1\0");
const NONCE_LENGTH = 32;
const PUBLIC_KEY_LENGTH = 32;
const SECRETBOX_NONCE_LENGTH = 24;

export function buildHandshakeTranscript(
  clientNonce: Uint8Array,
  serverNonce: Uint8Array,
  ephemeralPublicKey: Uint8Array,
): Uint8Array {
  if (
    clientNonce.length !== NONCE_LENGTH ||
    serverNonce.length !== NONCE_LENGTH ||
    ephemeralPublicKey.length !== PUBLIC_KEY_LENGTH
  ) {
    throw new Error("服务器握手数据格式无效");
  }

  const transcript = new Uint8Array(
    TRANSCRIPT_PREFIX.length + 4 + NONCE_LENGTH * 2 + PUBLIC_KEY_LENGTH,
  );
  let offset = 0;
  transcript.set(TRANSCRIPT_PREFIX, offset);
  offset += TRANSCRIPT_PREFIX.length;
  new DataView(transcript.buffer).setUint32(offset, 1, false);
  offset += 4;
  transcript.set(clientNonce, offset);
  offset += clientNonce.length;
  transcript.set(serverNonce, offset);
  offset += serverNonce.length;
  transcript.set(ephemeralPublicKey, offset);
  return transcript;
}

export function nonceForSequence(sequence: bigint): Uint8Array {
  if (sequence < 0n || sequence > 0xffff_ffff_ffff_ffffn) {
    throw new Error("消息序号超出范围");
  }
  const nonce = new Uint8Array(SECRETBOX_NONCE_LENGTH);
  new DataView(nonce.buffer).setBigUint64(0, sequence, true);
  return nonce;
}

export function mapCanvasPoint(
  clientX: number,
  clientY: number,
  canvasWidth: number,
  canvasHeight: number,
  remoteWidth: number,
  remoteHeight: number,
  remoteX = 0,
  remoteY = 0,
): { x: number; y: number } {
  if (canvasWidth <= 0 || canvasHeight <= 0 || remoteWidth <= 0 || remoteHeight <= 0) {
    return { x: 0, y: 0 };
  }

  const scale = Math.min(canvasWidth / remoteWidth, canvasHeight / remoteHeight);
  const renderedWidth = remoteWidth * scale;
  const renderedHeight = remoteHeight * scale;
  const offsetX = (canvasWidth - renderedWidth) / 2;
  const offsetY = (canvasHeight - renderedHeight) / 2;
  const x = Math.round((clientX - offsetX) / scale);
  const y = Math.round((clientY - offsetY) / scale);
  return {
    x: remoteX + Math.max(0, Math.min(remoteWidth - 1, x)),
    y: remoteY + Math.max(0, Math.min(remoteHeight - 1, y)),
  };
}

function buttonFlag(button: number): number {
  if (button === 0) return 1;
  if (button === 2) return 2;
  if (button === 1) return 4;
  return 0;
}

export function mouseMask(type: number, button: number, buttons: number): number {
  if (type !== 0) return type | (buttonFlag(button) << 3);
  let held = 0;
  if ((buttons & 1) !== 0) held |= 1;
  if ((buttons & 2) !== 0) held |= 2;
  if ((buttons & 4) !== 0) held |= 4;
  return held << 3;
}

export function normalizeFingerprint(value: string): string {
  const normalized = value.toLowerCase().replaceAll(":", "").replaceAll("-", "");
  if (normalized.length === 0 || !/^[0-9a-f]+$/.test(normalized)) {
    throw new Error("设备指纹格式无效");
  }
  return normalized;
}

export function bytesToHex(value: Uint8Array): string {
  return Array.from(value, (byte) => byte.toString(16).padStart(2, "0")).join("");
}
