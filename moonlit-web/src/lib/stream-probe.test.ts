import { describe, expect, it } from 'vitest';
import { classifyStreamProbe } from './stream-probe';

describe('stream probe classification', () => {
  it('accepts mp4 byte signatures as browser playable', () => {
    const bytes = new Uint8Array([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d]);

    expect(classifyStreamProbe({ status: 206, contentType: 'application/octet-stream', bytes }).playable).toBe(true);
  });

  it('rejects matroska byte signatures for browser playback', () => {
    const bytes = new Uint8Array([0x1a, 0x45, 0xdf, 0xa3, 0x93, 0x42, 0x82, 0x88]);

    expect(classifyStreamProbe({ status: 206, contentType: 'application/octet-stream', bytes }).playable).toBe(false);
  });

  it('rejects upstream html error responses', () => {
    const bytes = new TextEncoder().encode('<html><head><title>502 Bad Gateway</title></head>');

    expect(classifyStreamProbe({ status: 502, contentType: 'text/html', bytes }).playable).toBe(false);
  });

  it('accepts mislabeled hls playlists by sniffing bytes', () => {
    const bytes = new TextEncoder().encode('#EXTM3U\n#EXT-X-VERSION:3');

    expect(classifyStreamProbe({ status: 200, contentType: 'text/plain', bytes })).toMatchObject({
      playable: true,
      type: 'application/x-mpegurl',
    });
  });
});
