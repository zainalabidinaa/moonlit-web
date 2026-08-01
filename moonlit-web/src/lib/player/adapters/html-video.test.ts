import { afterEach, describe, expect, it, vi } from 'vitest';

import type { PlaybackAttempt } from '@/lib/player/contracts';
import {
  HtmlVideoAdapter,
  attachHtmlVideoPlayback,
  type HtmlVideoPlaybackDependencies,
} from './html-video';

function attempt(method: PlaybackAttempt['method'], url = 'https://cdn.example/movie.mp4'): PlaybackAttempt {
  return {
    id: `${method}:${url}`,
    adapter: 'html-video',
    method,
    url,
    sourceType: method === 'mpeg-ts' ? 'mpeg-ts' : method.includes('hls') ? 'hls' : 'video',
    isLive: method === 'mpeg-ts',
    reason: method,
    requestHeaders: { Authorization: 'Bearer test' },
  };
}

describe('attachHtmlVideoPlayback', () => {
  it('uses the native media element without loading either optional transport', async () => {
    const video = document.createElement('video');
    const dependencies: HtmlVideoPlaybackDependencies = {
      loadHls: vi.fn(),
      loadMpegTs: vi.fn(),
    };

    const cleanup = await attachHtmlVideoPlayback(video, attempt('native'), dependencies);

    expect(video.getAttribute('src')).toBe('https://cdn.example/movie.mp4');
    expect(dependencies.loadHls).not.toHaveBeenCalled();
    expect(dependencies.loadMpegTs).not.toHaveBeenCalled();
    cleanup();
    expect(video.hasAttribute('src')).toBe(false);
  });

  it('lazily attaches HLS.js with request headers for the MSE route', async () => {
    const video = document.createElement('video');
    const calls: { source?: string; media?: HTMLVideoElement; destroyed?: boolean; authorization?: string } = {};
    class FakeHls {
      static isSupported() { return true; }
      static Events = { ERROR: 'error' };
      static ErrorTypes = { MEDIA_ERROR: 'mediaError' };
      constructor(config: { xhrSetup?: (xhr: XMLHttpRequest) => void }) {
        const xhr = { setRequestHeader: (name: string, value: string) => {
          if (name === 'Authorization') calls.authorization = value;
        } } as XMLHttpRequest;
        config.xhrSetup?.(xhr);
      }
      on() {}
      loadSource(url: string) { calls.source = url; }
      attachMedia(media: HTMLVideoElement) { calls.media = media; }
      recoverMediaError() {}
      destroy() { calls.destroyed = true; }
    }
    const loadHls = vi.fn(async () => ({ default: FakeHls }));

    const cleanup = await attachHtmlVideoPlayback(
      video,
      attempt('hls-mse', 'https://cdn.example/master.m3u8'),
      { loadHls, loadMpegTs: vi.fn() },
    );

    expect(loadHls).toHaveBeenCalledTimes(1);
    expect(calls).toMatchObject({
      source: 'https://cdn.example/master.m3u8',
      media: video,
      authorization: 'Bearer test',
    });
    cleanup();
    expect(calls.destroyed).toBe(true);
  });

  it('lazily creates mpegts.js only for a planned live MPEG-TS route', async () => {
    const video = document.createElement('video');
    const calls: Record<string, unknown> = {};
    const player = {
      on: vi.fn(),
      attachMediaElement: (media: HTMLVideoElement) => { calls.media = media; },
      load: () => { calls.loaded = true; },
      destroy: () => { calls.destroyed = true; },
    };
    const mpegts = {
      isSupported: () => true,
      Events: { ERROR: 'error' },
      createPlayer: (mediaDataSource: unknown, config: unknown) => {
        calls.mediaDataSource = mediaDataSource;
        calls.config = config;
        return player;
      },
    };
    const loadMpegTs = vi.fn(async () => ({ default: mpegts }));

    const cleanup = await attachHtmlVideoPlayback(
      video,
      attempt('mpeg-ts', 'https://tv.example/live/user/pass/42'),
      { loadHls: vi.fn(), loadMpegTs },
    );

    expect(loadMpegTs).toHaveBeenCalledTimes(1);
    expect(calls).toMatchObject({
      mediaDataSource: { type: 'mpegts', isLive: true, url: 'https://tv.example/live/user/pass/42' },
      media: video,
      loaded: true,
    });
    expect(calls.config).toMatchObject({ headers: { Authorization: 'Bearer test' } });
    cleanup();
    expect(calls.destroyed).toBe(true);
  });
});

