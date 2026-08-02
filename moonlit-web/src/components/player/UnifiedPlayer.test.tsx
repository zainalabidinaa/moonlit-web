import { act, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import type {
  PlaybackAttempt,
  PlaybackPlan,
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerAdapterLoadRequest,
  PlayerAdapterState,
} from '@/lib/player/contracts';
import { normalizeAdapterState, normalizePlayerLaunch } from '@/lib/player/contracts';
import { UnifiedPlayer } from './UnifiedPlayer';

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
  readonly pause = vi.fn();
  readonly seek = vi.fn();
  readonly subtitleUpdates: PlayerAdapterLoadRequest['subtitles'][] = [];
  private state = normalizeAdapterState({ phase: 'idle' });
  private listeners = new Set<(state: PlayerAdapterState) => void>();

  constructor(
    kind: PlaybackAttempt['adapter'],
    private readonly destroyBehavior?: () => Promise<void>,
  ) { this.kind = kind; }
  async load(request: PlayerAdapterLoadRequest) { this.loads.push(request); }
  play() {}
  setVolume() {}
  setMuted() {}
  setPlaybackRate() {}
  setFullscreen() {}
  setPictureInPicture() {}
  selectAudioTrack() {}
  selectSubtitleTrack() {}
  updateSubtitles(subtitles: PlayerAdapterLoadRequest['subtitles']) { this.subtitleUpdates.push(subtitles); }
  subscribe(listener: (state: PlayerAdapterState) => void) { this.listeners.add(listener); listener(this.state); return () => this.listeners.delete(listener); }
  destroy() { return this.destroyBehavior?.(); }
  emit(input: Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'>) {
    this.state = normalizeAdapterState({ ...this.state, ...input });
    this.listeners.forEach(listener => listener(this.state));
  }
}

function playbackAttempt(adapter: PlaybackAttempt['adapter'], method: PlaybackAttempt['method']): PlaybackAttempt {
  return {
    id: `${adapter}:${method}`,
    adapter,
    method,
    url: `https://cdn.example/${method}`,
    sourceType: adapter === 'webcodecs' ? 'mkv' : 'video',
    isLive: false,
    reason: method,
  };
}

const stream = { url: 'https://cdn.example/movie.mp4', title: 'Movie H.264 AAC' };
const plan: PlaybackPlan = {
  outcome: 'play-here',
  label: 'Plays here',
  detail: 'Direct with a retained WebCodecs fallback',
  stream,
  attempts: [playbackAttempt('html-video', 'native'), playbackAttempt('webcodecs', 'webcodecs')],
};
const launch = normalizePlayerLaunch({
  type: 'movie',
  id: 'tt123',
  metadata: { mediaId: 'tt123', mediaType: 'movie', title: 'Moonlit Movie' },
  startPosition: 12,
});

afterEach(() => vi.useRealTimers());

