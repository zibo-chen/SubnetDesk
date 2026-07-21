import {
  ControlKey,
  KeyboardMode,
  Message,
  OptionMessage_BoolOption,
  SupportedDecoding_PreferCodec,
  type DisplayInfo,
  type KeyEvent,
  type PeerInfo,
} from "./generated/message";
import { LanCryptoSession } from "./crypto";
import { mapCanvasPoint, mouseMask, normalizeFingerprint } from "./protocol";
import { decodeVideoBatch } from "./video";

interface ServerInfo {
  app_name: string;
  device_name: string;
  fingerprint: string;
  version: string;
  secure: boolean;
}

interface Credentials {
  username: string;
  password: string;
}

const MAX_PASSWORD_LENGTH = 256;
const encoder = new TextEncoder();

function requiredElement<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`页面元素缺失：${id}`);
  return element as T;
}

const connectPanel = requiredElement<HTMLElement>("connect-panel");
const viewerPanel = requiredElement<HTMLElement>("viewer-panel");
const loginForm = requiredElement<HTMLFormElement>("login-form");
const usernameInput = requiredElement<HTMLInputElement>("username");
const passwordInput = requiredElement<HTMLInputElement>("password");
const connectButton = requiredElement<HTMLButtonElement>("connect");
const disconnectButton = requiredElement<HTMLButtonElement>("disconnect");
const fullscreenButton = requiredElement<HTMLButtonElement>("fullscreen");
const canvas = requiredElement<HTMLCanvasElement>("screen");
const deviceName = requiredElement<HTMLElement>("device-name");
const fingerprintElement = requiredElement<HTMLElement>("fingerprint");
const statusElement = requiredElement<HTMLElement>("status");
const viewerStatus = requiredElement<HTMLElement>("viewer-status");

let serverInfo: ServerInfo;
let socket: WebSocket | undefined;
let cryptoSession: LanCryptoSession | undefined;
let secured = false;
let authenticated = false;
let remoteDisplay: DisplayInfo | undefined;
let decoder: VideoDecoder | undefined;
let frameTimestamp = 0;

function setStatus(message: string, error = false): void {
  statusElement.textContent = message;
  statusElement.dataset.error = error ? "true" : "false";
}

function resetConnection(message = "已断开"): void {
  secured = false;
  authenticated = false;
  cryptoSession = undefined;
  connectButton.disabled = false;
  socket = undefined;
  decoder?.close();
  decoder = undefined;
  remoteDisplay = undefined;
  viewerPanel.hidden = true;
  connectPanel.hidden = false;
  viewerStatus.textContent = "";
  setStatus(message);
}

function closeConnection(message = "已断开"): void {
  const active = socket;
  socket = undefined;
  if (active && active.readyState < WebSocket.CLOSING) active.close(1000, "client closed");
  resetConnection(message);
}

function sendRaw(payload: Uint8Array): void {
  if (!socket || socket.readyState !== WebSocket.OPEN) throw new Error("连接已经关闭");
  socket.send(payload);
}

function send(message: Message): void {
  if (!cryptoSession || !secured) throw new Error("安全通道尚未建立");
  sendRaw(cryptoSession.encrypt(message));
}

function currentModifiers(event: KeyboardEvent | MouseEvent | WheelEvent): ControlKey[] {
  const modifiers: ControlKey[] = [];
  if (event.altKey) modifiers.push(ControlKey.Alt);
  if (event.ctrlKey) modifiers.push(ControlKey.Control);
  if (event.shiftKey) modifiers.push(ControlKey.Shift);
  if (event.metaKey) modifiers.push(ControlKey.Meta);
  return modifiers;
}

const controlKeys: Record<string, ControlKey> = {
  Alt: ControlKey.Alt,
  Backspace: ControlKey.Backspace,
  CapsLock: ControlKey.CapsLock,
  Control: ControlKey.Control,
  Delete: ControlKey.Delete,
  ArrowDown: ControlKey.DownArrow,
  End: ControlKey.End,
  Escape: ControlKey.Escape,
  Home: ControlKey.Home,
  ArrowLeft: ControlKey.LeftArrow,
  Meta: ControlKey.Meta,
  PageDown: ControlKey.PageDown,
  PageUp: ControlKey.PageUp,
  Enter: ControlKey.Return,
  ArrowRight: ControlKey.RightArrow,
  Shift: ControlKey.Shift,
  " ": ControlKey.Space,
  Tab: ControlKey.Tab,
  ArrowUp: ControlKey.UpArrow,
  Insert: ControlKey.Insert,
};
for (let index = 1; index <= 12; index += 1) {
  controlKeys[`F${index}`] = ControlKey[`F${index}` as keyof typeof ControlKey] as ControlKey;
}

