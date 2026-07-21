import type { VideoFrame as ProtocolVideoFrame } from "./generated/message";

interface VideoDecodeQueue {
  decode(chunk: EncodedVideoChunk): void;
}

type EncodedVideoChunkFactory = (init: EncodedVideoChunkInit) => EncodedVideoChunk;

export function decodeVideoBatch(
  decoder: VideoDecodeQueue,
  frame: ProtocolVideoFrame,
  previousTimestamp: number,
  createChunk: EncodedVideoChunkFactory = (init) => new EncodedVideoChunk(init),
): number {
  const frames = frame.vp9s?.frames;
  if (!frames) return previousTimestamp;

  let timestamp = previousTimestamp;
  for (const encoded of frames) {
    const sourceTimestamp = Number(encoded.pts);
    timestamp = Number.isSafeInteger(sourceTimestamp) && sourceTimestamp > timestamp
      ? sourceTimestamp
      : timestamp + 1;
    decoder.decode(
      createChunk({
        type: encoded.key ? "key" : "delta",
        timestamp,
        data: encoded.data,
      }),
    );
  }
  return timestamp;
}
