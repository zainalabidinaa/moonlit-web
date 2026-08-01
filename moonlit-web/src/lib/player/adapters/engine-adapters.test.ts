import { describe, expect, it, vi } from 'vitest';

import type { PlaybackAttempt, PlayerAdapterLoadRequest, PlayerAdapterState } from '@/lib/player/contracts';
import type { MpvEvent } from '@/lib/platform/mpv';
import { attachMediabunnyPlayback, MediabunnyAdapter } from './mediabunny';
import { WebCodecsAdapter, type WebCodecsEngineLike } from './webcodecs';
import { MpvAdapter, type MpvAdapterBridge } from './mpv';

function attempt(adapter: PlaybackAttempt['adapter'], method: PlaybackAttempt['method']): PlaybackAttempt {
  return {
    id: `${method}:fixture`,
    adapter,
    method,
    url: `https://cdn.example/${method}.mkv`,
    sourceType: 'mkv',
    isLive: false,
    reason: method,
    requestHeaders: { Referer: 'https://moonlit.example' },
  };
}

function request(target: PlaybackAttempt, position = 38): PlayerAdapterLoadRequest {
  return {
    attempt: target,
    position,
    tracks: { audioId: 'audio-2', subtitleId: 'sub-3', audioLanguage: 'en', subtitleLanguage: 'sv' },
    subtitles: [],
    signal: new AbortController().signal,
  };
}

describe('attachMediabunnyPlayback', () => {
  it('feeds remuxed fragments into MSE and tears every resource down', async () => {
    const video = document.createElement('video');
    const appended: Uint8Array[] = [];
    const sourceBuffer = {
      updating: false,
      appendBuffer: (chunk: BufferSource) => {
        appended.push(new Uint8Array(chunk as ArrayBuffer));
        sourceBuffer.updating = true;
        setTimeout(() => {
          sourceBuffer.updating = false;
          sourceBufferListener?.();
        }, 0);
      },
      addEventListener: (_event: string, listener: () => void) => { sourceBufferListener = listener; },
    };
    let sourceBufferListener: (() => void) | null = null;
    const mediaSource = {
      readyState: 'open',
      addSourceBuffer: vi.fn(() => sourceBuffer),
      addEventListener: vi.fn(),
      endOfStream: vi.fn(),
    };
    const remuxer = {
      start: vi.fn(async (_url: string, callbacks: {
        onReady?: (mime: string) => void;
        onChunk: (chunk: Uint8Array) => void;
      }) => {
        callbacks.onReady?.('video/mp4; codecs="avc1.640028"');
        callbacks.onChunk(new Uint8Array([1, 2, 3]));
      }),
      destroy: vi.fn(async () => undefined),
    };
    const revokeObjectURL = vi.fn();

    const cleanup = await attachMediabunnyPlayback(video, attempt('mediabunny', 'mediabunny-remux'), {
      createRemuxer: () => remuxer,
      createMediaSource: () => mediaSource,
      createObjectURL: () => 'blob:moonlit-remux',
      revokeObjectURL,
    });
    await vi.waitFor(() => expect(appended).toHaveLength(1));

    expect(video.getAttribute('src')).toBe('blob:moonlit-remux');
    expect(mediaSource.addSourceBuffer).toHaveBeenCalledWith('video/mp4; codecs="avc1.640028"');
    expect([...appended[0]]).toEqual([1, 2, 3]);
    await vi.waitFor(() => expect(mediaSource.endOfStream).toHaveBeenCalledTimes(1));
    await cleanup();
    expect(remuxer.destroy).toHaveBeenCalledTimes(1);
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:moonlit-remux');
  });

  it('normalizes Mediabunny through the media-element adapter without claiming audio switching', () => {
    const video = document.createElement('video');
    const adapter = new MediabunnyAdapter(video, video, {
      attachPlayback: async () => () => undefined,
    });

    expect(adapter.kind).toBe('mediabunny');
    expect(adapter.capabilities.audioTracks).toBe(false);
    expect(adapter.capabilities.subtitleTracks).toBe(true);
  });

  it('forwards default remux failures into normalized adapter error state', async () => {
    const video = document.createElement('video');
    const mediaSource = {
      readyState: 'open',
      addSourceBuffer: vi.fn(),
      addEventListener: vi.fn(),
      endOfStream: vi.fn(),
    };
    const adapter = new MediabunnyAdapter(video, video, {
      createRemuxer: () => ({
        start: async (_url, callbacks) => { callbacks.onError(new Error('remux failed')); },
        destroy: vi.fn(),
      }),
      createMediaSource: () => mediaSource,
      createObjectURL: () => 'blob:failed-remux',
      revokeObjectURL: vi.fn(),
    });
    let error: string | null = null;
    adapter.subscribe(state => { error = state.error; });

    await adapter.load(request(attempt('mediabunny', 'mediabunny-remux')));
    await vi.waitFor(() => expect(error).toBe('remux failed'));
  });
});

