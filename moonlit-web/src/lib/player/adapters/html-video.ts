import type {
  PlaybackAttempt,
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerAdapterLoadRequest,
  PlayerAdapterState,
  PlayerSeekPreview,
  PlayerTrack,
  PlayerTrackSelection,
} from '../contracts';
import { normalizeAdapterState } from '../contracts';
import { findPlayerTrackByIdentity } from '../contracts';
import { headersForExactOrigin } from '../media-proxy';

interface HlsInstanceLike {
  audioTracks?: Array<{ id?: number; name?: string; lang?: string; audioCodec?: string }>;
  audioTrack?: number;
  on(event: string, listener: (event: string, data: { fatal?: boolean; type?: string }) => void): void;
  loadSource(url: string): void;
  attachMedia(video: HTMLVideoElement): void;
  recoverMediaError(): void;
  destroy(): void;
}

interface HlsConstructorLike {
  new(config: Record<string, unknown>): HlsInstanceLike;
  isSupported(): boolean;
  Events: { ERROR: string; MANIFEST_PARSED: string; AUDIO_TRACKS_UPDATED: string; AUDIO_TRACK_SWITCHED: string };
  ErrorTypes: { MEDIA_ERROR: string };
}

interface MpegTsPlayerLike {
  on(event: string, listener: () => void): void;
  attachMediaElement(video: HTMLVideoElement): void;
  load(): void;
  destroy(): void;
}

interface MpegTsLike {
  isSupported(): boolean;
  Events: { ERROR: string };
  createPlayer(
    mediaDataSource: { type: 'mpegts'; isLive: true; url: string },
    config: Record<string, unknown>,
  ): MpegTsPlayerLike;
}

export interface HtmlVideoPlaybackDependencies {
  loadHls?: () => Promise<{ default: HlsConstructorLike }>;
  loadMpegTs?: () => Promise<{ default: MpegTsLike }>;
  onError?: (message: string) => void;
  detectBlackFrame?: (video: HTMLVideoElement) => boolean | Promise<boolean>;
  signal?: AbortSignal;
  onHlsAttached?: (hls: HlsInstanceLike | null) => void;
  createSeekPreview?: (url: string, position: number, signal?: AbortSignal) => Promise<PlayerSeekPreview | null>;
  attachPlayback?: (
    video: HTMLVideoElement,
    attempt: PlaybackAttempt,
    dependencies: HtmlVideoPlaybackDependencies,
  ) => Promise<() => void>;
}

const defaultDependencies: Required<Pick<HtmlVideoPlaybackDependencies, 'loadHls' | 'loadMpegTs'>> = {
  loadHls: () => import('hls.js') as unknown as Promise<{ default: HlsConstructorLike }>,
  loadMpegTs: () => import('mpegts.js') as unknown as Promise<{ default: MpegTsLike }>,
};

function clearMediaElement(video: HTMLVideoElement): void {
  video.removeAttribute('src');
  if (!video.isConnected) return;
  try { video.load(); } catch { /* Some test and embedded runtimes do not implement load. */ }
}

function detectBlackVideoFrame(video: HTMLVideoElement): boolean {
  if (typeof navigator !== 'undefined' && /jsdom/i.test(navigator.userAgent)) return false;
  if (video.videoWidth <= 0 || video.videoHeight <= 0 || video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) return false;
  try {
    const canvas = document.createElement('canvas');
    canvas.width = 16;
    canvas.height = 9;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (!context) return false;
    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
    let total = 0;
    let peak = 0;
    for (let index = 0; index < pixels.length; index += 4) {
      const luminance = (pixels[index] + pixels[index + 1] + pixels[index + 2]) / 3;
      total += luminance;
      peak = Math.max(peak, luminance);
    }
    return total / (pixels.length / 4) < 2 && peak < 8;
  } catch {
    // Cross-origin video commonly taints canvas. Detection is optional in that case.
    return false;
  }
}

