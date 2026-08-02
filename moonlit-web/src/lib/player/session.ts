import type { SubtitleItem } from '@/lib/stremio';
import type {
  PlaybackAttempt,
  PlaybackPlan,
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerAdapterState,
  PlayerTrackSelection,
} from './contracts';
import { playerTrackIdentity } from './contracts';

export const DEFAULT_STARTUP_TIMEOUT_MS = 15_000;
export const DEFAULT_REPEATED_BUFFERING_LIMIT = 3;

export type PlayerSessionPhase =
  | 'idle'
  | 'loading'
  | 'ready'
  | 'playing'
  | 'paused'
  | 'buffering'
  | 'ended'
  | 'error'
  | 'external'
  | 'unsupported';

export interface PlayerSessionState {
  phase: PlayerSessionPhase;
  plan: PlaybackPlan;
  attempt: PlaybackAttempt | null;
  attemptIndex: number;
  fallbackCount: number;
  fallbackReason: string | null;
  error: string | null;
  adapterState: PlayerAdapterState | null;
  capabilities: PlayerAdapterCapabilities | null;
}

export interface PlayerSessionStartOptions {
  position: number;
  tracks: PlayerTrackSelection;
  subtitles: SubtitleItem[];
}

export interface PlayerSessionOptions {
  createAdapter: (attempt: PlaybackAttempt) => PlayerAdapter;
  startupTimeoutMs?: number;
  repeatedBufferingLimit?: number;
}

type Listener = (state: PlayerSessionState) => void;

export class PlayerSession {
  private readonly createAdapter: PlayerSessionOptions['createAdapter'];
  private readonly startupTimeoutMs: number;
  private readonly repeatedBufferingLimit: number;
  private readonly listeners = new Set<Listener>();
  private adapter: PlayerAdapter | null = null;
  private unsubscribeAdapter: (() => void) | null = null;
  private startupTimer: ReturnType<typeof setTimeout> | null = null;
  private loadAbortController: AbortController | null = null;
  private loadGeneration = 0;
  private destroyed = false;
  private destroyPromise: Promise<void> | null = null;
  private readonly adapterDisposals = new WeakMap<PlayerAdapter, Promise<void>>();
  private startOptions: PlayerSessionStartOptions | null = null;
  private preservedPosition = 0;
  private preservedTracks: PlayerTrackSelection = {
    audioId: null,
    subtitleId: 'off',
    audioLanguage: null,
    subtitleLanguage: null,
  };
  private pendingAudioSelection: string | number | null = null;
  private pendingSubtitleSelection: string | number | 'off' | null = null;
  private bufferingCount = 0;
  private lastAdapterPhase: PlayerAdapterState['phase'] = 'idle';
  private fallingBack = false;
  private audioProbed = false;
  private state: PlayerSessionState;

  constructor(private readonly plan: PlaybackPlan, options: PlayerSessionOptions) {
    this.createAdapter = options.createAdapter;
    this.startupTimeoutMs = options.startupTimeoutMs ?? DEFAULT_STARTUP_TIMEOUT_MS;
    this.repeatedBufferingLimit = options.repeatedBufferingLimit ?? DEFAULT_REPEATED_BUFFERING_LIMIT;
    this.state = {
      phase: 'idle',
      plan,
      attempt: null,
      attemptIndex: -1,
      fallbackCount: 0,
      fallbackReason: null,
      error: null,
      adapterState: null,
      capabilities: null,
    };
  }

  getState(): PlayerSessionState {
    return this.state;
  }