describe('WebCodecsAdapter', () => {
  it('maps engine state to the shared contract and restores position', async () => {
    const canvas = document.createElement('canvas');
    let listener: ((state: { duration: number; currentTime: number; isPlaying: boolean; isReady: boolean; ended: boolean; error: string | null }) => void) | null = null;
    const engine: WebCodecsEngineLike = {
      subscribe: callback => { listener = callback; return () => { listener = null; }; },
      load: vi.fn(async () => undefined),
      seekTo: vi.fn(async () => undefined),
      seek: vi.fn(async () => undefined),
      play: vi.fn(),
      pause: vi.fn(),
      destroy: vi.fn(),
    };
    const adapter = new WebCodecsAdapter(canvas, canvas, () => engine);
    const phases: string[] = [];
    let latestState: PlayerAdapterState | null = null;
    adapter.subscribe(state => {
      latestState = state;
      phases.push(`${state.phase}:${state.position}:${state.hasVideo}`);
    });

    await adapter.load(request(attempt('webcodecs', 'webcodecs'), 51));
    listener?.({ duration: 120, currentTime: 51, isPlaying: true, isReady: true, ended: false, error: null });

    expect(engine.load).toHaveBeenCalledWith('https://cdn.example/webcodecs.mkv', canvas);
    expect(engine.seekTo).toHaveBeenCalledWith(51);
    expect(phases.at(-1)).toBe('playing:51:true');
    listener?.({ duration: 120, currentTime: 120, isPlaying: false, isReady: true, ended: true, error: null });
    expect(phases.at(-1)).toBe('ended:120:true');
    expect(adapter.capabilities.volume).toBe(false);
    expect(adapter.capabilities.subtitleTracks).toBe(false);
    Object.defineProperty(canvas, 'requestFullscreen', { configurable: true, value: vi.fn(async () => undefined) });
    await adapter.setFullscreen(true);
    expect(latestState?.fullscreen).toBe(true);
  });

  it('does not start a WebCodecs engine after an aborted load resolves', async () => {
    let resolveLoad: (() => void) | null = null;
    const engine: WebCodecsEngineLike = {
      subscribe: () => () => undefined,
      load: vi.fn(() => new Promise<void>(resolve => { resolveLoad = resolve; })),
      seekTo: vi.fn(async () => undefined),
      seek: vi.fn(async () => undefined),
      play: vi.fn(),
      pause: vi.fn(),
      destroy: vi.fn(),
    };
    const canvas = document.createElement('canvas');
    const adapter = new WebCodecsAdapter(canvas, canvas, () => engine);
    const controller = new AbortController();
    const load = adapter.load({ ...request(attempt('webcodecs', 'webcodecs')), signal: controller.signal });

    controller.abort();
    adapter.destroy();
    resolveLoad?.();
    await load;

    expect(engine.play).not.toHaveBeenCalled();
  });
});