async function captureSeekPreview(url: string, position: number, signal?: AbortSignal): Promise<PlayerSeekPreview | null> {
  if (signal?.aborted) return null;
  const preview = document.createElement('video');
  preview.preload = 'auto';
  preview.muted = true;
  preview.crossOrigin = 'anonymous';
  return new Promise(resolve => {
    let settled = false;
    const finish = (result: PlayerSeekPreview | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener('abort', onAbort);
      preview.removeAttribute('src');
      try { preview.load(); } catch { /* Detached preview cleanup can be unsupported. */ }
      resolve(result);
    };
    const onAbort = () => finish(null);
    const timer = setTimeout(() => finish(null), 2_500);
    signal?.addEventListener('abort', onAbort, { once: true });
    preview.addEventListener('error', () => finish(null), { once: true });
    preview.addEventListener('loadedmetadata', () => {
      preview.currentTime = Math.min(Math.max(0, position), preview.duration || position);
    }, { once: true });
    preview.addEventListener('seeked', () => {
      try {
        const canvas = document.createElement('canvas');
        canvas.width = 256;
        canvas.height = 144;
        const context = canvas.getContext('2d');
        if (!context || preview.videoWidth <= 0 || preview.videoHeight <= 0) return finish(null);
        context.drawImage(preview, 0, 0, canvas.width, canvas.height);
        finish({ position, imageUrl: canvas.toDataURL('image/jpeg', 0.82) });
      } catch {
        finish(null);
      }
    }, { once: true });
    preview.src = url;
    preview.load();
  });
}

export async function attachHtmlVideoPlayback(
  video: HTMLVideoElement,
  attempt: PlaybackAttempt,
  dependencies: HtmlVideoPlaybackDependencies = {},
): Promise<() => void> {
  const loadHls = dependencies.loadHls ?? defaultDependencies.loadHls;
  const loadMpegTs = dependencies.loadMpegTs ?? defaultDependencies.loadMpegTs;
  if (dependencies.signal?.aborted) throw new DOMException('Playback load aborted', 'AbortError');

  if (attempt.method === 'hls-mse' || attempt.method === 'server-remux' || attempt.method === 'server-transcode') {
    const { default: Hls } = await loadHls();
    if (dependencies.signal?.aborted) throw new DOMException('Playback load aborted', 'AbortError');
    if (!Hls.isSupported()) {
      if (attempt.requestHeaders && Object.keys(attempt.requestHeaders).length > 0) {
        throw new Error('Protected HLS requires HLS.js exact-origin header support.');
      }
      if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = attempt.url;
        return () => clearMediaElement(video);
      }
      throw new Error('HLS playback is unavailable in this browser.');
    }
    const headers = attempt.requestHeaders;
    const hls = new Hls({
      enableWorker: true,
      lowLatencyMode: attempt.isLive,
      backBufferLength: attempt.isLive ? 90 : 30,
      maxBufferLength: attempt.isLive ? 30 : 50,
      ...(headers && {
        xhrSetup: (xhr: XMLHttpRequest, url: string) => {
          for (const [name, value] of Object.entries(headersForExactOrigin(headers, attempt.url, url))) {
            xhr.setRequestHeader(name, value);
          }
        },
      }),
    });
    dependencies.onHlsAttached?.(hls);
    hls.on(Hls.Events.ERROR, (_event, data) => {
      if (!data.fatal) return;
      if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
        hls.recoverMediaError();
        return;
      }
      dependencies.onError?.('HLS transport failed.');
    });
    hls.on(Hls.Events.MANIFEST_PARSED, () => this.emitTracks());
    hls.on(Hls.Events.AUDIO_TRACKS_UPDATED, () => this.emitTracks());
    hls.on(Hls.Events.AUDIO_TRACK_SWITCHED, () => this.emitTracks());
    hls.loadSource(attempt.url);
    hls.attachMedia(video);
    return () => {
      dependencies.onHlsAttached?.(null);
      hls.destroy();
      clearMediaElement(video);
    };
  }

  if (attempt.method === 'mpeg-ts') {
    const { default: mpegts } = await loadMpegTs();
    if (dependencies.signal?.aborted) throw new DOMException('Playback load aborted', 'AbortError');
    if (!mpegts.isSupported()) {
      throw new Error('MPEG-TS playback is unavailable in this browser.');
    }
    const player = mpegts.createPlayer(
      { type: 'mpegts', isLive: true, url: attempt.url },
      {
        enableWorker: true,
        liveBufferLatencyChasing: true,
        autoCleanupSourceBuffer: true,
        ...(attempt.requestHeaders && { headers: attempt.requestHeaders }),
      },
    );
    player.on(mpegts.Events.ERROR, () => dependencies.onError?.('MPEG-TS transport failed.'));
    player.attachMediaElement(video);
    player.load();
    return () => {
      try { player.destroy(); } catch { /* A fatal mpegts teardown can throw. */ }
      clearMediaElement(video);
    };
  }

  video.src = attempt.url;
  return () => clearMediaElement(video);
}

