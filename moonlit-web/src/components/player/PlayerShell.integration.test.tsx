import { act, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { PlayerProvider } from '@/app/PlayerProvider';
import type {
  PlaybackAttempt,
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerAdapterLoadRequest,
  PlayerAdapterState,
} from '@/lib/player/contracts';
import { normalizeAdapterState, normalizePlayerLaunch } from '@/lib/player/contracts';
import { mpvAvailable } from '@/lib/platform/mpv';
import { DEFAULT_PLAYER_PREFERENCES } from '@/lib/preferences/profile-preferences';
import { fetchStreamsFromAll } from '@/lib/stremio';
import { PlayerShell } from './PlayerShell';

const preferenceRepositoryMock = vi.hoisted(() => ({
  load: vi.fn(),
  loadCached: vi.fn(),
}));
const apiMock = vi.hoisted(() => ({ updateWatchProgress: vi.fn() }));

vi.mock('@/app/AuthProvider', () => ({
  useAuth: () => ({ addons: [], currentProfile: null }),
}));

vi.mock('@/lib/platform/mpv', async importOriginal => {
  const actual = await importOriginal<typeof import('@/lib/platform/mpv')>();
  return { ...actual, mpvAvailable: vi.fn(async () => false) };
});

vi.mock('@/lib/stremio', async importOriginal => {
  const actual = await importOriginal<typeof import('@/lib/stremio')>();
  return {
    ...actual,
    fetchStreamsFromAll: vi.fn(async () => []),
    fetchSubtitlesFromAll: vi.fn(async () => []),
  };
});

vi.mock('@/lib/preferences/profile-preferences', async importOriginal => {
  const actual = await importOriginal<typeof import('@/lib/preferences/profile-preferences')>();
  return {
    ...actual,
    createProfilePreferencesRepository: () => ({
      loadCached: (...args: unknown[]) => preferenceRepositoryMock.loadCached(...args)
        ?? { value: actual.DEFAULT_PLAYER_PREFERENCES },
      load: (...args: unknown[]) => preferenceRepositoryMock.load(...args)
        ?? Promise.resolve({ value: actual.DEFAULT_PLAYER_PREFERENCES }),
    }),
  };
});

vi.mock('@/lib/services/api', () => apiMock);

const capabilities: PlayerAdapterCapabilities = {
  seek: true,
  volume: true,
  playbackRate: true,
  fullscreen: true,
  pictureInPicture: false,
  remotePlayback: false,
  audioTracks: false,
  subtitleTracks: true,
  seekPreview: false,
  screenshot: false,
  anime4k: false,
};

class FakeAdapter implements PlayerAdapter {
  readonly kind;
  readonly capabilities = capabilities;
  readonly loads: PlayerAdapterLoadRequest[] = [];
  private state = normalizeAdapterState({ phase: 'idle' });
  private listeners = new Set<(state: PlayerAdapterState) => void>();

  constructor(kind: PlaybackAttempt['adapter']) { this.kind = kind; }
  async load(request: PlayerAdapterLoadRequest) { this.loads.push(request); }
  play() {}
  pause() {}
  seek() {}
  setVolume() {}
  setMuted() {}
  setPlaybackRate() {}
  setFullscreen() {}
  setPictureInPicture() {}
  selectAudioTrack() {}
  selectSubtitleTrack() {}
  subscribe(listener: (state: PlayerAdapterState) => void) { this.listeners.add(listener); listener(this.state); return () => this.listeners.delete(listener); }
  destroy() {}
  emit(input: Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'>) {
    this.state = normalizeAdapterState({ ...this.state, ...input });
    this.listeners.forEach(listener => listener(this.state));
  }
}

describe('PlayerShell unified integration', () => {
  it('waits for actual adapter readiness and preserves the handoff when the next source is selected', async () => {
    const first = { url: 'https://cdn.example/first.mp4', title: '1080p H.264 AAC' };
    const backup = { url: 'https://cdn.example/backup.mp4', title: '720p H.264 AAC' };
    const launch = normalizePlayerLaunch({
      type: 'movie',
      id: 'tt123',
      streamUrl: first.url,
      streams: [first, backup],
      metadata: { mediaId: 'tt123', mediaType: 'movie', title: 'Movie' },
      startPosition: 12,
    });
    const adapters: FakeAdapter[] = [];
    const onVideoReady = vi.fn();
    const onError = vi.fn();

    render(
      <PlayerProvider>
        <PlayerShell
          launch={launch}
          onBack={vi.fn()}
          onVideoReady={onVideoReady}
          onError={onError}
          createAdapter={attempt => {
            const adapter = new FakeAdapter(attempt.adapter);
            adapters.push(adapter);
            return adapter;
          }}
        />
      </PlayerProvider>,
    );
    await vi.waitFor(() => expect(adapters).toHaveLength(1));
    expect(adapters[0].loads[0]).toMatchObject({ position: 12, attempt: { url: first.url } });
    expect(onVideoReady).not.toHaveBeenCalled();

    act(() => adapters[0].emit({ phase: 'ready', position: 12, duration: 120, paused: true, hasVideo: true }));
    expect(onVideoReady).toHaveBeenCalledTimes(1);
    act(() => adapters[0].emit({ phase: 'playing', position: 44, duration: 120, paused: false, hasVideo: true }));
    await act(async () => {
      adapters[0].emit({ phase: 'error', position: 44, duration: 120, error: 'source failed' });
      await Promise.resolve();
    });

    await vi.waitFor(() => expect(adapters).toHaveLength(2));
    expect(adapters[1].loads[0]).toMatchObject({ position: 44, attempt: { url: backup.url } });
    expect(onError).not.toHaveBeenCalled();
  });

  it('turns stalled capability and addon resolution into a shared terminal state', async () => {
    vi.useFakeTimers();
    vi.mocked(mpvAvailable).mockImplementationOnce(() => new Promise(() => undefined));
    vi.mocked(fetchStreamsFromAll).mockImplementationOnce(() => new Promise(() => undefined));
    render(
      <PlayerProvider>
        <PlayerShell
          launch={normalizePlayerLaunch({
            type: 'movie',
            id: 'tt-stalled',
            metadata: { mediaId: 'tt-stalled', mediaType: 'movie', title: 'Stalled Movie' },
          })}
          onBack={vi.fn()}
          onVideoReady={vi.fn()}
          onError={vi.fn()}
        />
      </PlayerProvider>,
    );

    await act(async () => vi.advanceTimersByTimeAsync(15_000));

    expect(screen.getByRole('alert')).toHaveTextContent('No sources were returned');
  });

  it('binds launch credentials only to the matching explicit source', async () => {
    const protectedSource = { url: 'https://protected.example/movie.mp4', title: 'Protected H.264 AAC' };
    const publicBackup = { url: 'https://public.example/movie.mp4', title: 'Public H.264 AAC' };
    const adapters: FakeAdapter[] = [];

    render(
      <PlayerProvider>
        <PlayerShell
          launch={normalizePlayerLaunch({
            type: 'movie',
            id: 'tt-headers',
            streamUrl: protectedSource.url,
            streams: [protectedSource, publicBackup],
            requestHeaders: { Authorization: 'Bearer source-secret' },
            metadata: { mediaId: 'tt-headers', mediaType: 'movie', title: 'Movie' },
          })}
          onBack={vi.fn()}
          onVideoReady={vi.fn()}
          onError={vi.fn()}
          createAdapter={attempt => {
            const adapter = new FakeAdapter(attempt.adapter);
            adapters.push(adapter);
            return adapter;
          }}
        />
      </PlayerProvider>,
    );

    await vi.waitFor(() => expect(adapters).toHaveLength(1));
    expect(adapters[0].loads[0].attempt.url).toBe(publicBackup.url);
    expect(adapters[0].loads[0].attempt.requestHeaders).toBeUndefined();
  });

  it('does not rebuild active playback when authoritative profile preferences reconcile', async () => {
    let resolvePreferences: ((value: { value: typeof DEFAULT_PLAYER_PREFERENCES }) => void) | null = null;
    preferenceRepositoryMock.loadCached.mockReturnValueOnce({
      value: {
        ...DEFAULT_PLAYER_PREFERENCES,
        usePerTypePlayers: true,
        moviePlayer: 'native',
      },
    });
    preferenceRepositoryMock.load.mockReturnValueOnce(new Promise(resolve => { resolvePreferences = resolve; }));
    vi.mocked(mpvAvailable).mockResolvedValueOnce(true);
    const adapters: FakeAdapter[] = [];

    render(
      <PlayerProvider>
        <PlayerShell
          launch={normalizePlayerLaunch({
            type: 'movie',
            id: 'tt-preferences',
            streams: [{ url: 'https://cdn.example/movie.mp4', title: 'H.264 AAC' }],
            metadata: { mediaId: 'tt-preferences', mediaType: 'movie', title: 'Movie' },
          })}
          profileId="profile-1"
          onBack={vi.fn()}
          onVideoReady={vi.fn()}
          onError={vi.fn()}
          createAdapter={attempt => {
            const adapter = new FakeAdapter(attempt.adapter);
            adapters.push(adapter);
            return adapter;
          }}
        />
      </PlayerProvider>,
    );
    await vi.waitFor(() => expect(adapters).toHaveLength(1));
    act(() => adapters[0].emit({ phase: 'playing', position: 31, duration: 120, paused: false, hasVideo: true }));

    await act(async () => {
      resolvePreferences?.({
        value: {
          ...DEFAULT_PLAYER_PREFERENCES,
          usePerTypePlayers: true,
          moviePlayer: 'mpv',
        },
      });
      await Promise.resolve();
    });

    expect(adapters).toHaveLength(1);
    expect(adapters[0].loads[0].attempt.method).toBe('native');
  });

  it('serializes progress persistence so completion cannot be overtaken by an older write', async () => {
    vi.useFakeTimers();
    let releaseFirstWrite: (() => void) | null = null;
    apiMock.updateWatchProgress
      .mockImplementationOnce(() => new Promise<void>(resolve => { releaseFirstWrite = resolve; }))
      .mockResolvedValue(undefined);
    const adapter = new FakeAdapter('html-video');

    render(
      <PlayerProvider>
        <PlayerShell
          launch={normalizePlayerLaunch({
            type: 'movie',
            id: 'tt-progress',
            streams: [{ url: 'https://cdn.example/progress.mp4', title: 'H.264 AAC' }],
            metadata: { mediaId: 'tt-progress', mediaType: 'movie', title: 'Movie' },
          })}
          profileId="profile-progress"
          onBack={vi.fn()}
          onVideoReady={vi.fn()}
          onError={vi.fn()}
          createAdapter={() => adapter}
        />
      </PlayerProvider>,
    );
    await vi.waitFor(() => expect(adapter.loads).toHaveLength(1));
    act(() => adapter.emit({ phase: 'playing', position: 40, duration: 100, paused: false, hasVideo: true }));
    await act(async () => {
      vi.advanceTimersByTime(10_000);
      await Promise.resolve();
    });
    expect(apiMock.updateWatchProgress).toHaveBeenCalledTimes(1);

    act(() => adapter.emit({ phase: 'ended', position: 100, duration: 100, paused: true, hasVideo: true }));
    expect(apiMock.updateWatchProgress).toHaveBeenCalledTimes(1);

    await act(async () => {
      releaseFirstWrite?.();
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(apiMock.updateWatchProgress).toHaveBeenCalledTimes(2);
    expect(apiMock.updateWatchProgress).toHaveBeenLastCalledWith(
      'profile-progress', 'tt-progress', 'movie', 100, 100, true, 'Movie', undefined,
    );
  });
});

afterEach(() => {
  vi.useRealTimers();
  vi.mocked(mpvAvailable).mockResolvedValue(false);
  vi.mocked(fetchStreamsFromAll).mockResolvedValue([]);
  preferenceRepositoryMock.load.mockReset();
  preferenceRepositoryMock.loadCached.mockReset();
  apiMock.updateWatchProgress.mockReset();
});