describe('HtmlVideoAdapter', () => {
  it('normalizes media events and restores the requested position', async () => {
    const video = document.createElement('video');
    Object.defineProperties(video, {
      duration: { configurable: true, get: () => 300 },
      videoWidth: { configurable: true, get: () => 1920 },
      videoHeight: { configurable: true, get: () => 1080 },
      paused: { configurable: true, get: () => false },
      volume: { configurable: true, writable: true, value: 0.8 },
    });
    const adapter = new HtmlVideoAdapter(video, video.parentElement ?? video, {
      loadHls: vi.fn(),
      loadMpegTs: vi.fn(),
    });
    const states: string[] = [];
    adapter.subscribe(state => states.push(`${state.phase}:${state.position}:${state.hasVideo}`));

    await adapter.load({
      attempt: attempt('native'),
      position: 42,
      tracks: { audioId: null, subtitleId: 'off', audioLanguage: null, subtitleLanguage: null },
      subtitles: [],
    });
    video.dispatchEvent(new Event('loadedmetadata'));
    expect(states.at(-1)).toBe('loading:42:true');
    video.dispatchEvent(new Event('canplay'));
    video.currentTime = 47;
    video.dispatchEvent(new Event('timeupdate'));
    video.dispatchEvent(new Event('playing'));

    expect(video.currentTime).toBe(47);
    expect(states).toContain('playing:42:true');
    expect(states.at(-1)).toBe('playing:47:true');
  });

  it('restores requested audio and subtitle tracks by id or preferred language', async () => {
    const video = document.createElement('video');
    const audio = [
      { id: 'audio-en', label: 'English', language: 'en', enabled: true },
      { id: 'audio-ja', label: 'Japanese', language: 'ja', enabled: false },
    ];
    const text = [
      { label: 'English', language: 'en', mode: 'disabled' },
      { label: 'Svenska', language: 'sv', mode: 'disabled' },
    ];
    Object.defineProperties(video, {
      audioTracks: { configurable: true, value: { 0: audio[0], 1: audio[1], length: 2 } },
      textTracks: { configurable: true, value: text },
      duration: { configurable: true, get: () => 300 },
      videoWidth: { configurable: true, get: () => 1920 },
      videoHeight: { configurable: true, get: () => 1080 },
    });
    const adapter = new HtmlVideoAdapter(video, video, {
      attachPlayback: async () => () => undefined,
    });

    await adapter.load({
      attempt: attempt('native'),
      position: 0,
      tracks: { audioId: 'missing', subtitleId: null, audioLanguage: 'ja', subtitleLanguage: 'sv' },
      subtitles: [
        { id: 'sub-en', lang: 'en', url: '/en.vtt' },
        { id: 'sub-sv', lang: 'sv', url: '/sv.vtt' },
      ],
    });
    video.dispatchEvent(new Event('loadedmetadata'));

    expect(audio.map(track => track.enabled)).toEqual([false, true]);
    expect(text.map(track => track.mode)).toEqual(['disabled', 'showing']);
  });

  it('keeps embedded and appended subtitle identities aligned', async () => {
    const video = document.createElement('video');
    const text = [
      { label: 'Embedded English', language: 'en', mode: 'disabled' },
      { label: 'External English', language: 'en', mode: 'disabled' },
      { label: 'External Svenska', language: 'sv', mode: 'disabled' },
    ];
    Object.defineProperties(video, {
      textTracks: { configurable: true, value: text },
      duration: { configurable: true, get: () => 300 },
      videoWidth: { configurable: true, get: () => 1920 },
      videoHeight: { configurable: true, get: () => 1080 },
    });
    const adapter = new HtmlVideoAdapter(video, video, {
      attachPlayback: async () => () => undefined,
    });
    let subtitleIds: Array<string | number> = [];
    adapter.subscribe(state => { subtitleIds = state.subtitleTracks.map(track => track.id); });

    await adapter.load({
      attempt: attempt('native'),
      position: 0,
      tracks: { audioId: null, subtitleId: 'sub-sv', audioLanguage: null, subtitleLanguage: null },
      subtitles: [
        { id: 'sub-en', lang: 'en', name: 'External English', url: '/en.vtt' },
        { id: 'sub-sv', lang: 'sv', name: 'External Svenska', url: '/sv.vtt' },
      ],
    });
    video.dispatchEvent(new Event('loadedmetadata'));

    expect(text.map(track => track.mode)).toEqual(['disabled', 'disabled', 'showing']);
    expect(subtitleIds).toEqual([0, 'sub-en', 'sub-sv']);
  });

  it('reports a persistent black frame after conservative repeated samples', async () => {
    vi.useFakeTimers();
    const video = document.createElement('video');
    Object.defineProperties(video, {
      duration: { configurable: true, get: () => 300 },
      videoWidth: { configurable: true, get: () => 1920 },
      videoHeight: { configurable: true, get: () => 1080 },
      paused: { configurable: true, get: () => false },
    });
    const adapter = new HtmlVideoAdapter(video, video, {
      attachPlayback: async () => () => undefined,
      detectBlackFrame: vi.fn(async () => true),
    });
    let blackFrameDetected = false;
    adapter.subscribe(state => { blackFrameDetected = state.blackFrameDetected; });
    await adapter.load({
      attempt: attempt('native'),
      position: 0,
      tracks: { audioId: null, subtitleId: 'off', audioLanguage: null, subtitleLanguage: null },
      subtitles: [],
    });

    video.dispatchEvent(new Event('playing'));
    await vi.advanceTimersByTimeAsync(6_000);

    expect(blackFrameDetected).toBe(true);
  });
});

afterEach(() => vi.useRealTimers());