type AudioTrackLike = {
  id?: string;
  label?: string;
  language?: string;
  kind?: string;
  enabled?: boolean;
};

type AudioTrackListLike = {
  length: number;
  [index: number]: AudioTrackLike;
};

type VideoWithTracks = HTMLVideoElement & { audioTracks?: AudioTrackListLike };

function audioTracks(video: VideoWithTracks): PlayerTrack[] {
  const list = video.audioTracks;
  if (!list) return [];
  return Array.from({ length: list.length }, (_, index) => {
    const track = list[index];
    return {
      id: track.id || index,
      kind: 'audio' as const,
      label: track.label || track.language || `Track ${index + 1}`,
      language: track.language || undefined,
      selected: track.enabled === true,
    };
  });
}

export class HtmlVideoAdapter implements PlayerAdapter {
  readonly kind = 'html-video' as const;
  readonly capabilities: PlayerAdapterCapabilities;
  private state = normalizeAdapterState({ phase: 'idle' });
  private readonly listeners = new Set<(state: PlayerAdapterState) => void>();
  private readonly eventCleanups: (() => void)[] = [];
  private transportCleanup: (() => void) | null = null;
  private pendingAttachment: Promise<void> | null = null;
  private destroyPromise: Promise<void> | null = null;
  private hlsTransport: HlsInstanceLike | null = null;
  private loadGeneration = 0;
  private pendingPosition = 0;
  private previewUrl: string | null = null;
  private previewAbortController: AbortController | null = null;
  private readonly previewCache = new Map<number, PlayerSeekPreview>();
  private subtitleElements: HTMLTrackElement[] = [];
  private blackFrameProbeTimer: ReturnType<typeof setTimeout> | null = null;
  private blackFrameProbeGeneration = 0;
  private preferredTracks: PlayerTrackSelection = {
    audioId: null,
    subtitleId: 'off',
    audioLanguage: null,
    subtitleLanguage: null,
  };

  constructor(
    private readonly video: HTMLVideoElement,
    private readonly fullscreenRoot: HTMLElement,
    private readonly dependencies: HtmlVideoPlaybackDependencies = {},
  ) {
    this.capabilities = {
      seek: true,
      volume: true,
      playbackRate: true,
      fullscreen: typeof fullscreenRoot.requestFullscreen === 'function',
      pictureInPicture: typeof video.requestPictureInPicture === 'function',
      remotePlayback: 'remote' in video,
      audioTracks: true,
      subtitleTracks: true,
      seekPreview: true,
      screenshot: false,
      anime4k: false,
    };
    video.autoplay = true;
    video.playsInline = true;
    this.bindEvents();
  }

  async load(request: PlayerAdapterLoadRequest): Promise<void> {
    const generation = this.loadGeneration + 1;
    this.loadGeneration = generation;
    await this.cleanupTransport();
    if (request.signal.aborted || generation !== this.loadGeneration) return;
    this.subtitleElements.forEach(element => element.remove());
    this.subtitleElements = [];
    this.cancelBlackFrameProbe();
    this.pendingPosition = Math.max(0, request.position);
    this.previewUrl = request.attempt.method === 'native'
      && !request.attempt.isLive
      && !request.attempt.requestHeaders
      ? request.attempt.url
      : null;
    this.capabilities.seekPreview = this.previewUrl !== null;
    this.preferredTracks = { ...request.tracks };
    this.emit({ phase: 'loading', position: this.pendingPosition, error: null, blackFrameDetected: false });
    this.installSubtitles(request.subtitles);

    const attachPlayback = this.dependencies.attachPlayback ?? attachHtmlVideoPlayback;
    const attachment = (async () => {
      const cleanup = await attachPlayback(this.video, request.attempt, {
        ...this.dependencies,
        signal: request.signal,
        onHlsAttached: hls => { this.hlsTransport = hls; },
        onError: message => this.emit({ phase: 'error', error: message }),
      });
      if (request.signal.aborted || generation !== this.loadGeneration) {
        await cleanup();
        return;
      }
      this.transportCleanup = cleanup;
    })();
    this.pendingAttachment = attachment;
    try {
      await attachment;
    } finally {
      if (this.pendingAttachment === attachment) this.pendingAttachment = null;
    }
  }