function sendKey(event: KeyboardEvent): void {
  if (!authenticated) return;
  const controlKey = controlKeys[event.key];
  const keyEvent: Partial<KeyEvent> = {
    down: false,
    press: true,
    modifiers: currentModifiers(event),
    mode: KeyboardMode.Legacy,
  };
  if (controlKey !== undefined) {
    keyEvent.control_key = controlKey;
  } else {
    const codePoint = Array.from(event.key)[0]?.codePointAt(0);
    if (codePoint === undefined || event.key.length > 2) return;
    keyEvent.unicode = codePoint;
  }
  event.preventDefault();
  send(Message.create({ key_event: keyEvent }));
}

function canvasCoordinates(event: MouseEvent): { x: number; y: number } {
  if (!remoteDisplay) return { x: 0, y: 0 };
  const bounds = canvas.getBoundingClientRect();
  return mapCanvasPoint(
    event.clientX - bounds.left,
    event.clientY - bounds.top,
    bounds.width,
    bounds.height,
    remoteDisplay.width,
    remoteDisplay.height,
    remoteDisplay.x,
    remoteDisplay.y,
  );
}

function sendMouse(event: MouseEvent, type: number): void {
  if (!authenticated) return;
  const point = canvasCoordinates(event);
  send(
    Message.create({
      mouse_event: {
        mask: mouseMask(type, event.button, event.buttons),
        x: point.x,
        y: point.y,
        modifiers: currentModifiers(event),
      },
    }),
  );
}

function configureDecoder(peer: PeerInfo): void {
  const display = peer.displays[peer.current_display] ?? peer.displays[0];
  if (!display) throw new Error("远端没有可用显示器");
  remoteDisplay = display;
  canvas.width = display.width;
  canvas.height = display.height;
  const context = canvas.getContext("2d", { alpha: false });
  if (!context) throw new Error("浏览器无法创建画布");
  decoder?.close();
  decoder = new VideoDecoder({
    output: (frame) => {
      context.drawImage(frame, 0, 0, canvas.width, canvas.height);
      frame.close();
    },
    error: (error) => closeConnection(`视频解码失败：${error.message}`),
  });
  decoder.configure({
    codec: "vp09.00.10.08",
    codedWidth: display.width,
    codedHeight: display.height,
    optimizeForLatency: true,
  });
  viewerStatus.textContent = `${peer.hostname || serverInfo.device_name} · ${display.width}×${display.height}`;
}

