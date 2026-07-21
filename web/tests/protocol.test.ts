import { describe, expect, test } from "bun:test";
import {
  buildHandshakeTranscript,
  mapCanvasPoint,
  mouseMask,
  nonceForSequence,
  normalizeFingerprint,
} from "../src/protocol";

describe("LAN protocol helpers", () => {
  test("the signed transcript binds the protocol and all nonces and keys", () => {
    const clientNonce = new Uint8Array(32).fill(1);
    const serverNonce = new Uint8Array(32).fill(2);
    const serverKey = new Uint8Array(32).fill(3);
    const transcript = buildHandshakeTranscript(clientNonce, serverNonce, serverKey);

    expect(new TextDecoder().decode(transcript.slice(0, 26))).toBe(
      "rustdesk-lan-handshake-v1\0",
    );
    expect(Array.from(transcript.slice(26, 30))).toEqual([0, 0, 0, 1]);
    expect(transcript.length).toBe(126);
  });

  test("rejects malformed handshake values", () => {
    expect(() =>
      buildHandshakeTranscript(new Uint8Array(31), new Uint8Array(32), new Uint8Array(32)),
    ).toThrow();
  });

  test("uses little endian monotonically increasing secretbox nonces", () => {
    expect(Array.from(nonceForSequence(1n).slice(0, 9))).toEqual([1, 0, 0, 0, 0, 0, 0, 0, 0]);
    expect(Array.from(nonceForSequence(0x0102n).slice(0, 3))).toEqual([2, 1, 0]);
  });

  test("maps letterboxed canvas coordinates to the remote display", () => {
    expect(mapCanvasPoint(500, 250, 1000, 500, 1920, 1080)).toEqual({ x: 960, y: 540 });
    expect(mapCanvasPoint(-10, 1000, 1000, 500, 1920, 1080)).toEqual({ x: 0, y: 1079 });
    expect(mapCanvasPoint(500, 250, 1000, 500, 1920, 1080, -1920, 120)).toEqual({
      x: -960,
      y: 660,
    });
  });

  test("encodes mouse movement and button transitions without phantom clicks", () => {
    expect(mouseMask(0, 0, 0)).toBe(0);
    expect(mouseMask(0, 0, 1)).toBe(8);
    expect(mouseMask(1, 0, 1)).toBe(9);
    expect(mouseMask(2, 2, 0)).toBe(18);
  });

  test("normalizes fingerprints without accepting arbitrary characters", () => {
    expect(normalizeFingerprint("AA:bb:01")).toBe("aabb01");
    expect(() => normalizeFingerprint("not a fingerprint")).toThrow();
  });
});