  play() { return this.video.play(); }
  pause() { this.video.pause(); }
  seek(position: number) { this.video.currentTime = Math.max(0, position); }
  setVolume(volume: number) { this.video.volume = Math.max(0, Math.min(1, volume)); }
  setMuted(muted: boolean) { this.video.muted = muted; }
  setPlaybackRate(rate: number) { this.video.playbackRate = rate; }

  async setFullscreen(fullscreen: boolean): Promise<void> {
    if (fullscreen && !document.fullscreenElement) await this.fullscreenRoot.requestFullscreen();
    else if (!fullscreen && document.fullscreenElement) await document.exitFullscreen();
  }

  async setPictureInPicture(enabled: boolean): Promise<void> {
    if (enabled && document.pictureInPictureElement !== this.video) await this.video.requestPictureInPicture();
    else if (!enabled && document.pictureInPictureElement) await document.exitPictureInPicture();
  }

  async requestRemotePlayback(): Promise<void> {
    const remote = (this.video as HTMLVideoElement & { remote?: { prompt(): Promise<void> } }).remote;
    await remote?.prompt();
  }

  selectAudioTrack(id: string | number): void {
    const list = (this.video as VideoWithTracks).audioTracks;
    if (list && list.length > 0) {
      for (let index = 0; index < list.length; index += 1) {
        const track = list[index];
        track.enabled = String(track.id || index) === String(id);
      }
    } else if (this.hlsTransport?.audioTracks) {
      const selected = this.hlsTransport.audioTracks.findIndex((track, index) => `hls:${track.id ?? index}` === String(id));
      if (selected >= 0) this.hlsTransport.audioTrack = selected;
    }
    this.emitTracks();
  }

  selectSubtitleTrack(id: string | number | 'off'): void {
    const tracks = Array.from(this.video.textTracks ?? []);
    tracks.forEach((track, index) => {
      const element = this.subtitleElementForTrack(track, index, tracks);
      const trackId = element?.dataset.moonlitTrackId ?? index;
      track.mode = id !== 'off' && String(trackId) === String(id) ? 'showing' : 'disabled';
    });
    this.emitTracks();
  }

  updateSubtitles(subtitles: PlayerAdapterLoadRequest['subtitles'], tracks: PlayerTrackSelection): void {
    this.preferredTracks = { ...tracks };
    this.installSubtitles(subtitles);
    this.restorePreferredTracks();
    this.emitTracks();
  }

  probeAudioTracks(): void {
    this.emitTracks();
  }

  requestSeekPreview(position: number, signal?: AbortSignal): Promise<PlayerSeekPreview | null> {
    if (!this.previewUrl) return Promise.resolve(null);
    const cacheKey = Math.round(Math.max(0, position));
    const cached = this.previewCache.get(cacheKey);
    if (cached) return Promise.resolve(cached);
    this.previewAbortController?.abort();
    const abortController = new AbortController();
    this.previewAbortController = abortController;
    const abort = () => abortController.abort();
    if (signal?.aborted) abort();
    else signal?.addEventListener('abort', abort, { once: true });
    const create = this.dependencies.createSeekPreview ?? captureSeekPreview;
    return create(this.previewUrl, cacheKey, abortController.signal).then(result => {
      if (!abortController.signal.aborted && result) this.previewCache.set(cacheKey, result);
      return abortController.signal.aborted ? null : result;
    }).finally(() => {
      signal?.removeEventListener('abort', abort);
    });
  }

  subscribe(listener: (state: PlayerAdapterState) => void): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  async destroy(): Promise<void> {
    if (this.destroyPromise) return this.destroyPromise;
    this.loadGeneration += 1;
    this.destroyPromise = (async () => {
      await this.cleanupTransport();
      this.eventCleanups.splice(0).forEach(cleanup => cleanup());
      this.subtitleElements.forEach(element => element.remove());
      this.subtitleElements = [];
      this.cancelBlackFrameProbe();
      this.previewUrl = null;
      this.previewAbortController?.abort();
      this.previewAbortController = null;
      this.previewCache.clear();
      this.listeners.clear();
    })();
    return this.destroyPromise;
  }

