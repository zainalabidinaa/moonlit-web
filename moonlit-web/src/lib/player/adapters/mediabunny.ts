import { MediabunnyRemuxer, type RemuxerCallbacks } from '@/lib/mediabunny-remuxer';
import type {
  PlaybackAttempt,
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerAdapterLoadRequest,
  PlayerAdapterState,
} from '../contracts';
import { HtmlVideoAdapter, type HtmlVideoPlaybackDependencies } from './html-video';

interface RemuxerLike {
  start(url: string, callbacks: RemuxerCallbacks): Promise<void>;
  destroy(): Promise<void> | void;
}

interface SourceBufferLike {
  updating: boolean;
  appendBuffer(data: BufferSource): void;
  addEventListener(event: string, listener: () => void, options?: AddEventListenerOptions): void;
}

interface MediaSourceLike {
  readyState: string;
  addSourceBuffer(mimeType: string): SourceBufferLike;
  addEventListener(event: string, listener: () => void, options?: AddEventListenerOptions): void;
  endOfStream(): void;
}

export interface MediabunnyPlaybackDependencies {
  createRemuxer?: () => RemuxerLike;
  createMediaSource?: () => MediaSourceLike;
  createObjectURL?: (source: MediaSourceLike) => string;
  revokeObjectURL?: (url: string) => void;
  onError?: (message: string) => void;
}

export async function attachMediabunnyPlayback(
  video: HTMLVideoElement,
  attempt: PlaybackAttempt,
  dependencies: MediabunnyPlaybackDependencies = {},
): Promise<() => Promise<void>> {
  const remuxer = dependencies.createRemuxer?.() ?? new MediabunnyRemuxer();
  const mediaSource = dependencies.createMediaSource?.() ?? new MediaSource();
  const createObjectURL = dependencies.createObjectURL ?? (source => URL.createObjectURL(source as unknown as MediaSource));
  const revokeObjectURL = dependencies.revokeObjectURL ?? URL.revokeObjectURL.bind(URL);
  const objectUrl = createObjectURL(mediaSource);
  const chunks: Uint8Array[] = [];
  let sourceBuffer: SourceBufferLike | null = null;
  let mimeType: string | null = null;
  let cancelled = false;
  let remuxComplete = false;
  let streamEnded = false;

  const endIfDrained = () => {
    if (cancelled || streamEnded || !remuxComplete || sourceBuffer?.updating || chunks.length > 0 || mediaSource.readyState !== 'open') return;
    try {
      mediaSource.endOfStream();
      streamEnded = true;
    } catch { /* The source may already have ended. */ }
  };

  const appendNext = () => {
    if (cancelled || !sourceBuffer || sourceBuffer.updating) return;
    const chunk = chunks.shift();
    if (!chunk) {
      endIfDrained();
      return;
    }
    try {
      sourceBuffer.addEventListener('updateend', appendNext, { once: true });
      sourceBuffer.appendBuffer(chunk as BufferSource);
    } catch (error) {
      dependencies.onError?.(error instanceof Error ? error.message : 'Mediabunny buffer append failed.');
    }
  };

  const createSourceBuffer = () => {
    if (cancelled || sourceBuffer || !mimeType || mediaSource.readyState !== 'open') return;
    try {
      sourceBuffer = mediaSource.addSourceBuffer(mimeType);
      appendNext();
    } catch (error) {
      dependencies.onError?.(error instanceof Error ? error.message : 'Mediabunny source buffer failed.');
    }
  };

  mediaSource.addEventListener('sourceopen', createSourceBuffer, { once: true });
  video.src = objectUrl;

  void remuxer.start(attempt.url, {
    onReady: value => {
      mimeType = value;
      createSourceBuffer();
    },
    onChunk: chunk => {
      chunks.push(chunk);
      appendNext();
    },
    onError: error => dependencies.onError?.(error.message),
  }).then(() => {
    remuxComplete = true;
    appendNext();
    endIfDrained();
  });

  return async () => {
    cancelled = true;
    await remuxer.destroy();
    try {
      if (mediaSource.readyState === 'open') mediaSource.endOfStream();
    } catch { /* Ignore teardown races. */ }
    video.removeAttribute('src');
    revokeObjectURL(objectUrl);
  };
}

export class MediabunnyAdapter implements PlayerAdapter {
  readonly kind = 'mediabunny' as const;
  readonly capabilities: PlayerAdapterCapabilities;
  private readonly inner: HtmlVideoAdapter;

  constructor(
    video: HTMLVideoElement,
    fullscreenRoot: HTMLElement,
    dependencies: MediabunnyPlaybackDependencies & { attachPlayback?: HtmlVideoPlaybackDependencies['attachPlayback'] } = {},
  ) {
    const attachPlayback = dependencies.attachPlayback ?? ((element, target, runtimeDependencies) => (
      attachMediabunnyPlayback(element, target, {
        ...dependencies,
        onError: runtimeDependencies.onError ?? dependencies.onError,
      })
    ));
    this.inner = new HtmlVideoAdapter(video, fullscreenRoot, { attachPlayback });
    this.capabilities = {
      ...this.inner.capabilities,
      audioTracks: false,
      subtitleTracks: true,
      seekPreview: false,
    };
  }

  load(request: PlayerAdapterLoadRequest) { return this.inner.load(request); }
  play() { return this.inner.play(); }
  pause() { return this.inner.pause(); }
  seek(position: number) { return this.inner.seek(position); }
  setVolume(volume: number) { return this.inner.setVolume(volume); }
  setMuted(muted: boolean) { return this.inner.setMuted(muted); }
  setPlaybackRate(rate: number) { return this.inner.setPlaybackRate(rate); }
  setFullscreen(fullscreen: boolean) { return this.inner.setFullscreen(fullscreen); }
  setPictureInPicture(enabled: boolean) { return this.inner.setPictureInPicture(enabled); }
  requestRemotePlayback() { return this.inner.requestRemotePlayback(); }
  selectAudioTrack() {}
  selectSubtitleTrack(id: string | number | 'off') { return this.inner.selectSubtitleTrack(id); }
  updateSubtitles(subtitles: PlayerAdapterLoadRequest['subtitles'], tracks: PlayerAdapterLoadRequest['tracks']) {
    return this.inner.updateSubtitles(subtitles, tracks);
  }
  subscribe(listener: (state: PlayerAdapterState) => void) { return this.inner.subscribe(listener); }
  destroy() { return this.inner.destroy(); }
}
