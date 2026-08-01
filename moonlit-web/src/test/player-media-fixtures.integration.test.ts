import { readFile } from 'node:fs/promises';
import { createServer, type Server } from 'node:http';
import { resolve } from 'node:path';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const fixtureRoot = resolve(process.cwd(), 'src/test/fixtures/player-media');
const allowedOrigin = 'https://moonlit.example';
let server: Server | undefined;
let origin = '';

function mp4DurationSeconds(bytes: Buffer): number {
  const marker = bytes.indexOf(Buffer.from('mvhd'));
  if (marker < 0 || bytes[marker + 4] !== 0) throw new Error('Expected a version-0 mvhd box');
  const timescale = bytes.readUInt32BE(marker + 16);
  const duration = bytes.readUInt32BE(marker + 20);
  return duration / timescale;
}

beforeAll(async () => {
  const files = new Map(await Promise.all(
    ['sample-av.mp4', 'sample.m3u8', 'sample-hls-00.mpegts', 'sample-hls-01.mpegts'].map(async name => [
      `/${name}`,
      await readFile(resolve(fixtureRoot, name)),
    ] as const),
  ));
  server = createServer((request, response) => {
    const pathname = new URL(request.url ?? '/', 'http://fixture.local').pathname.replace('/protected', '');
    const body = files.get(pathname);
    if (!body) {
      response.writeHead(404).end();
      return;
    }
    if (request.url?.startsWith('/protected/') && request.headers.authorization !== 'Bearer fixture-token') {
      response.writeHead(401, { 'Cache-Control': 'no-store' }).end();
      return;
    }
    if (request.headers.origin === allowedOrigin) response.setHeader('Access-Control-Allow-Origin', allowedOrigin);
    response.setHeader('Accept-Ranges', 'bytes');
    response.setHeader('Content-Type', pathname.endsWith('.m3u8')
      ? 'application/vnd.apple.mpegurl'
      : pathname.endsWith('.mpegts') ? 'video/mp2t' : 'video/mp4');
    const match = /^bytes=(\d+)-(\d+)?$/.exec(request.headers.range ?? '');
    if (match) {
      const start = Number(match[1]);
      const end = Math.min(Number(match[2] ?? body.length - 1), body.length - 1);
      response.writeHead(206, {
        'Content-Length': end - start + 1,
        'Content-Range': `bytes ${start}-${end}/${body.length}`,
      });
      response.end(body.subarray(start, end + 1));
      return;
    }
    response.writeHead(200, { 'Content-Length': body.length });
    response.end(body);
  });
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Fixture server did not bind');
  origin = `http://127.0.0.1:${address.port}`;
});

afterAll(async () => {
  if (!server) return;
  await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
});

describe('encoded player media fixtures', () => {
  it('serves an actual H.264/AAC MP4 with authenticated byte ranges and CORS', async () => {
    const unauthorized = await fetch(`${origin}/protected/sample-av.mp4`);
    expect(unauthorized.status).toBe(401);
    expect(unauthorized.headers.get('cache-control')).toBe('no-store');

    const ranged = await fetch(`${origin}/protected/sample-av.mp4`, {
      headers: {
        Authorization: 'Bearer fixture-token',
        Origin: allowedOrigin,
        Range: 'bytes=0-4095',
      },
    });
    const bytes = Buffer.from(await ranged.arrayBuffer());

    expect(ranged.status).toBe(206);
    expect(ranged.headers.get('access-control-allow-origin')).toBe(allowedOrigin);
    expect(ranged.headers.get('content-range')).toMatch(/^bytes 0-4095\/\d+$/);
    expect(bytes.subarray(4, 8).toString()).toBe('ftyp');
  });

  it('contains real video/audio tracks and deterministic two-second end timing', async () => {
    const response = await fetch(`${origin}/sample-av.mp4`);
    const bytes = Buffer.from(await response.arrayBuffer());

    expect(bytes.includes(Buffer.from('avc1'))).toBe(true);
    expect(bytes.includes(Buffer.from('mp4a'))).toBe(true);
    expect(mp4DurationSeconds(bytes)).toBe(2);
  });

  it('serves a finite encoded HLS presentation whose segments have MPEG-TS sync bytes', async () => {
    const manifest = await fetch(`${origin}/sample.m3u8`, { headers: { Origin: allowedOrigin } }).then(result => result.text());
    const durations = [...manifest.matchAll(/#EXTINF:([\d.]+)/g)].map(match => Number(match[1]));
    const segment = Buffer.from(await fetch(`${origin}/sample-hls-00.mpegts`).then(result => result.arrayBuffer()));

    expect(manifest).toContain('#EXT-X-ENDLIST');
    expect(durations.reduce((sum, duration) => sum + duration, 0)).toBe(2);
    expect(segment.length).toBeGreaterThan(188);
    expect(segment[0]).toBe(0x47);
    expect(segment[188]).toBe(0x47);
  });
});