  private async cleanupTransport(): Promise<void> {
    const cleanup = this.transportCleanup;
    this.transportCleanup = null;
    if (cleanup) await cleanup();
    this.hlsTransport = null;
  }

  private bindEvents(): void {
    const on = (event: string, listener: EventListener) => {
      this.video.addEventListener(event, listener);
      this.eventCleanups.push(() => this.video.removeEventListener(event, listener));
    };
    on('loadstart', () => this.emit({ phase: 'loading' }));
    on('loadedmetadata', () => {
      if (this.pendingPosition > 0 && Number.isFinite(this.video.duration)) {
        this.video.currentTime = Math.min(this.pendingPosition, this.video.duration || this.pendingPosition);
      }
      this.restorePreferredTracks();
      this.emit(this.snapshot('loading'));
    });
    on('canplay', () => this.emit(this.snapshot(this.video.paused ? 'ready' : 'playing')));
    on('playing', () => {
      this.emit(this.snapshot('playing'));
      this.startBlackFrameProbe();
    });
    on('pause', () => {
      this.cancelBlackFrameProbe();
      this.emit(this.snapshot(this.video.ended ? 'ended' : 'paused'));
    });
    on('waiting', () => this.emit(this.snapshot('buffering')));
    on('seeking', () => this.emit(this.snapshot('buffering')));
    on('seeked', () => this.emit(this.snapshot(this.video.paused ? 'paused' : 'playing')));
    on('stalled', () => this.emit(this.snapshot('buffering')));
    on('ended', () => this.emit(this.snapshot('ended')));
    on('timeupdate', () => this.emit(this.snapshot(this.state.phase)));
    on('durationchange', () => this.emit(this.snapshot(this.state.phase)));
    on('progress', () => this.emit(this.snapshot(this.state.phase)));
    on('volumechange', () => this.emit(this.snapshot(this.state.phase)));
    on('ratechange', () => this.emit(this.snapshot(this.state.phase)));
    on('resize', () => this.emit(this.snapshot(this.state.phase)));
    on('error', () => this.emit({
      ...this.snapshot('error'),
      error: this.video.error?.message || 'HTML media playback failed.',
    }));
    const onFullscreen = () => this.emit(this.snapshot(this.state.phase));
    document.addEventListener('fullscreenchange', onFullscreen);
    this.eventCleanups.push(() => document.removeEventListener('fullscreenchange', onFullscreen));
    on('enterpictureinpicture', () => this.emit(this.snapshot(this.state.phase)));
    on('leavepictureinpicture', () => this.emit(this.snapshot(this.state.phase)));
  }

