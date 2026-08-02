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

interface CanvasOwnership {
  width: number;
  height: number;
}

const canvasOwners = new WeakMap<HTMLCanvasElement, CanvasOwnership>();

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
  private readonly canvasOwnership = new WeakMap<WebCodecsEngineLike, {
    owner: CanvasOwnership;
    initialWidth: number;
    initialHeight: number;
  }>();
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
    const owner = { width: this.canvas.width, height: this.canvas.height };
    this.canvasOwnership.set(engine, {
      owner,
      initialWidth: this.canvas.width,
      initialHeight: this.canvas.height,
    });
    canvasOwners.set(this.canvas, owner);
    this.engine = engine;
    this.emit({ phase: 'loading', position: request.position });
    this.unsubscribeEngine = engine.subscribe(state => this.handleEngineState(state, engine));
    await engine.load(request.attempt.url, this.canvas);
    if (request.signal.aborted || generation !== this.loadGeneration || this.engine !== engine) {
      this.disposeEngine(engine, true);
      this.restoreCanvasAfterLateLoad(engine);
      return;
    }
    this.recordCanvasOwnership(engine);
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
      const engine = this.engine;
      this.disposeEngine(engine);
      this.restoreCanvasAfterLateLoad(engine);
      this.releaseCanvasOwnership(engine);
      this.engine = null;
      document.removeEventListener('fullscreenchange', this.onFullscreenChange);
      this.listeners.clear();
    });
    return this.destroyPromise;
  }

  private disposeEngine(engine: WebCodecsEngineLike | null, afterLateLoad = false): void {
    if (!engine || (!afterLateLoad && this.disposedEngines.has(engine))) return;
    if (!this.disposedEngines.has(engine)) this.disposedEngines.add(engine);
    engine.destroy();
  }

  private recordCanvasOwnership(engine: WebCodecsEngineLike): void {
    const ownership = this.canvasOwnership.get(engine)?.owner;
    if (!ownership || canvasOwners.get(this.canvas) !== ownership) return;
    ownership.width = this.canvas.width;
    ownership.height = this.canvas.height;
  }

  private restoreCanvasAfterLateLoad(engine: WebCodecsEngineLike | null): void {
    if (!engine) return;
    const claim = this.canvasOwnership.get(engine);
    if (!claim) return;
    const currentOwner = canvasOwners.get(this.canvas);
    const width = currentOwner && currentOwner !== claim.owner ? currentOwner.width : claim.initialWidth;
    const height = currentOwner && currentOwner !== claim.owner ? currentOwner.height : claim.initialHeight;
    if (this.canvas.width !== width) this.canvas.width = width;
    if (this.canvas.height !== height) this.canvas.height = height;
  }

  private releaseCanvasOwnership(engine: WebCodecsEngineLike | null): void {
    if (!engine) return;
    const ownership = this.canvasOwnership.get(engine)?.owner;
    if (ownership && canvasOwners.get(this.canvas) === ownership) canvasOwners.delete(this.canvas);
  }

  private handleEngineState(next: WebCodecsPlayerState, engine: WebCodecsEngineLike): void {
    this.recordCanvasOwnership(engine);
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