describe('UnifiedPlayer', () => {
  it('keeps one React chrome while the session falls back between renderer adapters', async () => {
    const adapters: FakeAdapter[] = [];
    const onReady = vi.fn();
    render(
      <UnifiedPlayer
        launch={launch}
        plan={plan}
        currentStream={stream}
        streams={[stream]}
        subtitles={[]}
        createAdapter={attempt => {
          const adapter = new FakeAdapter(attempt.adapter);
          adapters.push(adapter);
          return adapter;
        }}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
        onReady={onReady}
      />,
    );
    await vi.waitFor(() => expect(adapters).toHaveLength(1));

    act(() => adapters[0].emit({ phase: 'playing', position: 24, duration: 120, paused: false, hasVideo: true }));
    expect(onReady).toHaveBeenCalledTimes(1);
    expect(screen.getAllByRole('button', { name: 'Sources' })).toHaveLength(1);
    fireEvent.click(screen.getByRole('button', { name: 'Pause' }));
    expect(adapters[0].pause).toHaveBeenCalledTimes(1);

    await act(async () => {
      adapters[0].emit({ phase: 'error', position: 24, duration: 120, error: 'native failed' });
      await Promise.resolve();
    });
    await vi.waitFor(() => expect(adapters).toHaveLength(2));
    expect(adapters[1].kind).toBe('webcodecs');
    expect(adapters[1].loads[0].position).toBe(24);
    act(() => adapters[1].emit({ phase: 'playing', position: 24, duration: 120, paused: false, hasVideo: true }));
    expect(screen.getByTestId('unified-player')).toHaveAttribute('data-active-adapter', 'webcodecs');
    expect(screen.getAllByRole('button', { name: 'Sources' })).toHaveLength(1);
  });

  it('centralizes progress and completion reporting for every adapter', async () => {
    vi.useFakeTimers();
    const adapter = new FakeAdapter('html-video');
    const onProgress = vi.fn();
    render(
      <UnifiedPlayer
        launch={launch}
        plan={{ ...plan, attempts: [plan.attempts[0]] }}
        currentStream={stream}
        streams={[stream]}
        subtitles={[]}
        createAdapter={() => adapter}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
        onProgress={onProgress}
      />,
    );
    await vi.waitFor(() => expect(adapter.loads).toHaveLength(1));
    act(() => adapter.emit({ phase: 'playing', position: 40, duration: 100, paused: false, hasVideo: true }));

    act(() => vi.advanceTimersByTime(10_000));
    expect(onProgress).toHaveBeenCalledWith(40, 100, false);
    act(() => adapter.emit({ phase: 'ended', position: 100, duration: 100, paused: true, hasVideo: true }));
    expect(onProgress).toHaveBeenLastCalledWith(100, 100, true);
    const completionCallCount = onProgress.mock.calls.length;

    act(() => vi.advanceTimersByTime(10_000));

    expect(onProgress).toHaveBeenCalledTimes(completionCallCount);
  });

  it('does not restart active playback when async preferences or subtitles reconcile', async () => {
    const adapters: FakeAdapter[] = [];
    const props = {
      plan,
      currentStream: stream,
      streams: [stream],
      onBack: vi.fn(),
      onSwitchStream: vi.fn(),
      createAdapter: (attempt: PlaybackAttempt) => {
        const adapter = new FakeAdapter(attempt.adapter);
        adapters.push(adapter);
        return adapter;
      },
    };
    const view = render(<UnifiedPlayer {...props} launch={launch} subtitles={[]} />);
    await vi.waitFor(() => expect(adapters).toHaveLength(1));
    act(() => adapters[0].emit({ phase: 'playing', position: 30, duration: 100, paused: false, hasVideo: true }));

    view.rerender(
      <UnifiedPlayer
        {...props}
        launch={normalizePlayerLaunch({
          ...launch,
          preferredTracks: { audioLanguage: 'ja', subtitleLanguage: 'sv' },
        })}
        subtitles={[{ id: 'sv', lang: 'sv', url: '/sv.vtt' }]}
      />,
    );
    await act(async () => Promise.resolve());

    expect(adapters).toHaveLength(1);
    expect(adapters[0].subtitleUpdates).toEqual([[{ id: 'sv', lang: 'sv', url: '/sv.vtt' }]]);
  });

  it('hands portable track languages, not adapter-local ids, to a switched source', async () => {
    const adapter = new FakeAdapter('html-video');
    const onSwitchStream = vi.fn();
    const backup = { url: 'https://cdn.example/backup.mp4', title: 'Backup 1080p' };
    render(
      <UnifiedPlayer
        launch={launch}
        plan={{ ...plan, attempts: [plan.attempts[0]] }}
        currentStream={stream}
        streams={[stream, backup]}
        subtitles={[]}
        createAdapter={() => adapter}
        onBack={vi.fn()}
        onSwitchStream={onSwitchStream}
      />,
    );
    await vi.waitFor(() => expect(adapter.loads).toHaveLength(1));
    act(() => adapter.emit({
      phase: 'playing',
      position: 55,
      duration: 100,
      paused: false,
      hasVideo: true,
      selectedAudioId: 'html-audio-7',
      selectedSubtitleId: 'html-sub-3',
      audioTracks: [{ id: 'html-audio-7', kind: 'audio', label: 'Spanish', language: 'es', selected: true }],
      subtitleTracks: [{ id: 'html-sub-3', kind: 'subtitles', label: 'English', language: 'en', selected: true }],
    }));

    fireEvent.click(screen.getByRole('button', { name: 'Sources' }));
    fireEvent.click(screen.getByRole('option', { name: /Backup 1080p/ }));

    expect(onSwitchStream).toHaveBeenCalledWith(backup, {
      position: 55,
      tracks: {
        audioId: null,
        subtitleId: null,
        audioLanguage: 'es',
        subtitleLanguage: 'en',
        audioIdentity: { kind: 'audio', language: 'es', label: 'Spanish', ordinal: 0 },
        subtitleIdentity: { kind: 'subtitles', language: 'en', label: 'English', ordinal: 0 },
      },
    });
  });

  it('hands off the synchronous MPV selection before its adapter acknowledgement', async () => {
    const adapter = new FakeAdapter('mpv');
    const onSwitchStream = vi.fn();
    const backup = { url: 'https://cdn.example/backup.mp4', title: 'Backup 1080p' };
    render(
      <UnifiedPlayer
        launch={launch}
        plan={{ ...plan, attempts: [playbackAttempt('mpv', 'mpv')] }}
        currentStream={stream}
        streams={[stream, backup]}
        subtitles={[]}
        createAdapter={() => adapter}
        onBack={vi.fn()}
        onSwitchStream={onSwitchStream}
      />,
    );
    await vi.waitFor(() => expect(adapter.loads).toHaveLength(1));
    act(() => adapter.emit({
      phase: 'playing',
      position: 61,
      duration: 100,
      paused: false,
      hasVideo: true,
      selectedSubtitleId: 11,
      subtitleTracks: [
        { id: 11, kind: 'subtitles', label: 'Signs', language: 'en', selected: true },
        { id: 22, kind: 'subtitles', label: 'Signs', language: 'en', selected: false },
      ],
    }));

    fireEvent.click(screen.getByRole('button', { name: 'Subtitles' }));
    fireEvent.click(screen.getAllByRole('option', { name: /Signs/ })[1]);
    fireEvent.click(screen.getByRole('button', { name: 'Sources' }));
    fireEvent.click(screen.getByRole('option', { name: /Backup 1080p/ }));

    expect(onSwitchStream).toHaveBeenCalledWith(backup, {
      position: 61,
      tracks: {
        audioId: null,
        subtitleId: null,
        audioLanguage: null,
        subtitleLanguage: 'en',
        audioIdentity: null,
        subtitleIdentity: { kind: 'subtitles', language: 'en', label: 'Signs', ordinal: 1 },
      },
    });
  });

  it('uses the same shared loading surface while a stream plan is still resolving', () => {
    render(
      <UnifiedPlayer
        launch={launch}
        plan={null}
        currentStream={null}
        streams={[]}
        subtitles={[]}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
      />,
    );

    expect(screen.getByRole('status')).toHaveTextContent('Finding the best playable source');
    expect(screen.getByTestId('unified-player')).toHaveStyle({ '--moonlit-subtitle-font-size': '32px' });
    expect(screen.getByTestId('player-video-host')).toHaveClass('moonlit-native-subtitles');
  });

  it('keeps intro prompts and profile-driven auto-skip inside the shared controller', async () => {
    const manualAdapter = new FakeAdapter('html-video');
    const view = render(
      <UnifiedPlayer
        launch={launch}
        plan={{ ...plan, attempts: [plan.attempts[0]] }}
        currentStream={stream}
        streams={[stream]}
        subtitles={[]}
        createAdapter={() => manualAdapter}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
        intro={{ start: 10, end: 30, showButton: true, autoSkip: false }}
      />,
    );
    await vi.waitFor(() => expect(manualAdapter.loads).toHaveLength(1));
    act(() => manualAdapter.emit({ phase: 'playing', position: 15, duration: 100, paused: false, hasVideo: true }));
    fireEvent.click(screen.getByRole('button', { name: /Skip Intro/ }));
    expect(manualAdapter.seek).toHaveBeenCalledWith(30);

    view.unmount();
    const autoAdapter = new FakeAdapter('html-video');
    render(
      <UnifiedPlayer
        launch={launch}
        plan={{ ...plan, attempts: [plan.attempts[0]] }}
        currentStream={stream}
        streams={[stream]}
        subtitles={[]}
        createAdapter={() => autoAdapter}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
        intro={{ start: 10, end: 30, showButton: false, autoSkip: true }}
      />,
    );
    await vi.waitFor(() => expect(autoAdapter.loads).toHaveLength(1));
    act(() => autoAdapter.emit({ phase: 'playing', position: 15, duration: 100, paused: false, hasVideo: true }));
    expect(autoAdapter.seek).toHaveBeenCalledWith(30);
  });

  it('awaits prior session teardown before reusing shared hosts for a replacement plan', async () => {
    let releaseDestroy: (() => void) | null = null;
    const adapters: FakeAdapter[] = [];
    const createAdapter = (attempt: PlaybackAttempt) => {
      const adapter = new FakeAdapter(
        attempt.adapter,
        adapters.length === 0
          ? () => new Promise<void>(resolve => { releaseDestroy = resolve; })
          : undefined,
      );
      adapters.push(adapter);
      return adapter;
    };
    const view = render(
      <UnifiedPlayer
        launch={launch}
        plan={plan}
        currentStream={stream}
        streams={[stream]}
        subtitles={[]}
        createAdapter={createAdapter}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
      />,
    );
    await vi.waitFor(() => expect(adapters).toHaveLength(1));

    view.rerender(
      <UnifiedPlayer
        launch={launch}
        plan={{ ...plan, attempts: [playbackAttempt('html-video', 'native-hls')] }}
        currentStream={stream}
        streams={[stream]}
        subtitles={[]}
        createAdapter={createAdapter}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
      />,
    );
    await act(async () => Promise.resolve());

    expect(adapters).toHaveLength(1);
    releaseDestroy?.();
    await vi.waitFor(() => expect(adapters).toHaveLength(2));
  });
});