function authenticate(username: string, password: string): void {
  const passwordBytes = encoder.encode(password);
  try {
    send(
      Message.create({
        login_request: {
          my_id: cryptoSession?.clientIdentifier() ?? "web",
          my_name:
            (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData
              ?.platform || navigator.platform || "Browser",
          my_platform: "Web",
          version: serverInfo.version,
          video_ack_required: true,
          session_id: 0n,
          lan_login: {
            access_username: username,
            access_password: passwordBytes,
            credential_revision_hint: 0n,
          },
          option: {
            disable_audio: OptionMessage_BoolOption.Yes,
            disable_clipboard: OptionMessage_BoolOption.Yes,
            show_remote_cursor: OptionMessage_BoolOption.No,
            supported_decoding: {
              ability_vp9: 1,
              prefer: SupportedDecoding_PreferCodec.VP9,
            },
          },
        },
      }),
    );
  } finally {
    passwordBytes.fill(0);
  }
}

async function handleMessage(payload: Uint8Array, credentials: Credentials): Promise<void> {
  if (!cryptoSession) throw new Error("连接状态无效");
  if (!secured) {
    const message = Message.decode(payload);
    if (!message.lan_server_hello) throw new Error("服务器没有返回 LAN 安全握手");
    const result = await cryptoSession.acceptServerHello(message.lan_server_hello);
    if (normalizeFingerprint(result.fingerprint) !== normalizeFingerprint(serverInfo.fingerprint)) {
      throw new Error("网页公布的设备指纹与握手签名不一致");
    }
    sendRaw(result.keyMessage);
    secured = true;
    setStatus("安全通道已建立，正在认证…");
    authenticate(credentials.username, credentials.password);
    credentials.password = "";
    return;
  }

  const message = cryptoSession.decrypt(payload);
  if (message.login_response) {
    if (message.login_response.error) {
      const retry = message.login_response.retry_after_seconds;
      throw new Error(`${message.login_response.error}${retry ? `（${retry} 秒后重试）` : ""}`);
    }
    if (!message.login_response.peer_info) throw new Error("服务器没有返回桌面信息");
    configureDecoder(message.login_response.peer_info);
    authenticated = true;
    connectPanel.hidden = true;
    viewerPanel.hidden = false;
    canvas.focus();
    setStatus("已连接");
  }
  if (message.peer_info) configureDecoder(message.peer_info);
  if (message.video_frame) {
    if (decoder) frameTimestamp = decodeVideoBatch(decoder, message.video_frame, frameTimestamp);
    send(Message.create({ misc: { video_received: true } }));
  }
  if (message.test_delay && !message.test_delay.from_client) {
    send(Message.create({ test_delay: message.test_delay }));
  }
  if (message.misc?.close_reason) closeConnection(message.misc.close_reason);
  if (message.message_box?.text) viewerStatus.textContent = message.message_box.text;
}

async function connect(username: string, password: string): Promise<void> {
  if (!("VideoDecoder" in window) || !("EncodedVideoChunk" in window)) {
    throw new Error("当前浏览器不支持 WebCodecs，请使用最新版 Chrome 或 Edge");
  }
  cryptoSession = await LanCryptoSession.create();
  const scheme = location.protocol === "https:" ? "wss:" : "ws:";
  const nextSocket = new WebSocket(`${scheme}//${location.host}/ws`);
  const credentials: Credentials = { username, password };
  let receiveQueue = Promise.resolve();
  nextSocket.binaryType = "arraybuffer";
  socket = nextSocket;

  nextSocket.addEventListener("open", () => {
    if (socket !== nextSocket || !cryptoSession) return;
    setStatus("正在校验设备身份…");
    sendRaw(cryptoSession.clientHello());
  });
  nextSocket.addEventListener("message", (event) => {
    if (socket !== nextSocket || !(event.data instanceof ArrayBuffer)) return;
    receiveQueue = receiveQueue
      .then(() => handleMessage(new Uint8Array(event.data), credentials))
      .catch((error: unknown) => {
        closeConnection(error instanceof Error ? error.message : "连接失败");
        statusElement.dataset.error = "true";
      });
  });
  nextSocket.addEventListener("error", () => {
    credentials.password = "";
    if (socket === nextSocket) closeConnection("网络连接失败");
    statusElement.dataset.error = "true";
  });
  nextSocket.addEventListener("close", () => {
    credentials.password = "";
    if (socket === nextSocket) resetConnection(authenticated ? "远端已断开" : "连接已关闭");
  });
}

loginForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const username = usernameInput.value.trim();
  const password = passwordInput.value;
  if (!username || !password) {
    setStatus("请输入访问用户名和密码", true);
    return;
  }
  if (encoder.encode(password).length > MAX_PASSWORD_LENGTH) {
    setStatus("密码过长", true);
    return;
  }
  connectButton.disabled = true;
  setStatus("正在连接…");
  passwordInput.value = "";
  void connect(username, password).catch((error: unknown) => {
    resetConnection(error instanceof Error ? error.message : "连接失败");
    statusElement.dataset.error = "true";
  });
});

disconnectButton.addEventListener("click", () => closeConnection());
fullscreenButton.addEventListener("click", () => void viewerPanel.requestFullscreen());
canvas.addEventListener("contextmenu", (event) => event.preventDefault());
canvas.addEventListener("mousemove", (event) => sendMouse(event, 0));
canvas.addEventListener("mousedown", (event) => {
  canvas.focus();
  sendMouse(event, 1);
});
canvas.addEventListener("mouseup", (event) => sendMouse(event, 2));
canvas.addEventListener(
  "wheel",
  (event) => {
    if (!authenticated) return;
    event.preventDefault();
    send(
      Message.create({
        mouse_event: {
          mask: 3,
          x: Math.round(event.deltaX),
          y: Math.round(event.deltaY),
          modifiers: currentModifiers(event),
        },
      }),
    );
  },
  { passive: false },
);
canvas.addEventListener("keydown", sendKey);

void fetch("/api/info", { cache: "no-store", credentials: "same-origin" })
  .then(async (response) => {
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    serverInfo = (await response.json()) as ServerInfo;
    deviceName.textContent = serverInfo.device_name;
    fingerprintElement.textContent = serverInfo.fingerprint.match(/.{1,4}/g)?.join(" ") ?? serverInfo.fingerprint;
    connectButton.disabled = false;
    setStatus(serverInfo.secure ? "HTTPS 已启用" : "警告：当前使用未加密 HTTP", !serverInfo.secure);
  })
  .catch((error: unknown) => {
    connectButton.disabled = true;
    setStatus(`无法读取设备信息：${error instanceof Error ? error.message : "未知错误"}`, true);
  });
