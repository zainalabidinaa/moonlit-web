import { afterEach, describe, expect, it, vi } from 'vitest';

import type { PlaybackAttempt, PlayerAdapterState } from '@/lib/player/contracts';
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

  it('sends source headers only to exact-origin HLS requests', async () => {
    const video = document.createElement('video');
    let xhrSetup: ((xhr: XMLHttpRequest, url: string) => void) | undefined;
    class FakeHls {
      static isSupported() { return true; }
      static Events = { ERROR: 'error' };
      static ErrorTypes = { MEDIA_ERROR: 'mediaError' };
      constructor(config: { xhrSetup?: (xhr: XMLHttpRequest, url: string) => void }) {
        xhrSetup = config.xhrSetup;
      }
      on() {}
      loadSource() {}
      attachMedia() {}
      recoverMediaError() {}
      destroy() {}
    }
    await attachHtmlVideoPlayback(
      video,
      attempt('hls-mse', 'https://cdn.example/master.m3u8'),
      { loadHls: async () => ({ default: FakeHls }), loadMpegTs: vi.fn() },
    );
    const sameOrigin = vi.fn();
    const crossOrigin = vi.fn();

    xhrSetup?.({ setRequestHeader: sameOrigin } as unknown as XMLHttpRequest, 'https://cdn.example/segment.ts');
    xhrSetup?.({ setRequestHeader: crossOrigin } as unknown as XMLHttpRequest, 'https://evil.example/segment.ts');

    expect(sameOrigin).toHaveBeenCalledWith('Authorization', 'Bearer test');
    expect(crossOrigin).not.toHaveBeenCalled();
  });

  it('does not fall back to headerless native HLS for a protected manifest', async () => {
    const video = document.createElement('video');
    vi.spyOn(video, 'canPlayType').mockReturnValue('probably');
    class UnsupportedHls {
      static isSupported() { return false; }
      static Events = { ERROR: 'error' };
      static ErrorTypes = { MEDIA_ERROR: 'mediaError' };
    }

    await expect(attachHtmlVideoPlayback(
      video,
      attempt('hls-mse', 'https://cdn.example/protected.m3u8'),
      { loadHls: async () => ({ default: UnsupportedHls as never }), loadMpegTs: vi.fn() },
    )).rejects.toThrow(/protected HLS/i);
    expect(video.hasAttribute('src')).toBe(false);
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
  it('reflects native fullscreen and picture-in-picture exits in adapter state', () => {
    const video = document.createElement('video');
    const root = document.createElement('div');
    let fullscreenElement: Element | null = root;
    let pictureInPictureElement: Element | null = video;
    Object.defineProperty(document, 'fullscreenElement', { configurable: true, get: () => fullscreenElement });
    Object.defineProperty(document, 'pictureInPictureElement', { configurable: true, get: () => pictureInPictureElement });
    const adapter = new HtmlVideoAdapter(video, root, { attachPlayback: async () => () => undefined });
    let latest: PlayerAdapterState | null = null;
    adapter.subscribe(state => { latest = state; });

    document.dispatchEvent(new Event('fullscreenchange'));
    video.dispatchEvent(new Event('enterpictureinpicture'));
    expect(latest?.fullscreen).toBe(true);
    expect(latest?.pictureInPicture).toBe(true);

    fullscreenElement = null;
    pictureInPictureElement = null;
    document.dispatchEvent(new Event('fullscreenchange'));
    video.dispatchEvent(new Event('leavepictureinpicture'));
    expect(latest?.fullscreen).toBe(false);
    expect(latest?.pictureInPicture).toBe(false);
    delete (document as Document & { fullscreenElement?: Element | null }).fullscreenElement;
    delete (document as Document & { pictureInPictureElement?: Element | null }).pictureInPictureElement;
  });

  it('lazily exposes and selects HLS.js audio renditions when native audioTracks are absent', async () => {
    const video = document.createElement('video');
    class FakeHls {
      static instance: FakeHls | null = null;
      static isSupported() { return true; }
      static Events = { ERROR: 'error' };
      static ErrorTypes = { MEDIA_ERROR: 'mediaError' };
      audioTracks = [
        { id: 10, name: 'English', lang: 'en', audioCodec: 'mp4a.40.2' },
        { id: 20, name: 'Japanese', lang: 'ja', audioCodec: 'mp4a.40.2' },
      ];
      audioTrack = 0;
      constructor() { FakeHls.instance = this; }
      on() {}
      loadSource() {}
      attachMedia() {}
      recoverMediaError() {}
      destroy() {}
    }
    const adapter = new HtmlVideoAdapter(video, video, {
      loadHls: async () => ({ default: FakeHls }),
      loadMpegTs: vi.fn(),
    });
    let latestTracks: Array<{ id: string | number; language?: string }> = [];
    adapter.subscribe(state => { latestTracks = state.audioTracks; });

    await adapter.load({
      attempt: attempt('hls-mse', 'https://cdn.example/master.m3u8'),
      position: 0,
      tracks: { audioId: null, subtitleId: 'off', audioLanguage: null, subtitleLanguage: null },
      subtitles: [],
      signal: new AbortController().signal,
    });
    adapter.probeAudioTracks?.();

    expect(adapter.capabilities.audioTracks).toBe(true);
    expect(latestTracks).toEqual([
      expect.objectContaining({ id: 'hls:10', language: 'en' }),
      expect.objectContaining({ id: 'hls:20', language: 'ja' }),
    ]);
    adapter.selectAudioTrack('hls:20');
    expect(FakeHls.instance?.audioTrack).toBe(1);
  });

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
      signal: new AbortController().signal,
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
      signal: new AbortController().signal,
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
      signal: new AbortController().signal,
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
      signal: new AbortController().signal,
    });

    video.dispatchEvent(new Event('playing'));
    await vi.advanceTimersByTimeAsync(6_000);

    expect(blackFrameDetected).toBe(true);
  });

  it('appends subtitles delivered after playback is ready without reloading transport', async () => {
    const video = document.createElement('video');
    const attachPlayback = vi.fn(async () => () => undefined);
    const adapter = new HtmlVideoAdapter(video, video, { attachPlayback });
    await adapter.load({
      attempt: attempt('native'),
      position: 0,
      tracks: { audioId: null, subtitleId: null, audioLanguage: null, subtitleLanguage: 'sv' },
      subtitles: [],
      signal: new AbortController().signal,
    });

    expect(typeof adapter.updateSubtitles).toBe('function');
    await adapter.updateSubtitles?.(
      [{ id: 'late-sv', lang: 'sv', name: 'Svenska', url: '/late-sv.vtt' }],
      { audioId: null, subtitleId: null, audioLanguage: null, subtitleLanguage: 'sv' },
    );

    expect(attachPlayback).toHaveBeenCalledTimes(1);
    expect(video.querySelector('track')?.dataset.moonlitTrackId).toBe('late-sv');
    expect(video.querySelector('track')).toHaveAttribute('src', '/late-sv.vtt');
  });

  it('bounds direct-media preview work to one request and caches completed frames', async () => {
    const pending: Array<{ signal?: AbortSignal; resolve: (value: { position: number; imageUrl: string }) => void }> = [];
    const createSeekPreview = vi.fn((_url: string, _position: number, signal?: AbortSignal) => new Promise(resolve => {
      pending.push({ signal, resolve });
    }));
    const video = document.createElement('video');
    const adapter = new HtmlVideoAdapter(video, video, {
      attachPlayback: async () => () => undefined,
      createSeekPreview,
    });
    await adapter.load({
      attempt: { ...attempt('native'), requestHeaders: undefined },
      position: 0,
      tracks: { audioId: null, subtitleId: 'off', audioLanguage: null, subtitleLanguage: null },
      subtitles: [],
      signal: new AbortController().signal,
    });

    void adapter.requestSeekPreview(10);
    const second = adapter.requestSeekPreview(20);
    expect(pending[0].signal?.aborted).toBe(true);
    pending[1].resolve({ position: 20, imageUrl: 'data:image/jpeg;base64,twenty' });
    await second;
    await adapter.requestSeekPreview(20);

    expect(createSeekPreview).toHaveBeenCalledTimes(2);
    await adapter.destroy();
    expect(pending[1].signal?.aborted).toBe(true);
  });

  it('destroys promptly when transport attach never settles and cleans a late result', async () => {
    const video = document.createElement('video');
    const cleanup = vi.fn();
    let resolveAttach: ((value: () => void) => void) | null = null;
    const adapter = new HtmlVideoAdapter(video, video, {
      attachPlayback: () => new Promise(resolve => { resolveAttach = resolve; }),
    });
    const controller = new AbortController();
    const load = adapter.load({
      attempt: attempt('native'),
      position: 0,
      tracks: { audioId: null, subtitleId: null, audioLanguage: null, subtitleLanguage: null },
      subtitles: [],
      signal: controller.signal,
    });
    await Promise.resolve();
    expect(resolveAttach).not.toBeNull();

    controller.abort();
    const destroy = adapter.destroy();
    let destroySettled = false;
    void destroy.then(() => { destroySettled = true; });
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(destroySettled).toBe(true);
    expect(cleanup).not.toHaveBeenCalled();
    resolveAttach?.(cleanup);
    await load;

    expect(cleanup).toHaveBeenCalledTimes(1);
  });
});

afterEach(() => vi.useRealTimers());