  private snapshot(phase: PlayerAdapterState['phase']): Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'> {
    const buffered = (() => {
      try {
        return this.video.buffered.length > 0 ? this.video.buffered.end(this.video.buffered.length - 1) : 0;
      } catch { return 0; }
    })();
    const nativeTracks = audioTracks(this.video as VideoWithTracks);
    const tracks = nativeTracks.length > 0 ? nativeTracks : (this.hlsTransport?.audioTracks ?? []).map((track, index): PlayerTrack => ({
      id: `hls:${track.id ?? index}`,
      kind: 'audio',
      label: track.name || track.lang || `Track ${index + 1}`,
      language: track.lang || undefined,
      codec: track.audioCodec || undefined,
      selected: this.hlsTransport?.audioTrack === index,
    }));
    const textTracks = Array.from(this.video.textTracks ?? []);
    const subtitles = textTracks.map((track, index): PlayerTrack => {
      const externalElement = this.subtitleElementForTrack(track, index, textTracks);
      return {
      id: externalElement?.dataset.moonlitTrackId ?? index,
      kind: 'subtitles',
      label: track.label || track.language || `Subtitle ${index + 1}`,
      language: track.language || undefined,
      embedded: !externalElement,
      sourceUrl: externalElement?.getAttribute('src') ?? undefined,
      selected: track.mode === 'showing',
      };
    });
    return {
      phase,
      position: this.video.currentTime,
      duration: this.video.duration,
      buffered,
      paused: this.video.paused,
      muted: this.video.muted,
      volume: this.video.volume,
      playbackRate: this.video.playbackRate,
      fullscreen: document.fullscreenElement === this.fullscreenRoot,
      pictureInPicture: document.pictureInPictureElement === this.video,
      audioTracks: tracks,
      subtitleTracks: subtitles,
      selectedAudioId: tracks.find(track => track.selected)?.id ?? null,
      selectedSubtitleId: subtitles.find(track => track.selected)?.id ?? 'off',
      hasVideo: this.video.videoWidth > 0 && this.video.videoHeight > 0,
      videoWidth: this.video.videoWidth,
      videoHeight: this.video.videoHeight,
      error: null,
    };
  }

  private emitTracks(): void {
    this.emit(this.snapshot(this.state.phase));
  }

  private installSubtitles(subtitles: PlayerAdapterLoadRequest['subtitles']): void {
    this.subtitleElements.forEach(element => element.remove());
    this.subtitleElements = [];
    for (const subtitle of subtitles) {
      const element = document.createElement('track');
      element.kind = 'subtitles';
      element.src = subtitle.url;
      element.label = subtitle.name || subtitle.lang || 'Subtitle';
      element.srclang = subtitle.lang || 'und';
      element.dataset.moonlitTrackId = subtitle.id;
      element.default = this.preferredTracks.subtitleId !== 'off' && (
        String(this.preferredTracks.subtitleId) === subtitle.id
        || (!this.preferredTracks.subtitleId
          && !!this.preferredTracks.subtitleLanguage
          && this.preferredTracks.subtitleLanguage === subtitle.lang)
      );
      this.video.appendChild(element);
      this.subtitleElements.push(element);
    }
  }

  private restorePreferredTracks(): void {
    const audioList = (this.video as VideoWithTracks).audioTracks;
    if (audioList && (this.preferredTracks.audioId !== null || this.preferredTracks.audioLanguage || this.preferredTracks.audioIdentity)) {
      let selectedIndex = -1;
      for (let index = 0; index < audioList.length; index += 1) {
        const track = audioList[index];
        if (this.preferredTracks.audioId !== null && String(track.id ?? index) === String(this.preferredTracks.audioId)) {
          selectedIndex = index;
          break;
        }
      }
      if (selectedIndex < 0 && this.preferredTracks.audioIdentity) {
        const normalized = audioTracks(this.video as VideoWithTracks);
        const match = findPlayerTrackByIdentity(normalized, this.preferredTracks.audioIdentity);
        selectedIndex = match ? normalized.indexOf(match) : -1;
      }
      if (selectedIndex < 0 && this.preferredTracks.audioLanguage && !this.preferredTracks.audioIdentity) {
        for (let index = 0; index < audioList.length; index += 1) {
          if (audioList[index].language?.toLowerCase() === this.preferredTracks.audioLanguage.toLowerCase()) {
            selectedIndex = index;
            break;
          }
        }
      }
      if (selectedIndex >= 0) {
        for (let index = 0; index < audioList.length; index += 1) {
          audioList[index].enabled = index === selectedIndex;
        }
      }
    }
    if (!audioList && this.hlsTransport?.audioTracks && (this.preferredTracks.audioId !== null || this.preferredTracks.audioLanguage || this.preferredTracks.audioIdentity)) {
      const hlsTracks = this.hlsTransport.audioTracks;
      let selectedIndex = this.preferredTracks.audioId === null
        ? -1
        : hlsTracks.findIndex((track, index) => `hls:${track.id ?? index}` === String(this.preferredTracks.audioId));
      if (selectedIndex < 0 && this.preferredTracks.audioLanguage && !this.preferredTracks.audioIdentity) {
        selectedIndex = hlsTracks.findIndex(track => track.lang?.toLowerCase() === this.preferredTracks.audioLanguage?.toLowerCase());
      }
      if (selectedIndex < 0 && this.preferredTracks.audioIdentity) {
        const normalized = hlsTracks.map((track, index): PlayerTrack => ({
          id: `hls:${track.id ?? index}`,
          kind: 'audio',
          label: track.name || track.lang || `Track ${index + 1}`,
          language: track.lang,
          selected: this.hlsTransport?.audioTrack === index,
        }));
        const match = findPlayerTrackByIdentity(normalized, this.preferredTracks.audioIdentity);
        selectedIndex = match ? normalized.indexOf(match) : -1;
      }
      if (selectedIndex >= 0) this.hlsTransport.audioTrack = selectedIndex;
    }

    const textTracks = Array.from(this.video.textTracks ?? []);
    if (this.preferredTracks.subtitleId === 'off') {
      textTracks.forEach(track => { track.mode = 'disabled'; });
      return;
    }
    let selectedSubtitle = -1;
    if (this.preferredTracks.subtitleId !== null) {
      selectedSubtitle = textTracks.findIndex((track, index) => (
        String(this.subtitleElementForTrack(track, index, textTracks)?.dataset.moonlitTrackId ?? index)
          === String(this.preferredTracks.subtitleId)
      ));
    }
    if (selectedSubtitle < 0 && this.preferredTracks.subtitleLanguage && !this.preferredTracks.subtitleIdentity) {
      selectedSubtitle = textTracks.findIndex(track => (
        track.language?.toLowerCase() === this.preferredTracks.subtitleLanguage?.toLowerCase()
      ));
    }
    if (selectedSubtitle < 0 && this.preferredTracks.subtitleIdentity) {
      const normalized = textTracks.map((track, index): PlayerTrack => {
        const element = this.subtitleElementForTrack(track, index, textTracks);
        return {
          id: element?.dataset.moonlitTrackId ?? index,
          kind: 'subtitles',
          label: track.label || track.language || `Subtitle ${index + 1}`,
          language: track.language || undefined,
          embedded: !element,
          sourceUrl: element?.getAttribute('src') ?? undefined,
          selected: track.mode === 'showing',
        };
      });
      const match = findPlayerTrackByIdentity(normalized, this.preferredTracks.subtitleIdentity);
      selectedSubtitle = match ? normalized.indexOf(match) : -1;
    }
    if (selectedSubtitle >= 0) {
      textTracks.forEach((track, index) => { track.mode = index === selectedSubtitle ? 'showing' : 'disabled'; });
    }
  }

  private subtitleElementForTrack(
    track: TextTrack,
    index: number,
    allTracks: TextTrack[],
  ): HTMLTrackElement | undefined {
    const exact = this.subtitleElements.find(element => element.track === track);
    if (exact) return exact;
    // Appended external tracks follow any embedded tracks. This fallback is
    // needed in runtimes that do not expose HTMLTrackElement.track identity.
    const externalStart = Math.max(0, allTracks.length - this.subtitleElements.length);
    return index >= externalStart ? this.subtitleElements[index - externalStart] : undefined;
  }

  private startBlackFrameProbe(): void {
    this.cancelBlackFrameProbe();
    const generation = this.blackFrameProbeGeneration;
    const detect = this.dependencies.detectBlackFrame ?? detectBlackVideoFrame;
    let consecutiveBlackFrames = 0;
    const sample = async () => {
      if (generation !== this.blackFrameProbeGeneration || this.state.phase !== 'playing') return;
      const isBlack = await detect(this.video);
      if (generation !== this.blackFrameProbeGeneration || this.state.phase !== 'playing') return;
      if (!isBlack) return;
      consecutiveBlackFrames += 1;
      if (consecutiveBlackFrames >= 3) {
        this.emit({ ...this.snapshot('playing'), blackFrameDetected: true });
        return;
      }
      this.blackFrameProbeTimer = setTimeout(sample, 2_000);
    };
    // Allow normal fades and title cards to clear before sampling. A single
    // non-black sample proves decoded video and ends this startup-only probe.
    this.blackFrameProbeTimer = setTimeout(sample, 2_000);
  }

  private cancelBlackFrameProbe(): void {
    this.blackFrameProbeGeneration += 1;
    if (this.blackFrameProbeTimer) clearTimeout(this.blackFrameProbeTimer);
    this.blackFrameProbeTimer = null;
  }

  private emit(input: Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'>): void {
    this.state = normalizeAdapterState({ ...this.state, ...input });
    this.listeners.forEach(listener => listener(this.state));
  }
}
