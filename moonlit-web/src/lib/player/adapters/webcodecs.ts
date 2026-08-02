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
  private loadGeneration = 0;
  private fullscreen = false;
  private destroyPromise: Promise<void> | null = null;
  private readonly disposedEngines = new WeakSet<WebCodecsEngineLike>();
  private readonly onFullscreenChange: () => void;

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
    this.onFullscreenChange = () => {
      this.fullscreen = document.fullscreenElement === this.fullscreenRoot;
      this.emit({ phase: this.state.phase, fullscreen: this.fullscreen });
    };
    document.addEventListener('fullscreenchange', this.onFullscreenChange);
  }

  async load(request: PlayerAdapterLoadRequest): Promise<void> {
    const generation = this.loadGeneration + 1;
    this.loadGeneration = generation;
    this.unsubscribeEngine?.();
    this.disposeEngine(this.engine);
    const engine = this.createEngine();
    this.engine = engine;
    this.emit({ phase: 'loading', position: request.position });
    this.unsubscribeEngine = engine.subscribe(state => this.handleEngineState(state));
    await engine.load(request.attempt.url, this.canvas);
    if (request.signal.aborted || generation !== this.loadGeneration || this.engine !== engine) {
      this.disposeEngine(engine);
      return;
    }
    if (request.position > 0) await engine.seekTo(request.position);
    if (request.signal.aborted || generation !== this.loadGeneration || this.engine !== engine) {
      this.disposeEngine(engine);
      return;
    }
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
    this.fullscreen = fullscreen;
    this.emit({ phase: this.state.phase, fullscreen });
  }
  setPictureInPicture() {}
  selectAudioTrack() {}
  selectSubtitleTrack() {}

  subscribe(listener: (state: PlayerAdapterState) => void): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  destroy(): Promise<void> {
    if (this.destroyPromise) return this.destroyPromise;
    this.loadGeneration += 1;
    this.destroyPromise = Promise.resolve().then(() => {
      this.unsubscribeEngine?.();
      this.unsubscribeEngine = null;
      this.disposeEngine(this.engine);
      this.engine = null;
      document.removeEventListener('fullscreenchange', this.onFullscreenChange);
      this.listeners.clear();
    });
    return this.destroyPromise;
  }

  private disposeEngine(engine: WebCodecsEngineLike | null): void {
    if (!engine || this.disposedEngines.has(engine)) return;
    this.disposedEngines.add(engine);
    engine.destroy();
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
      fullscreen: this.fullscreen,
      error: next.error,
    });
  }

  private emit(input: Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'>): void {
    this.state = normalizeAdapterState({ ...this.state, ...input });
    this.listeners.forEach(listener => listener(this.state));
  }
}
