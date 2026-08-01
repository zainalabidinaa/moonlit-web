import type { SubtitleItem } from '@/lib/stremio';
import type {
  PlaybackAttempt,
  PlaybackPlan,
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerAdapterState,
  PlayerTrackSelection,
} from './contracts';

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
  private startOptions: PlayerSessionStartOptions | null = null;
  private preservedPosition = 0;
  private preservedTracks: PlayerTrackSelection = {
    audioId: null,
    subtitleId: 'off',
    audioLanguage: null,
    subtitleLanguage: null,
  };
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

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  async start(options: PlayerSessionStartOptions): Promise<void> {
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
    this.clearStartupTimer();
    this.unsubscribeAdapter?.();
    this.unsubscribeAdapter = null;
    const adapter = this.adapter;
    this.adapter = null;
    if (adapter) await adapter.destroy();
    this.listeners.clear();
  }

  play() { return this.adapter?.play(); }
  pause() { return this.adapter?.pause(); }
  seek(position: number) {
    if (!this.adapter?.capabilities.seek) return;
    this.preservedPosition = Math.max(0, position);
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
  selectAudioTrack(id: string | number) {
    if (!this.adapter?.capabilities.audioTracks) return;
    this.preservedTracks.audioId = id;
    return this.adapter.selectAudioTrack(id);
  }
  selectSubtitleTrack(id: string | number | 'off') {
    if (!this.adapter?.capabilities.subtitleTracks) return;
    this.preservedTracks.subtitleId = id;
    return this.adapter.selectSubtitleTrack(id);
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
    if (!attempt || !options) return;

    this.clearStartupTimer();
    this.unsubscribeAdapter?.();
    this.unsubscribeAdapter = null;
    const previous = this.adapter;
    this.adapter = null;
    if (previous) await previous.destroy();

    const adapter = this.createAdapter(attempt);
    this.adapter = adapter;
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
    this.armStartupTimer(index);

    try {
      await adapter.load({
        attempt,
        position: this.preservedPosition,
        tracks: { ...this.preservedTracks },
        subtitles: options.subtitles,
      });
    } catch (error) {
      if (this.adapter === adapter) {
        await this.fallbackFrom(index, error instanceof Error ? error.message : 'Adapter failed to load');
      }
    }
  }

  private handleAdapterState(adapter: PlayerAdapter, index: number, next: PlayerAdapterState): void {
    if (this.adapter !== adapter || this.state.attemptIndex !== index) return;

    if (next.position > 0) this.preservedPosition = next.position;
    if (next.audioTracks.length > 0 && next.selectedAudioId !== null) {
      this.preservedTracks.audioId = next.selectedAudioId;
      const track = next.audioTracks.find(item => item.id === next.selectedAudioId);
      if (track?.language) this.preservedTracks.audioLanguage = track.language;
    }
    if (next.subtitleTracks.length > 0 && next.selectedSubtitleId !== null) {
      this.preservedTracks.subtitleId = next.selectedSubtitleId;
      const track = next.subtitleTracks.find(item => item.id === next.selectedSubtitleId);
      if (track?.language) this.preservedTracks.subtitleLanguage = track.language;
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

  private armStartupTimer(index: number): void {
    this.clearStartupTimer();
    if (this.startupTimeoutMs <= 0) return;
    this.startupTimer = setTimeout(() => {
      this.startupTimer = null;
      void this.fallbackFrom(index, 'Startup timed out');
    }, this.startupTimeoutMs);
  }

  private clearStartupTimer(): void {
    if (this.startupTimer) clearTimeout(this.startupTimer);
    this.startupTimer = null;
  }

  private update(patch: Partial<PlayerSessionState>): void {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach(listener => listener(this.state));
  }
}