describe('MpvAdapter', () => {
  it('normalizes Tauri IPC events and preserves launch headers and position', async () => {
    let eventListener: ((event: MpvEvent) => void) | null = null;
    const bridge: MpvAdapterBridge = {
      start: vi.fn(async () => undefined),
      stop: vi.fn(async () => undefined),
      setProp: vi.fn(async () => undefined),
      getProp: vi.fn(async () => []),
      command: vi.fn(async () => undefined),
      subAdd: vi.fn(async () => undefined),
      listen: vi.fn(async listener => { eventListener = listener; return () => { eventListener = null; }; }),
      setGeometry: vi.fn(async () => undefined),
      setFullscreen: vi.fn(async () => undefined),
      setPictureInPicture: vi.fn(async () => undefined),
    };
    const adapter = new MpvAdapter(bridge);
    const phases: string[] = [];
    let latestState: PlayerAdapterState | null = null;
    adapter.subscribe(state => {
      latestState = state;
      phases.push(`${state.phase}:${state.position}`);
    });

    expect(adapter.capabilities).toMatchObject({
      seekPreview: false,
      screenshot: false,
      anime4k: false,
    });

    const loadRequest: PlayerAdapterLoadRequest = {
      ...request(attempt('mpv', 'mpv'), 75),
      tracks: { audioId: 2, subtitleId: 3, audioLanguage: 'en', subtitleLanguage: 'sv' },
      subtitles: [{
        id: '3',
        lang: 'sv',
        name: 'Svenska',
        url: '/api/stremio/vtt?url=https%3A%2F%2Fsubs.example%2Fepisode.srt',
      }],
    };
    await adapter.load(loadRequest);
    eventListener?.({ event: 'file-loaded' });
    eventListener?.({ event: 'property-change', name: 'duration', data: 600 });
    eventListener?.({ event: 'property-change', name: 'time-pos', data: 80 });
    eventListener?.({ event: 'property-change', name: 'pause', data: false });

    expect(bridge.start).toHaveBeenCalledWith({
      url: loadRequest.attempt.url,
      startAtSec: 75,
      headers: { Referer: 'https://moonlit.example' },
    });
    expect(bridge.setGeometry).toHaveBeenCalledWith(expect.objectContaining({
      cssLeft: 0,
      cssTop: 0,
      cssWidth: window.innerWidth,
      cssHeight: window.innerHeight,
    }));
    expect(bridge.setProp).toHaveBeenCalledWith('aid', 2);
    expect(bridge.setProp).toHaveBeenCalledWith('sid', 3);
    expect(bridge.setProp).toHaveBeenCalledWith('sub-font-size', 32);
    expect(bridge.subAdd).toHaveBeenCalledWith('https://subs.example/episode.srt', {
      title: 'Svenska',
      lang: 'sv',
      select: true,
    });
    expect(typeof adapter.updateSubtitles).toBe('function');
    await adapter.updateSubtitles?.(
      [{ id: 'late-en', lang: 'en', name: 'English', url: 'https://subs.example/late.vtt' }],
      { audioId: null, subtitleId: 'late-en', audioLanguage: null, subtitleLanguage: 'en' },
    );
    expect(bridge.subAdd).toHaveBeenCalledWith('https://subs.example/late.vtt', {
      title: 'English',
      lang: 'en',
      select: true,
    });
    expect(phases.at(-1)).toBe('playing:80');
    eventListener?.({ event: 'property-change', name: 'track-list', data: [
      { id: 1, type: 'audio', title: 'Audio only', selected: true },
    ] });
    expect(latestState?.hasVideo).toBe(false);
    await adapter.setFullscreen(true);
    await adapter.setPictureInPicture(true);
    expect(latestState?.fullscreen).toBe(true);
    expect(latestState?.pictureInPicture).toBe(true);
    await adapter.selectAudioTrack(2);
    await adapter.selectSubtitleTrack('off');
    expect(bridge.setProp).toHaveBeenCalledWith('aid', 2);
    expect(bridge.setProp).toHaveBeenCalledWith('sid', 'no');
  });

  it('does not start MPV after an aborted listener setup resolves', async () => {
    let resolveListen: ((unlisten: () => void) => void) | null = null;
    const bridge: MpvAdapterBridge = {
      start: vi.fn(async () => undefined),
      stop: vi.fn(async () => undefined),
      setProp: vi.fn(async () => undefined),
      getProp: vi.fn(async () => []),
      command: vi.fn(async () => undefined),
      subAdd: vi.fn(async () => undefined),
      listen: vi.fn(() => new Promise(resolve => { resolveListen = resolve; })),
      setFullscreen: vi.fn(async () => undefined),
      setPictureInPicture: vi.fn(async () => undefined),
    };
    const adapter = new MpvAdapter(bridge);
    const controller = new AbortController();
    const load = adapter.load({ ...request(attempt('mpv', 'mpv')), signal: controller.signal });

    controller.abort();
    const destroy = adapter.destroy();
    resolveListen?.(() => undefined);
    await load;
    await destroy;

    expect(bridge.start).not.toHaveBeenCalled();
  });

  it('stops a late MPV start that resolves after cancellation', async () => {
    let resolveStart: (() => void) | null = null;
    const bridge: MpvAdapterBridge = {
      start: vi.fn(() => new Promise<void>(resolve => { resolveStart = resolve; })),
      stop: vi.fn(async () => undefined),
      setProp: vi.fn(async () => undefined),
      getProp: vi.fn(async () => []),
      command: vi.fn(async () => undefined),
      subAdd: vi.fn(async () => undefined),
      listen: vi.fn(async () => () => undefined),
      setFullscreen: vi.fn(async () => undefined),
      setPictureInPicture: vi.fn(async () => undefined),
    };
    const adapter = new MpvAdapter(bridge);
    const controller = new AbortController();
    const load = adapter.load({ ...request(attempt('mpv', 'mpv')), signal: controller.signal });
    await vi.waitFor(() => expect(bridge.start).toHaveBeenCalledTimes(1));

    controller.abort();
    const destroy = adapter.destroy();
    resolveStart?.();
    await load;
    await destroy;

    expect(bridge.stop).toHaveBeenCalledTimes(2);
  });
});
