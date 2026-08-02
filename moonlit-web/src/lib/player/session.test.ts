import { describe, expect, it, vi } from 'vitest';

import type { SubtitleItem } from '@/lib/stremio';
import type {
  PlaybackAttempt,
  PlaybackPlan,
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerAdapterLoadRequest,
  PlayerAdapterState,
  PlayerTrackSelection,
} from './contracts';
import { normalizeAdapterState } from './contracts';
import { PlayerSession } from './session';

const allCapabilities: PlayerAdapterCapabilities = {
  seek: true,
  volume: true,
  playbackRate: true,
  fullscreen: true,
  pictureInPicture: true,
  remotePlayback: false,
  audioTracks: true,
  subtitleTracks: true,
  seekPreview: true,
  screenshot: false,
  anime4k: false,
};

class FakeAdapter implements PlayerAdapter {
  readonly kind = 'html-video' as const;
  readonly loads: PlayerAdapterLoadRequest[] = [];
  readonly playbackRates: number[] = [];
  readonly subtitleUpdates: SubtitleItem[][] = [];
  probeCount = 0;
  destroyed = false;
  destroyCount = 0;
  private listeners = new Set<(state: PlayerAdapterState) => void>();

  constructor(
    readonly capabilities = allCapabilities,
    private readonly loadBehavior?: () => Promise<void>,
    private readonly destroyBehavior?: () => Promise<void>,
  ) {}

