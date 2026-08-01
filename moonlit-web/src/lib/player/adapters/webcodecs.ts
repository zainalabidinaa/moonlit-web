import { WebCodecsPlayerEngine, type WebCodecsPlayerState } from '@/lib/webcodecs-player';
import type {
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerAdapterLoadRequest,
  PlayerAdapterState,
} from '../contracts';
import { normalizeAdapterState } from '../contracts';

export interface WebCodecsEngineLike {
  subscribe(listener: (state: WebCodecsPlayerState) => void): () => void;
  load(url: string, canvas: HTMLCanvasElement): Promise<void>;
  seekTo(position: number): Promise<void>;
  seek(position: number): Promise<void>;
  play(): void;
  pause(): void;
  destroy(): void;
}

export class WebCodecsAdapter implements PlayerAdapter {
  readonly kind = 'webcodecs' as const;
  readonly capabilities: PlayerAdapterCapabilities;
  private engine: WebCodecsEngineLike | null = null;
  private unsubscribeEngine: (() => void) | null = null;
  private state = normalizeAdapterState({ phase: 'idle' });
  private readonly listeners = new Set<(state: PlayerAdapterState) => void>();

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly fullscreenRoot: HTMLElement,
    private readonly createEngine: () => WebCodecsEngineLike = () => new WebCodecsPlayerEngine(),
  ) {
    this.capabilities = {
      seek: true,
      volume: false,
      playbackRate: false,
      fullscreen: typeof fullscreenRoot.requestFullscreen === 'function',
      pictureInPicture: false,
      remotePlayback: false,
      audioTracks: false,
      subtitleTracks: false,
      seekPreview: false,
      screenshot: false,
      anime4k: false,
    };
  }

  async load(request: PlayerAdapterLoadRequest): Promise<void> {
    this.unsubscribeEngine?.();
    this.engine?.destroy();
    const engine = this.createEngine();
    this.engine = engine;
    this.emit({ phase: 'loading', position: request.position });
    this.unsubscribeEngine = engine.subscribe(state => this.handleEngineState(state));
    await engine.load(request.attempt.url, this.canvas);
    if (request.position > 0) await engine.seekTo(request.position);
    engine.play();
  }

  play() { this.engine?.play(); }
  pause() { this.engine?.pause(); }
  seek(position: number) { return this.engine?.seek(position); }
  setVolume() {}
  setMuted() {}
  setPlaybackRate() {}
  async setFullscreen(fullscreen: boolean): Promise<void> {
    if (fullscreen && !document.fullscreenElement) await this.fullscreenRoot.requestFullscreen();
    else if (!fullscreen && document.fullscreenElement) await document.exitFullscreen();
  }
  setPictureInPicture() {}
  selectAudioTrack() {}
  selectSubtitleTrack() {}

  subscribe(listener: (state: PlayerAdapterState) => void): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  destroy(): void {
    this.unsubscribeEngine?.();
    this.unsubscribeEngine = null;
    this.engine?.destroy();
    this.engine = null;
    this.listeners.clear();
  }

  private handleEngineState(next: WebCodecsPlayerState): void {
    const phase = next.error
      ? 'error'
      : next.ended
        ? 'ended'
      : !next.isReady
        ? 'loading'
        : next.isPlaying
          ? 'playing'
          : 'paused';
    this.emit({
      phase,
      position: next.currentTime,
      duration: next.duration,
      paused: !next.isPlaying,
      hasVideo: next.isReady,
      videoWidth: this.canvas.width,
      videoHeight: this.canvas.height,
      error: next.error,
    });
  }

  private emit(input: Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'>): void {
    this.state = normalizeAdapterState({ ...this.state, ...input });
    this.listeners.forEach(listener => listener(this.state));
  }
}
