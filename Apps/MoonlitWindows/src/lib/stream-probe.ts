export interface StreamProbeInput {
  status: number;
  contentType: string | null;
  bytes: Uint8Array;
}

export interface StreamProbeResult {
  playable: boolean;
  type?: 'video/mp4' | 'application/x-mpegurl';
  reason?: string;
}

function hasBytes(bytes: Uint8Array, offset: number, signature: number[]): boolean {
  return signature.every((byte, index) => bytes[offset + index] === byte);
}

export function classifyStreamProbe(input: StreamProbeInput): StreamProbeResult {
  const contentType = input.contentType?.toLowerCase() ?? '';
  const textPrefix = new TextDecoder().decode(input.bytes.slice(0, 64)).trimStart();

  if (input.status < 200 || input.status >= 300) return { playable: false, reason: `http-${input.status}` };
  if (contentType.includes('text/html')) return { playable: false, reason: 'html-error' };
  if (contentType.includes('application/vnd.apple.mpegurl') || contentType.includes('application/x-mpegurl')) return { playable: true, type: 'application/x-mpegurl' };
  if (textPrefix.startsWith('#EXTM3U')) return { playable: true, type: 'application/x-mpegurl' };
  if (contentType.includes('video/mp4')) return { playable: true, type: 'video/mp4' };

  if (hasBytes(input.bytes, 0, [0x1a, 0x45, 0xdf, 0xa3])) return { playable: false, reason: 'matroska' };

  for (let offset = 0; offset <= Math.min(input.bytes.length - 4, 16); offset += 1) {
    if (hasBytes(input.bytes, offset, [0x66, 0x74, 0x79, 0x70])) return { playable: true, type: 'video/mp4' };
  }

  return { playable: false, reason: 'unknown-container' };
}