  getPlaybackHandoff(): { position: number; tracks: PlayerTrackSelection } {
    return {
      position: this.preservedPosition,
      tracks: {
        audioId: null,
        subtitleId: this.preservedTracks.subtitleId === 'off' ? 'off' : null,
        audioLanguage: this.preservedTracks.audioLanguage,
        subtitleLanguage: this.preservedTracks.subtitleLanguage,
        audioIdentity: this.preservedTracks.audioIdentity ?? null,
        subtitleIdentity: this.preservedTracks.subtitleIdentity ?? null,
      },
    };
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  async start(options: PlayerSessionStartOptions): Promise<void> {
    if (this.destroyed) return;
    this.startOptions = options;
    this.preservedPosition = Math.max(0, options.position);
    this.preservedTracks = { ...options.tracks };

    if (this.plan.outcome !== 'play-here' || this.plan.attempts.length === 0) {
      this.update({
        phase: this.plan.outcome === 'external' ? 'external' : 'unsupported',
        error: this.plan.detail,
      });
      return;
    }

    await this.loadAttempt(0, null);
  }

  async destroy(): Promise<void> {
    if (this.destroyPromise) return this.destroyPromise;
    this.destroyed = true;
    this.loadGeneration += 1;
    this.loadAbortController?.abort();
    this.loadAbortController = null;
    this.clearStartupTimer();
    this.unsubscribeAdapter?.();
    this.unsubscribeAdapter = null;
    const adapter = this.adapter;
    this.adapter = null;
    this.destroyPromise = (async () => {
      await this.destroyAdapter(adapter);
      this.listeners.clear();
    })();
    return this.destroyPromise;
  }

  play() { return this.adapter?.play(); }
  pause() { return this.adapter?.pause(); }
  seek(position: number) {
    if (!this.adapter?.capabilities.seek) return;
    this.preservedPosition = Math.max(0, position);
    this.bufferingCount = 0;
    return this.adapter.seek(this.preservedPosition);
  }
  setVolume(volume: number) {
    if (!this.adapter?.capabilities.volume) return;
    return this.adapter.setVolume(Math.max(0, Math.min(1, volume)));
  }
  setMuted(muted: boolean) {
    if (!this.adapter?.capabilities.volume) return;
    return this.adapter.setMuted(muted);
  }
  setPlaybackRate(rate: number) {
    if (!this.adapter?.capabilities.playbackRate) return;
    return this.adapter.setPlaybackRate(rate);
  }
  setFullscreen(fullscreen: boolean) {
    if (!this.adapter?.capabilities.fullscreen) return;
    return this.adapter.setFullscreen(fullscreen);
  }
  setPictureInPicture(enabled: boolean) {
    if (!this.adapter?.capabilities.pictureInPicture) return;
    return this.adapter.setPictureInPicture(enabled);
  }
  requestRemotePlayback() {
    if (!this.adapter?.capabilities.remotePlayback || !this.adapter.requestRemotePlayback) return;
    return this.adapter.requestRemotePlayback();
  }
  requestSeekPreview(position: number, signal?: AbortSignal) {
    const adapter = this.adapter;
    const request = adapter?.requestSeekPreview;
    if (!adapter?.capabilities.seekPreview || !request) return null;
    return request.call(adapter, Math.max(0, position), signal);
  }
  selectAudioTrack(id: string | number) {
    if (!this.adapter?.capabilities.audioTracks) return;
    this.preservedTracks.audioId = id;
    this.pendingAudioSelection = id;
    const tracks = this.state.adapterState?.audioTracks ?? [];
    const track = tracks.find(item => item.id === id);
    if (track) {
      this.preservedTracks.audioLanguage = track.language ?? null;
      this.preservedTracks.audioIdentity = playerTrackIdentity(track, tracks);
    }
    return this.adapter.selectAudioTrack(id);
  }
  selectSubtitleTrack(id: string | number | 'off') {
    if (!this.adapter?.capabilities.subtitleTracks) return;
    this.preservedTracks.subtitleId = id;
    this.pendingSubtitleSelection = id;
    if (id === 'off') {
      this.preservedTracks.subtitleIdentity = null;
    } else {
      const tracks = this.state.adapterState?.subtitleTracks ?? [];
      const track = tracks.find(item => item.id === id);
      if (track) {
        this.preservedTracks.subtitleLanguage = track.language ?? null;
        this.preservedTracks.subtitleIdentity = playerTrackIdentity(track, tracks);
      }
    }
    return this.adapter.selectSubtitleTrack(id);
  }

  async updateSubtitles(subtitles: SubtitleItem[]): Promise<void> {
    if (!this.startOptions) return;
    const previous = this.startOptions.subtitles;
    const unchanged = previous.length === subtitles.length
      && previous.every((item, index) => item.id === subtitles[index]?.id && item.url === subtitles[index]?.url);
    if (unchanged) return;
    this.startOptions = { ...this.startOptions, subtitles };
    await this.adapter?.updateSubtitles?.(subtitles, { ...this.preservedTracks });
  }

  async openAudioPanel(): Promise<void> {
    if (this.audioProbed || !this.adapter?.capabilities.audioTracks || !this.adapter.probeAudioTracks) return;
    this.audioProbed = true;
    await this.adapter.probeAudioTracks();
  }

  async retry(): Promise<void> {
    if (!this.startOptions || this.plan.attempts.length === 0) return;
    this.fallingBack = false;
    await this.loadAttempt(0, null);
  }

  async fallback(reason: string): Promise<void> {
    await this.fallbackFrom(this.state.attemptIndex, reason);
  }

  private async loadAttempt(index: number, reason: string | null): Promise<void> {
    const attempt = this.plan.attempts[index];
    const options = this.startOptions;
    if (!attempt || !options || this.destroyed) return;

    const generation = this.loadGeneration + 1;
    this.loadGeneration = generation;
    this.loadAbortController?.abort();
    const abortController = new AbortController();
    this.loadAbortController = abortController;
    this.clearStartupTimer();
    this.unsubscribeAdapter?.();
    this.unsubscribeAdapter = null;
    const previous = this.adapter;
    this.adapter = null;
    await this.destroyAdapter(previous);
    if (this.destroyed || generation !== this.loadGeneration) return;

    const adapter = this.createAdapter(attempt);
    this.adapter = adapter;
    this.pendingAudioSelection = null;
    this.pendingSubtitleSelection = null;
    const isFirstAdapter = this.state.attemptIndex === -1;
    this.bufferingCount = 0;
    this.lastAdapterPhase = 'idle';
    this.audioProbed = false;
    this.update({
      phase: 'loading',
      attempt,
      attemptIndex: index,
      fallbackCount: index,
      fallbackReason: reason,
      error: null,
      adapterState: null,
      capabilities: adapter.capabilities,
    });
    this.unsubscribeAdapter = adapter.subscribe(state => this.handleAdapterState(adapter, index, state));
    this.armStartupTimer(index, generation);
    const adapterTracks = !isFirstAdapter
      ? {
          ...this.preservedTracks,
          audioId: null,
          subtitleId: this.preservedTracks.subtitleId === 'off' ? 'off' as const : null,
        }
      : { ...this.preservedTracks };

    try {
      await adapter.load({
        attempt,
        position: this.preservedPosition,
        tracks: adapterTracks,
        subtitles: options.subtitles,
        signal: abortController.signal,
      });
      if (this.destroyed || generation !== this.loadGeneration || abortController.signal.aborted) {
        if (this.adapter === adapter) this.adapter = null;
        await this.destroyAdapter(adapter);
      }
    } catch (error) {
      if (!abortController.signal.aborted && !this.destroyed && generation === this.loadGeneration && this.adapter === adapter) {
        await this.fallbackFrom(index, error instanceof Error ? error.message : 'Adapter failed to load');
      }
    }
  }

  private handleAdapterState(adapter: PlayerAdapter, index: number, next: PlayerAdapterState): void {
    if (this.adapter !== adapter || this.state.attemptIndex !== index) return;

    if (next.position > 0) this.preservedPosition = next.position;
    const audioAcknowledged = this.pendingAudioSelection === null
      || String(next.selectedAudioId) === String(this.pendingAudioSelection);
    if (this.pendingAudioSelection !== null && audioAcknowledged) this.pendingAudioSelection = null;
    if (audioAcknowledged && next.audioTracks.length > 0 && next.selectedAudioId !== null) {
      this.preservedTracks.audioId = next.selectedAudioId;
      const track = next.audioTracks.find(item => item.id === next.selectedAudioId);
      if (track) {
        this.preservedTracks.audioLanguage = track.language ?? null;
        this.preservedTracks.audioIdentity = playerTrackIdentity(track, next.audioTracks);
      }
    }
    const subtitleAcknowledged = this.pendingSubtitleSelection === null
      || String(next.selectedSubtitleId) === String(this.pendingSubtitleSelection);
    if (this.pendingSubtitleSelection !== null && subtitleAcknowledged) this.pendingSubtitleSelection = null;
    if (subtitleAcknowledged && next.subtitleTracks.length > 0 && next.selectedSubtitleId !== null) {
      this.preservedTracks.subtitleId = next.selectedSubtitleId;
      const track = next.subtitleTracks.find(item => item.id === next.selectedSubtitleId);
      if (track) {
        this.preservedTracks.subtitleLanguage = track.language ?? null;
        this.preservedTracks.subtitleIdentity = playerTrackIdentity(track, next.subtitleTracks);
      }
    }

    if (next.hasVideo === false && (next.phase === 'ready' || next.phase === 'playing' || next.phase === 'paused')) {
      void this.fallbackFrom(index, 'No video track');
      return;
    }
    if (next.blackFrameDetected) {
      void this.fallbackFrom(index, 'Black frame detected');
      return;
    }
    if (next.phase === 'error') {
      void this.fallbackFrom(index, next.error || 'Playback failed');
      return;
    }

    if (next.phase === 'buffering' && this.lastAdapterPhase !== 'buffering') {
      this.bufferingCount += 1;
      if (this.bufferingCount >= this.repeatedBufferingLimit) {
        void this.fallbackFrom(index, 'Repeated buffering');
        return;
      }
    }
    this.lastAdapterPhase = next.phase;

    if (next.phase === 'ready' || next.phase === 'playing' || next.phase === 'paused') {
      this.clearStartupTimer();
    }
    this.update({ phase: next.phase, adapterState: next, error: null });
  }

  private async fallbackFrom(index: number, reason: string): Promise<void> {
    if (this.fallingBack || index !== this.state.attemptIndex) return;
    this.fallingBack = true;
    try {
      const nextIndex = index + 1;
      if (nextIndex >= this.plan.attempts.length) {
        this.clearStartupTimer();
        this.loadGeneration += 1;
        this.loadAbortController?.abort();
        this.loadAbortController = null;
        this.unsubscribeAdapter?.();
        this.unsubscribeAdapter = null;
        const terminalAdapter = this.adapter;
        this.adapter = null;
        await this.destroyAdapter(terminalAdapter);
        this.update({ phase: 'error', error: reason, fallbackReason: reason });
        return;
      }
      // The next adapter owns its own fallback chain. Release the transition
      // guard before awaiting it so a synchronous load failure can advance
      // again instead of waiting for the startup timer.
      this.fallingBack = false;
      await this.loadAttempt(nextIndex, reason);
    } finally {
      this.fallingBack = false;
    }
  }

  private armStartupTimer(index: number, generation: number): void {
    this.clearStartupTimer();
    if (this.startupTimeoutMs <= 0) return;
    this.startupTimer = setTimeout(() => {
      this.startupTimer = null;
      if (generation !== this.loadGeneration || this.destroyed) return;
      void this.fallbackFrom(index, 'Startup timed out');
    }, this.startupTimeoutMs);
  }

  private clearStartupTimer(): void {
    if (this.startupTimer) clearTimeout(this.startupTimer);
    this.startupTimer = null;
  }

  private async destroyAdapter(adapter: PlayerAdapter | null): Promise<void> {
    if (!adapter) return;
    const existing = this.adapterDisposals.get(adapter);
    if (existing) return existing;
    const disposal = Promise.resolve()
      .then(() => adapter.destroy())
      .catch(() => undefined);
    this.adapterDisposals.set(adapter, disposal);
    await disposal;
  }

  private update(patch: Partial<PlayerSessionState>): void {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach(listener => listener(this.state));
  }
}
