import { describe, expect, test } from "bun:test";
import { VideoFrame } from "../src/generated/message";
import { decodeVideoBatch } from "../src/video";

describe("WebCodecs video queue", () => {
  test("keeps the decoder open between a key-frame batch and following delta frames", () => {
    const decoded: EncodedVideoChunkInit[] = [];
    let flushCalls = 0;
    const decoder = {
      decode: (chunk: EncodedVideoChunk) => decoded.push(chunk as unknown as EncodedVideoChunkInit),
      flush: async () => {
        flushCalls += 1;
      },
    };
    const createChunk = (init: EncodedVideoChunkInit) => init as unknown as EncodedVideoChunk;

    let timestamp = decodeVideoBatch(
      decoder,
      VideoFrame.create({
        vp9s: { frames: [{ key: true, pts: 1n, data: new Uint8Array([1]) }] },
      }),
      0,
      createChunk,
    );
    timestamp = decodeVideoBatch(
      decoder,
      VideoFrame.create({
        vp9s: { frames: [{ key: false, pts: 2n, data: new Uint8Array([2]) }] },
      }),
      timestamp,
      createChunk,
    );

    expect(decoded.map(({ type }) => type)).toEqual(["key", "delta"]);
    expect(decoded.map(({ timestamp: value }) => value)).toEqual([1, 2]);
    expect(timestamp).toBe(2);
    expect(flushCalls).toBe(0);
  });

  test("keeps timestamps increasing when the source timestamp repeats", () => {
    const decoded: EncodedVideoChunkInit[] = [];
    const decoder = {
      decode: (chunk: EncodedVideoChunk) => decoded.push(chunk as unknown as EncodedVideoChunkInit),
    };
    const createChunk = (init: EncodedVideoChunkInit) => init as unknown as EncodedVideoChunk;
    const timestamp = decodeVideoBatch(
      decoder,
      VideoFrame.create({
        vp9s: {
          frames: [
            { key: true, pts: 5n, data: new Uint8Array([1]) },
            { key: false, pts: 5n, data: new Uint8Array([2]) },
          ],
        },
      }),
      4,
      createChunk,
    );

    expect(decoded.map(({ timestamp: value }) => value)).toEqual([5, 6]);
    expect(timestamp).toBe(6);
  });
});
