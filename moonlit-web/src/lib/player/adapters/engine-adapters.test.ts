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
  it('reflects native fullscreen changes including Escape exits', () => {
    const root = document.createElement('div');
    let fullscreenElement: Element | null = root;
    Object.defineProperty(document, 'fullscreenElement', { configurable: true, get: () => fullscreenElement });
    const adapter = new WebCodecsAdapter(document.createElement('canvas'), root, () => ({
      subscribe: () => () => undefined,
      load: vi.fn(async () => undefined), seekTo: vi.fn(async () => undefined), seek: vi.fn(async () => undefined),
      play: vi.fn(), pause: vi.fn(), destroy: vi.fn(),
    }));
    let latest: PlayerAdapterState | null = null;
    adapter.subscribe(state => { latest = state; });

    document.dispatchEvent(new Event('fullscreenchange'));
    expect(latest?.fullscreen).toBe(true);
    fullscreenElement = null;
    document.dispatchEvent(new Event('fullscreenchange'));
    expect(latest?.fullscreen).toBe(false);
    delete (document as Document & { fullscreenElement?: Element | null }).fullscreenElement;
  });

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

  it('re-cleans resources created by a late load without clobbering a replacement on the shared canvas', async () => {
    const canvas = document.createElement('canvas');
    canvas.width = 300;
    canvas.height = 150;
    let resolveOldLoad: (() => void) | null = null;
    let oldResourceOpen = false;
    const oldDestroy = vi.fn(() => { oldResourceOpen = false; });
    const oldEngine: WebCodecsEngineLike = {
      subscribe: () => () => undefined,
      load: vi.fn(async (_url, target) => {
        await new Promise<void>(resolve => { resolveOldLoad = resolve; });
        oldResourceOpen = true;
        target.width = 1920;
        target.height = 1080;
      }),
      seekTo: vi.fn(async () => undefined),
      seek: vi.fn(async () => undefined),
      play: vi.fn(),
      pause: vi.fn(),
      destroy: oldDestroy,
    };
    const replacementEngine: WebCodecsEngineLike = {
      subscribe: () => () => undefined,
      load: vi.fn(async (_url, target) => {
        target.width = 640;
        target.height = 360;
      }),
      seekTo: vi.fn(async () => undefined),
      seek: vi.fn(async () => undefined),
      play: vi.fn(),
      pause: vi.fn(),
      destroy: vi.fn(),
    };
    const oldAdapter = new WebCodecsAdapter(canvas, canvas, () => oldEngine);
    const oldLoad = oldAdapter.load(request(attempt('webcodecs', 'webcodecs')));
    await vi.waitFor(() => expect(oldEngine.load).toHaveBeenCalledTimes(1));

    await oldAdapter.destroy();
    const replacement = new WebCodecsAdapter(canvas, canvas, () => replacementEngine);
    await replacement.load({
      ...request(attempt('webcodecs', 'webcodecs')),
      attempt: { ...attempt('webcodecs', 'webcodecs'), url: 'https://cdn.example/replacement.mkv' },
    });
    expect([canvas.width, canvas.height]).toEqual([640, 360]);

    resolveOldLoad?.();
    await oldLoad;

    expect(oldDestroy).toHaveBeenCalledTimes(2);
    expect(oldResourceOpen).toBe(false);
    expect([canvas.width, canvas.height]).toEqual([640, 360]);
  });

  it('does not play WebCodecs after cancellation during resume seeking', async () => {
    let resolveSeek: (() => void) | null = null;
    const engine: WebCodecsEngineLike = {
      subscribe: () => () => undefined,
      load: vi.fn(async () => undefined),
      seekTo: vi.fn(() => new Promise<void>(resolve => { resolveSeek = resolve; })),
      seek: vi.fn(async () => undefined),
      play: vi.fn(),
      pause: vi.fn(),
      destroy: vi.fn(),
    };
    const adapter = new WebCodecsAdapter(document.createElement('canvas'), document.createElement('div'), () => engine);
    const controller = new AbortController();
    const load = adapter.load({ ...request(attempt('webcodecs', 'webcodecs'), 33), signal: controller.signal });
    await vi.waitFor(() => expect(engine.seekTo).toHaveBeenCalledWith(33));

    controller.abort();
    adapter.destroy();
    resolveSeek?.();
    await load;

    expect(engine.play).not.toHaveBeenCalled();
  });
});