  async load(request: PlayerAdapterLoadRequest) {
    this.loads.push(request);
    await this.loadBehavior?.();
  }
  play() {}
  pause() {}
  seek() {}
  setVolume() {}
  setMuted() {}
  setPlaybackRate(rate: number) { this.playbackRates.push(rate); }
  setFullscreen() {}
  setPictureInPicture() {}
  selectAudioTrack() {}
  selectSubtitleTrack() {}
  updateSubtitles(items: SubtitleItem[]) { this.subtitleUpdates.push(items); }
  probeAudioTracks() { this.probeCount += 1; }
  subscribe(listener: (state: PlayerAdapterState) => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
  async destroy() {
    this.destroyed = true;
    this.destroyCount += 1;
    await this.destroyBehavior?.();
  }

  emit(input: Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'>) {
    const state = normalizeAdapterState(input);
    this.listeners.forEach(listener => listener(state));
  }
}

function playbackAttempt(id: string): PlaybackAttempt {
  return {
    id,
    adapter: 'html-video',
    method: 'native',
    url: `https://cdn.example/${id}.mp4`,
    sourceType: 'video',
    isLive: false,
    reason: id,
  };
}

function playbackPlan(attempts = [playbackAttempt('primary'), playbackAttempt('fallback')]): PlaybackPlan {
  return {
    outcome: 'play-here',
    label: 'Plays here',
    detail: 'test plan',
    stream: { url: attempts[0]?.url, title: 'Test movie' },
    attempts,
  };
}

const initialTracks: PlayerTrackSelection = {
  audioId: 'audio-en',
  subtitleId: 'sub-sv',
  audioLanguage: 'en',
  subtitleLanguage: 'sv',
};

const subtitles: SubtitleItem[] = [{ id: 'sub-sv', lang: 'sv', url: '/subs/sv.vtt' }];

describe('PlayerSession', () => {
  it('loads the first route with the launch position and preferred tracks', async () => {
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      createAdapter: () => {
        const adapter = new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });

    await session.start({ position: 42, tracks: initialTracks, subtitles });

    expect(adapters[0].loads[0]).toMatchObject({
      attempt: playbackAttempt('primary'),
      position: 42,
      tracks: initialTracks,
      subtitles,
    });
    expect(adapters[0].loads[0].signal).toBeInstanceOf(AbortSignal);
    expect(session.getState()).toMatchObject({ phase: 'loading', attemptIndex: 0, fallbackCount: 0 });
  });

  it('preserves the latest position and selected tracks when an adapter fails', async () => {
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      createAdapter: () => {
        const adapter = new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    await session.start({ position: 10, tracks: initialTracks, subtitles });

    adapters[0].emit({
      phase: 'playing',
      position: 73,
      duration: 600,
      selectedAudioId: 'audio-es',
      selectedSubtitleId: 'sub-en',
      audioTracks: [{ id: 'audio-es', kind: 'audio', label: 'Spanish', language: 'es', selected: true }],
      subtitleTracks: [{ id: 'sub-en', kind: 'subtitles', label: 'English', language: 'en', selected: true }],
    });
    adapters[0].emit({ phase: 'error', position: 73, duration: 600, error: 'decoder failed' });

    await vi.waitFor(() => expect(adapters).toHaveLength(2));
    expect(adapters[0].destroyed).toBe(true);
    expect(adapters[1].loads[0]).toMatchObject({
      attempt: playbackAttempt('fallback'),
      position: 73,
      tracks: {
        audioId: null,
        subtitleId: null,
        audioLanguage: 'es',
        subtitleLanguage: 'en',
      },
    });
    expect(session.getState()).toMatchObject({ attemptIndex: 1, fallbackCount: 1, fallbackReason: 'decoder failed' });
  });

  it('snapshots a neutral identity before an async native selection event can arrive', async () => {
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      createAdapter: () => {
        const adapter = new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    await session.start({ position: 0, tracks: initialTracks, subtitles: [] });
    adapters[0].emit({
      phase: 'playing',
      position: 20,
      duration: 100,
      selectedAudioId: 1,
      audioTracks: [
        { id: 1, kind: 'audio', label: 'Spanish commentary', language: 'es', selected: true },
        { id: 2, kind: 'audio', label: 'Spanish stereo', language: 'es', selected: false },
      ],
    });

    session.selectAudioTrack(2);
    adapters[0].emit({
      phase: 'playing',
      position: 20,
      duration: 100,
      selectedAudioId: 1,
      audioTracks: [
        { id: 1, kind: 'audio', label: 'Spanish commentary', language: 'es', selected: true },
        { id: 2, kind: 'audio', label: 'Spanish stereo', language: 'es', selected: false },
      ],
    });
    adapters[0].emit({ phase: 'error', position: 20, error: 'native switch failed' });

    await vi.waitFor(() => expect(adapters).toHaveLength(2));
    expect(adapters[1].loads[0].tracks).toMatchObject({
      audioId: null,
      audioLanguage: 'es',
      audioIdentity: {
        kind: 'audio',
        language: 'es',
        label: 'Spanish stereo',
        ordinal: 1,
      },
    });
  });

  it('ports a language-less external subtitle by source identity, never local id', async () => {
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      createAdapter: () => {
        const adapter = new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    await session.start({ position: 0, tracks: initialTracks, subtitles: [] });
    adapters[0].emit({
      phase: 'playing',
      selectedSubtitleId: 'local-9',
      subtitleTracks: [{
        id: 'local-9',
        kind: 'subtitles',
        label: 'Signs',
        sourceUrl: 'https://subs.example/signs.vtt',
        embedded: false,
        selected: true,
      }],
    });

    adapters[0].emit({ phase: 'error', error: 'fallback' });

    await vi.waitFor(() => expect(adapters).toHaveLength(2));
    expect(adapters[1].loads[0].tracks).toMatchObject({
      subtitleId: null,
      subtitleIdentity: {
        kind: 'subtitles',
        language: null,
        label: 'Signs',
        sourceUrl: 'https://subs.example/signs.vtt',
        ordinal: 0,
      },
    });
  });

  it('falls back after repeated buffering but not on the first two recoveries', async () => {
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      repeatedBufferingLimit: 3,
      createAdapter: () => {
        const adapter = new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    await session.start({ position: 0, tracks: initialTracks, subtitles: [] });

    adapters[0].emit({ phase: 'buffering', position: 20, duration: 100 });
    adapters[0].emit({ phase: 'playing', position: 21, duration: 100 });
    adapters[0].emit({ phase: 'buffering', position: 22, duration: 100 });
    expect(adapters).toHaveLength(1);
    adapters[0].emit({ phase: 'playing', position: 23, duration: 100 });
    adapters[0].emit({ phase: 'buffering', position: 24, duration: 100 });

    await vi.waitFor(() => expect(adapters).toHaveLength(2));
    expect(adapters[1].loads[0].position).toBe(24);
    expect(session.getState().fallbackReason).toBe('Repeated buffering');
  });

  it('falls back when startup exceeds the configured timeout', async () => {
    vi.useFakeTimers();
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      startupTimeoutMs: 2_000,
      createAdapter: () => {
        const adapter = new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    await session.start({ position: 18, tracks: initialTracks, subtitles: [] });

    await vi.advanceTimersByTimeAsync(2_000);

    expect(adapters).toHaveLength(2);
    expect(adapters[1].loads[0].position).toBe(18);
    expect(session.getState().fallbackReason).toBe('Startup timed out');
    vi.useRealTimers();
  });

  it('times out even when the adapter load promise never settles', async () => {
    vi.useFakeTimers();
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      startupTimeoutMs: 2_000,
      createAdapter: () => {
        const adapter = adapters.length === 0
          ? new FakeAdapter(allCapabilities, () => new Promise(() => undefined))
          : new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    void session.start({ position: 18, tracks: initialTracks, subtitles: [] });
    await Promise.resolve();
    expect(adapters[0].loads[0].signal).toBeInstanceOf(AbortSignal);

    await vi.advanceTimersByTimeAsync(2_000);

    expect(adapters).toHaveLength(2);
    expect(adapters[0].loads[0].signal.aborted).toBe(true);
    expect(adapters[1].loads[0].position).toBe(18);
    expect(session.getState().fallbackReason).toBe('Startup timed out');
    vi.useRealTimers();
  });

  it.each([
    ['no video track', { phase: 'ready' as const, hasVideo: false }, 'No video track'],
    ['black frame', { phase: 'playing' as const, hasVideo: true, blackFrameDetected: true }, 'Black frame detected'],
  ])('falls back after detecting %s', async (_name, adapterState, reason) => {
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      createAdapter: () => {
        const adapter = new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    await session.start({ position: 5, tracks: initialTracks, subtitles: [] });

    adapters[0].emit(adapterState as Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'>);

    await vi.waitFor(() => expect(adapters).toHaveLength(2));
    expect(session.getState().fallbackReason).toBe(reason);
  });

  it('probes embedded audio only when the audio panel first opens for an adapter', async () => {
    const adapter = new FakeAdapter();
    const session = new PlayerSession(playbackPlan([playbackAttempt('primary')]), {
      createAdapter: () => adapter,
    });
    await session.start({ position: 0, tracks: initialTracks, subtitles: [] });

    expect(adapter.probeCount).toBe(0);
    await session.openAudioPanel();
    await session.openAudioPanel();

    expect(adapter.probeCount).toBe(1);
  });

  it('does not invoke capabilities an adapter cannot honestly provide', async () => {
    const adapter = new FakeAdapter({ ...allCapabilities, playbackRate: false });
    const session = new PlayerSession(playbackPlan([playbackAttempt('primary')]), {
      createAdapter: () => adapter,
    });
    await session.start({ position: 0, tracks: initialTracks, subtitles: [] });

    await session.setPlaybackRate(1.5);

    expect(adapter.playbackRates).toEqual([]);
  });

  it('retries from the primary route without losing the current handoff', async () => {
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      createAdapter: () => {
        const adapter = new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    await session.start({ position: 8, tracks: initialTracks, subtitles });
    adapters[0].emit({
      phase: 'playing',
      position: 64,
      duration: 600,
      selectedAudioId: 'audio-es',
      audioTracks: [{ id: 'audio-es', kind: 'audio', label: 'Spanish', language: 'es', selected: true }],
    });

    await session.retry();

    expect(adapters).toHaveLength(2);
    expect(adapters[1].loads[0]).toMatchObject({
      attempt: playbackAttempt('primary'),
      position: 64,
      tracks: { audioId: null, audioLanguage: 'es' },
    });
    expect(session.getState()).toMatchObject({ attemptIndex: 0, fallbackCount: 0, fallbackReason: null });
  });

  it('surfaces a terminal error after every planned attempt is exhausted', async () => {
    const adapter = new FakeAdapter();
    const session = new PlayerSession(playbackPlan([playbackAttempt('only')]), {
      createAdapter: () => adapter,
    });
    await session.start({ position: 0, tracks: initialTracks, subtitles: [] });

    adapter.emit({ phase: 'error', error: 'network failed' });

    await vi.waitFor(() => expect(session.getState().phase).toBe('error'));
    expect(session.getState()).toMatchObject({ error: 'network failed', fallbackCount: 0 });
  });

  it('continues cascading when a fallback adapter rejects during load', async () => {
    const attempts = [playbackAttempt('first'), playbackAttempt('second'), playbackAttempt('third')];
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(attempts), {
      createAdapter: () => {
        const adapter = adapters.length === 1
          ? new FakeAdapter(allCapabilities, async () => { throw new Error('second load failed'); })
          : new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    await session.start({ position: 9, tracks: initialTracks, subtitles: [] });

    adapters[0].emit({ phase: 'error', position: 27, error: 'first failed' });

    await vi.waitFor(() => expect(adapters).toHaveLength(3));
    expect(adapters[2].loads[0]).toMatchObject({
      attempt: attempts[2],
      position: 27,
    });
    expect(session.getState()).toMatchObject({ attemptIndex: 2, fallbackReason: 'second load failed' });
  });

  it('continues fallback when the previous adapter teardown rejects', async () => {
    const adapters: FakeAdapter[] = [];
    const session = new PlayerSession(playbackPlan(), {
      createAdapter: () => {
        const adapter = adapters.length === 0
          ? new FakeAdapter(allCapabilities, undefined, async () => { throw new Error('stop failed'); })
          : new FakeAdapter();
        adapters.push(adapter);
        return adapter;
      },
    });
    await session.start({ position: 0, tracks: initialTracks, subtitles: [] });

    await expect(session.fallback('decoder failed')).resolves.toBeUndefined();

    expect(adapters).toHaveLength(2);
    expect(session.getState()).toMatchObject({ attemptIndex: 1, phase: 'loading' });
  });

  it('destroys and detaches the final adapter on terminal error', async () => {
    const adapter = new FakeAdapter();
    const session = new PlayerSession(playbackPlan([playbackAttempt('only')]), {
      createAdapter: () => adapter,
    });
    await session.start({ position: 0, tracks: initialTracks, subtitles: [] });

    adapter.emit({ phase: 'error', error: 'terminal failure' });

    await vi.waitFor(() => expect(session.getState().phase).toBe('error'));
    expect(adapter.destroyed).toBe(true);
  });

  it('disposes a pending terminal adapter exactly once when its load settles late', async () => {
    let resolveLoad: (() => void) | null = null;
    const adapter = new FakeAdapter(allCapabilities, () => new Promise<void>(resolve => { resolveLoad = resolve; }));
    const session = new PlayerSession(playbackPlan([playbackAttempt('only')]), {
      createAdapter: () => adapter,
    });
    const start = session.start({ position: 0, tracks: initialTracks, subtitles: [] });
    await vi.waitFor(() => expect(adapter.loads).toHaveLength(1));

    adapter.emit({ phase: 'error', error: 'terminal failure' });
    await vi.waitFor(() => expect(session.getState().phase).toBe('error'));
    resolveLoad?.();
    await start;

    expect(adapter.destroyCount).toBe(1);
  });

  it('attaches late subtitles without recreating the active adapter', async () => {
    const adapter = new FakeAdapter();
    const session = new PlayerSession(playbackPlan([playbackAttempt('only')]), {
      createAdapter: () => adapter,
    });
    await session.start({ position: 0, tracks: initialTracks, subtitles: [] });
    const late = [{ id: 'late-sv', lang: 'sv', url: '/late-sv.vtt' }];

    expect('updateSubtitles' in session).toBe(true);
    if ('updateSubtitles' in session && typeof session.updateSubtitles === 'function') {
      await session.updateSubtitles(late);
    }

    expect(adapter.loads).toHaveLength(1);
    expect(adapter.subtitleUpdates).toEqual([late]);
  });
});
