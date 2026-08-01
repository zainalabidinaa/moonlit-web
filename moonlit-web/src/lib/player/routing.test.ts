import { describe, expect, it } from 'vitest';

import type { StreamItem } from '@/lib/types';
import { buildPlaybackPlan, type PlaybackEnvironment } from './routing';

const browser: PlaybackEnvironment = {
  chromium: false,
  mediaSource: true,
  nativeHls: false,
  hevc: false,
  hevc10: false,
  av1: false,
  ac3: false,
  eac3: false,
  webCodecs: true,
  mediabunny: true,
  mpv: false,
};

function stream(url: string | undefined, title: string, extra: Partial<StreamItem> = {}): StreamItem {
  return { url, title, ...extra };
}

describe('buildPlaybackPlan routing matrix', () => {
  it.each([
    {
      name: 'direct MP4',
      item: stream('https://cdn.example/movie.mp4', 'Movie 1080p H.264 AAC'),
      env: browser,
      options: {},
      outcome: 'play-here',
      methods: ['native'],
    },
    {
      name: 'native HLS',
      item: stream('https://cdn.example/master.m3u8', 'Channel H.264 AAC'),
      env: { ...browser, mediaSource: false, nativeHls: true },
      options: { isLive: true },
      outcome: 'play-here',
      methods: ['native-hls'],
    },
    {
      name: 'HLS.js MSE',
      item: stream('https://cdn.example/master.m3u8', 'Movie H.264 AAC'),
      env: browser,
      options: {},
      outcome: 'play-here',
      methods: ['hls-mse'],
    },
    {
      name: 'lazy live MPEG-TS',
      item: stream('https://tv.example/live/user/pass/42', 'Moonlit Sports'),
      env: browser,
      options: { isLive: true },
      outcome: 'play-here',
      methods: ['mpeg-ts'],
    },
    {
      name: 'safe Chromium MKV',
      item: stream('https://cdn.example/movie.mkv', 'Movie H.264 AAC'),
      env: { ...browser, chromium: true },
      options: {},
      outcome: 'play-here',
      methods: ['chromium-mkv', 'mediabunny-remux', 'webcodecs'],
    },
    {
      name: 'Mediabunny remux',
      item: stream('https://cdn.example/movie.mkv', 'Movie H.264 AAC'),
      env: browser,
      options: {},
      outcome: 'play-here',
      methods: ['mediabunny-remux', 'webcodecs'],
    },
    {
      name: 'server transcode for HEVC',
      item: stream('https://cdn.example/movie.mkv', 'Movie 2160p HEVC AAC'),
      env: browser,
      options: { serverUrl: 'https://stream.example' },
      outcome: 'play-here',
      methods: ['server-transcode'],
    },
    {
      name: 'server transcode for unsupported AC-3',
      item: stream('https://cdn.example/movie.mkv', 'Movie H.264 AC-3'),
      env: browser,
      options: { serverUrl: 'https://stream.example' },
      outcome: 'play-here',
      methods: ['server-transcode'],
    },
    {
      name: 'MPV for unsupported browser codecs',
      item: stream('https://cdn.example/movie.mkv', 'Movie 2160p HEVC TrueHD'),
      env: { ...browser, mpv: true },
      options: { enginePreference: 'mpv' },
      outcome: 'play-here',
      methods: ['mpv'],
    },
  ])('routes $name', ({ item, env, options, outcome, methods }) => {
    const plan = buildPlaybackPlan(item, env, options);

    expect(plan.outcome).toBe(outcome);
    expect(plan.attempts.map(attempt => attempt.method)).toEqual(methods);
  });

  it.each([
    ['Dolby Vision profile 5', 'Movie DoVi P5 HEVC AAC'],
    ['AV1 without a decoder', 'Movie AV1 AAC'],
    ['E-AC-3 without an audio decoder', 'Movie H.264 E-AC-3'],
    ['DD+ without an audio decoder', 'Movie H.264 DD+ 5.1'],
  ])('returns an honest external outcome for %s when no conversion path exists', (_name, title) => {
    const plan = buildPlaybackPlan(stream('https://cdn.example/movie.mkv', title), browser);

    expect(plan).toMatchObject({ outcome: 'external', label: 'Open externally' });
    expect(plan.externalUrl).toBe('https://cdn.example/movie.mkv');
    expect(plan.attempts).toEqual([]);
    expect(plan.detail.length).toBeGreaterThan(0);
  });

  it.each([
    ['archive', stream('https://cdn.example/movie.mkv.zip', 'Movie archive')],
    ['no video', stream('https://cdn.example/soundtrack.flac', 'Original soundtrack audio only')],
    ['unresolved torrent', stream(undefined, 'Torrent only', { infoHash: 'abc123' })],
  ])('rejects %s sources before an engine starts', (_name, item) => {
    expect(buildPlaybackPlan(item, browser)).toMatchObject({
      outcome: 'unsupported',
      label: 'Not playable',
      attempts: [],
    });
  });

  it('uses a supplied external URL instead of pretending browser playback is available', () => {
    const plan = buildPlaybackPlan({ externalUrl: 'vlc://movie', title: 'External source' }, browser);

    expect(plan).toMatchObject({
      outcome: 'external',
      externalUrl: 'vlc://movie',
      attempts: [],
    });
  });

  it('falls back from MPV to browser adapters when MPV is requested but unavailable', () => {
    const plan = buildPlaybackPlan(
      stream('https://cdn.example/movie.mp4', 'Movie H.264 AAC'),
      browser,
      { enginePreference: 'mpv' },
    );

    expect(plan.attempts.map(attempt => attempt.method)).toEqual(['native']);
    expect(plan.detail).toContain('MPV unavailable');
  });

  it('does not invent an insecure proxy route for protected direct media', () => {
    const plan = buildPlaybackPlan(
      stream('https://cdn.example/protected.mp4', 'Movie H.264 AAC', {
        behaviorHints: { proxyHeaders: { request: { Authorization: 'Bearer test' } } },
      }),
      browser,
    );

    expect(plan.outcome).toBe('external');
    expect(plan.externalUrl).toBe('https://cdn.example/protected.mp4');
    expect(plan.attempts).toEqual([]);
  });

  it('does not choose native HLS when protected manifests require request headers', () => {
    const plan = buildPlaybackPlan(
      stream('https://cdn.example/protected.m3u8', 'Channel H.264 AAC', {
        behaviorHints: { proxyHeaders: { request: { Authorization: 'Bearer test' } } },
      }),
      { ...browser, nativeHls: true },
      { isLive: true },
    );

    expect(plan.attempts.map(item => item.method)).toEqual(['hls-mse']);
  });

  it('binds headers to the selected stream and never forwards them to a configured server', () => {
    const item = stream('https://source.example/protected.mkv', 'Movie 2160p HEVC AAC', {
      behaviorHints: { proxyHeaders: { request: { Authorization: 'Bearer source' } } },
    });
    const plan = buildPlaybackPlan(item, browser, {
      serverUrl: 'https://server.example',
      requestHeaders: { Authorization: 'Bearer unrelated-launch' },
    });

    expect(plan.outcome).toBe('external');
    expect(plan.attempts).toEqual([]);
    expect(JSON.stringify(plan.attempts)).not.toContain('Bearer');
  });

  it.each([
    {
      name: 'HLS runtime recovery',
      item: stream('https://cdn.example/master.m3u8', 'H.264 AAC HLS'),
      env: { ...browser, nativeHls: true, mpv: true },
      options: { serverUrl: 'https://server.example' },
      methods: ['native-hls', 'hls-mse', 'server-remux', 'mpv'],
    },
    {
      name: 'live MPEG-TS recovery',
      item: stream('https://tv.example/live/user/pass/42', 'Live H.264 AAC'),
      env: { ...browser, mpv: true },
      options: { isLive: true, serverUrl: 'https://server.example' },
      methods: ['mpeg-ts', 'server-remux', 'mpv'],
    },
    {
      name: 'live MPEG-TS without browser MSE',
      item: stream('https://tv.example/live/user/pass/42', 'Live H.264 AAC'),
      env: { ...browser, mediaSource: false, mpv: true },
      options: { isLive: true, serverUrl: 'https://server.example' },
      methods: ['server-remux', 'mpv'],
    },
    {
      name: 'explicit MPV runtime recovery',
      item: stream('https://cdn.example/movie.mp4', 'H.264 AAC'),
      env: { ...browser, mpv: true },
      options: { enginePreference: 'mpv' as const, serverUrl: 'https://server.example' },
      methods: ['mpv', 'native', 'server-remux'],
    },
    {
      name: 'blocked codec recovery',
      item: stream('https://cdn.example/movie.mkv', 'HEVC AAC'),
      env: { ...browser, mpv: true },
      options: { serverUrl: 'https://server.example' },
      methods: ['server-transcode', 'mpv'],
    },
    {
      name: 'direct file recovery',
      item: stream('https://cdn.example/movie.mp4', 'H.264 AAC'),
      env: { ...browser, mpv: true },
      options: { serverUrl: 'https://server.example' },
      methods: ['native', 'server-remux', 'mpv'],
    },
  ])('builds the complete ordered ladder for $name', ({ item, env, options, methods }) => {
    const plan = buildPlaybackPlan(item, env, options);

    expect(plan.attempts.map(value => value.method)).toEqual(methods);
  });
});