describe('MpvAdapter', () => {
  it('reflects native window state and clears PiP/fullscreen during destroy', async () => {
    let windowListener: ((state: { fullscreen: boolean; pictureInPicture: boolean }) => void) | null = null;
    const bridge: MpvAdapterBridge = {
      start: vi.fn(async () => undefined), stop: vi.fn(async () => undefined),
      setProp: vi.fn(async () => undefined), getProp: vi.fn(async () => []), command: vi.fn(async () => undefined),
      subAdd: vi.fn(async () => undefined), listen: vi.fn(async () => () => undefined),
      listenWindowState: vi.fn(async listener => { windowListener = listener; return () => { windowListener = null; }; }),
      setFullscreen: vi.fn(async () => undefined), setPictureInPicture: vi.fn(async () => undefined),
    };
    const adapter = new MpvAdapter(bridge);
    let latest: PlayerAdapterState | null = null;
    adapter.subscribe(state => { latest = state; });
    await adapter.load(request(attempt('mpv', 'mpv')));

    windowListener?.({ fullscreen: true, pictureInPicture: true });
    expect(latest?.fullscreen).toBe(true);
    expect(latest?.pictureInPicture).toBe(true);
    windowListener?.({ fullscreen: false, pictureInPicture: false });
    expect(latest?.fullscreen).toBe(false);
    expect(latest?.pictureInPicture).toBe(false);

    await adapter.setPictureInPicture(true);
    await adapter.setFullscreen(true);
    await adapter.destroy();
    expect(bridge.setPictureInPicture).toHaveBeenLastCalledWith(false);
    expect(bridge.setFullscreen).toHaveBeenLastCalledWith(false);
    expect(windowListener).toBeNull();
  });

  it('maps a digit-only late app subtitle id before interpreting native sid values', async () => {
    let trackList: unknown[] = [];
    const setProp = vi.fn(async () => undefined);
    const bridge: MpvAdapterBridge = {
      start: vi.fn(async () => undefined),
      stop: vi.fn(async () => undefined),
      setProp,
      getProp: vi.fn(async name => name === 'track-list' ? trackList : undefined),
      command: vi.fn(async () => undefined),
      subAdd: vi.fn(async (url, options) => {
        trackList = [{
          id: 42,
          type: 'sub',
          title: options?.title,
          lang: options?.lang,
          external: true,
          'external-filename': url,
        }];
      }),
      listen: vi.fn(async () => () => undefined),
      setFullscreen: vi.fn(async () => undefined),
      setPictureInPicture: vi.fn(async () => undefined),
    };
    const adapter = new MpvAdapter(bridge);
    let subtitleIds: Array<string | number> = [];
    adapter.subscribe(state => { subtitleIds = state.subtitleTracks.map(track => track.id); });
    await adapter.load({ ...request(attempt('mpv', 'mpv')), tracks: { ...request(attempt('mpv', 'mpv')).tracks, subtitleId: 'off' } });

    await adapter.updateSubtitles?.(
      [{ id: '17', lang: 'en', name: 'English signs', url: 'https://subs.example/signs.vtt' }],
      { audioId: null, subtitleId: '17', audioLanguage: null, subtitleLanguage: 'en' },
    );
    await adapter.selectSubtitleTrack('17');

    expect(setProp).toHaveBeenCalledWith('sid', 42);
    expect(setProp).not.toHaveBeenCalledWith('sid', 17);
    expect(subtitleIds).toContain('17');
  });

  it('applies a subtitle click made before app-to-native reconciliation completes', async () => {
    let resolveSubAdd: (() => void) | null = null;
    const setProp = vi.fn(async () => undefined);
    const bridge: MpvAdapterBridge = {
      start: vi.fn(async () => undefined),
      stop: vi.fn(async () => undefined),
      setProp,
      getProp: vi.fn(async name => name === 'track-list' ? [{
        id: 29,
        type: 'sub',
        title: 'Late signs',
        external: true,
        'external-filename': 'https://subs.example/late-signs.vtt',
      }] : undefined),
      command: vi.fn(async () => undefined),
      subAdd: vi.fn(() => new Promise<void>(resolve => { resolveSubAdd = resolve; })),
      listen: vi.fn(async () => () => undefined),
      setFullscreen: vi.fn(async () => undefined),
      setPictureInPicture: vi.fn(async () => undefined),
    };
    const adapter = new MpvAdapter(bridge);
    await adapter.load({
      ...request(attempt('mpv', 'mpv')),
      tracks: { audioId: null, subtitleId: 'off', audioLanguage: null, subtitleLanguage: null },
    });
    const update = adapter.updateSubtitles?.(
      [{ id: 'late-signs', lang: '', name: 'Late signs', url: 'https://subs.example/late-signs.vtt' }],
      { audioId: null, subtitleId: null, audioLanguage: null, subtitleLanguage: null },
    );
    await vi.waitFor(() => expect(bridge.subAdd).toHaveBeenCalledTimes(1));

    await adapter.selectSubtitleTrack('late-signs');
    expect(setProp).not.toHaveBeenCalledWith('sid', 29);
    resolveSubAdd?.();
    await update;

    expect(setProp).toHaveBeenCalledWith('sid', 29);
  });

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

  it('does not let an old late start stop a replacement on the shared MPV bridge', async () => {
    let resolveOldStart: (() => void) | null = null;
    let activeUrl: string | null = null;
    let startCount = 0;
    const bridge: MpvAdapterBridge = {
      start: vi.fn(async ({ url }) => {
        startCount += 1;
        activeUrl = url;
        if (startCount === 1) await new Promise<void>(resolve => { resolveOldStart = resolve; });
      }),
      stop: vi.fn(async () => { activeUrl = null; }),
      setProp: vi.fn(async () => undefined),
      getProp: vi.fn(async () => []),
      command: vi.fn(async () => undefined),
      subAdd: vi.fn(async () => undefined),
      listen: vi.fn(async () => () => undefined),
      setFullscreen: vi.fn(async () => undefined),
      setPictureInPicture: vi.fn(async () => undefined),
    };
    const oldAdapter = new MpvAdapter(bridge);
    const oldController = new AbortController();
    const oldLoad = oldAdapter.load({
      ...request(attempt('mpv', 'mpv')),
      attempt: { ...attempt('mpv', 'mpv'), url: 'https://cdn.example/old.mkv' },
      signal: oldController.signal,
    });
    await vi.waitFor(() => expect(activeUrl).toBe('https://cdn.example/old.mkv'));

    oldController.abort();
    await oldAdapter.destroy();
    const replacement = new MpvAdapter(bridge);
    await replacement.load({
      ...request(attempt('mpv', 'mpv')),
      attempt: { ...attempt('mpv', 'mpv'), url: 'https://cdn.example/new.mkv' },
    });
    expect(activeUrl).toBe('https://cdn.example/new.mkv');

    resolveOldStart?.();
    await oldLoad;

    expect(activeUrl).toBe('https://cdn.example/new.mkv');
  });

  it('does not continue MPV setup after cancellation during track restoration', async () => {
    let resolveAudioRestore: (() => void) | null = null;
    const setProp = vi.fn((name: string) => name === 'aid'
      ? new Promise<void>(resolve => { resolveAudioRestore = resolve; })
      : Promise.resolve());
    const bridge: MpvAdapterBridge = {
      start: vi.fn(async () => undefined),
      stop: vi.fn(async () => undefined),
      setProp,
      getProp: vi.fn(async () => []),
      command: vi.fn(async () => undefined),
      subAdd: vi.fn(async () => undefined),
      listen: vi.fn(async () => () => undefined),
      setGeometry: vi.fn(async () => undefined),
      setFullscreen: vi.fn(async () => undefined),
      setPictureInPicture: vi.fn(async () => undefined),
    };
    const adapter = new MpvAdapter(bridge);
    const controller = new AbortController();
    const load = adapter.load({
      ...request(attempt('mpv', 'mpv')),
      tracks: { audioId: 2, subtitleId: 3, audioLanguage: null, subtitleLanguage: null },
      signal: controller.signal,
    });
    await vi.waitFor(() => expect(setProp).toHaveBeenCalledWith('aid', 2));

    controller.abort();
    const destroy = adapter.destroy();
    resolveAudioRestore?.();
    await load;
    await destroy;

    expect(setProp).not.toHaveBeenCalledWith('sid', expect.anything());
    expect(bridge.setGeometry).not.toHaveBeenCalled();
    expect(bridge.subAdd).not.toHaveBeenCalled();
  });
});
