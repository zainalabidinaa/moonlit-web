import {
  initialMpvState,
  mpv,
  onMpvEvent,
  reduceMpvEvent,
  type MpvEvent,
  type MpvState,
} from '@/lib/platform/mpv';
import { subtitlePrefsToMpvProps } from '@/lib/platform/mpv-subtitle-style';
import {
  loadSubtitlePreferences,
  subscribeSubtitlePreferences,
  type SubtitlePreferences,
} from '@/lib/subtitle-preferences';
import type {
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerAdapterLoadRequest,
  PlayerAdapterState,
  PlayerTrack,
  PlayerTrackSelection,
} from '../contracts';
import { normalizeAdapterState } from '../contracts';

export interface MpvAdapterBridge {
  start(payload: { url: string; startAtSec?: number; headers?: Record<string, string> }): Promise<void>;
  stop(): Promise<void>;
  setProp(name: string, value: unknown): Promise<void>;
  getProp<T = unknown>(name: string): Promise<T>;
  command(parts: string[]): Promise<void>;
  subAdd(url: string, options?: { title?: string; lang?: string; select?: boolean }): Promise<void>;
  listen(listener: (event: MpvEvent) => void): Promise<() => void>;
  setGeometry?(geometry: {
    cssLeft: number;
    cssTop: number;
    cssWidth: number;
    cssHeight: number;
    cssViewW: number;
    cssViewH: number;
  }): Promise<void>;
  setFullscreen(fullscreen: boolean): Promise<void>;
  setPictureInPicture(enabled: boolean): Promise<void>;
}

const defaultBridge: MpvAdapterBridge = {
  start: payload => mpv.start(payload),
  stop: () => mpv.stop(),
  setProp: (name, value) => mpv.setProp(name, value),
  getProp: name => mpv.getProp(name),
  command: parts => mpv.command(parts),
  subAdd: (url, options) => mpv.subAdd(url, options),
  listen: listener => onMpvEvent(listener),
  setGeometry: geometry => mpv.setGeometry(geometry),
  setFullscreen: async fullscreen => {
    const { getCurrentWindow } = await import('@tauri-apps/api/window');
    await getCurrentWindow().setFullscreen(fullscreen);
  },
  setPictureInPicture: async enabled => {
    const { getCurrentWindow, LogicalPosition, LogicalSize } = await import('@tauri-apps/api/window');
    const windowHandle = getCurrentWindow();
    await windowHandle.setAlwaysOnTop(enabled);
    if (enabled) {
      await windowHandle.setSize(new LogicalSize(480, 270));
      await windowHandle.setPosition(new LogicalPosition(window.screen.availWidth - 500, window.screen.availHeight - 320));
    }
  },
};

function tracks(state: MpvState, kind: 'audio' | 'subtitles'): PlayerTrack[] {
  const list = kind === 'audio' ? state.tracks.audio : state.tracks.subs;
  return list.map(track => ({
    id: track.id,
    kind,
    label: track.label,
    language: track.lang,
    embedded: !track.external,
    selected: track.selected,
  }));
}

function rawSubtitleUrl(url: string): string {
  const match = url.match(/^\/api\/stremio\/vtt\?url=(.*)$/);
  if (!match) return url;
  try { return decodeURIComponent(match[1]); } catch { return match[1]; }
}

function mpvTrackId(id: string | number | 'off' | null): string | number | null {
  if (typeof id === 'number' && Number.isFinite(id)) return id;
  if (typeof id === 'string' && /^\d+$/.test(id)) return Number(id);
  return null;
}

export class MpvAdapter implements PlayerAdapter {
  readonly kind = 'mpv' as const;
  readonly capabilities: PlayerAdapterCapabilities = {
    seek: true,
    volume: true,
    playbackRate: true,
    fullscreen: true,
    pictureInPicture: true,
    remotePlayback: false,
    audioTracks: true,
    subtitleTracks: true,
    seekPreview: false,
    screenshot: false,
    anime4k: false,
  };
  private mpvState = initialMpvState();
  private state = normalizeAdapterState({ phase: 'idle' });
  private readonly listeners = new Set<(state: PlayerAdapterState) => void>();
  private unlisten: (() => void) | null = null;
  private geometryCleanup: (() => void) | null = null;
  private subtitlePreferenceCleanup: (() => void) | null = null;
  private receivedPosition = false;
  private requestedTracks: PlayerTrackSelection = {
    audioId: null,
    subtitleId: null,
    audioLanguage: null,
    subtitleLanguage: null,
  };
  private restoredAudioLanguage = false;
  private restoredSubtitleLanguage = false;

  constructor(private readonly bridge: MpvAdapterBridge = defaultBridge) {}

  async load(request: PlayerAdapterLoadRequest): Promise<void> {
    this.unlisten?.();
    this.geometryCleanup?.();
    this.geometryCleanup = null;
    this.subtitlePreferenceCleanup?.();
    this.subtitlePreferenceCleanup = null;
    this.mpvState = initialMpvState();
    this.receivedPosition = false;
    this.requestedTracks = { ...request.tracks };
    this.restoredAudioLanguage = false;
    this.restoredSubtitleLanguage = false;
    this.emit({ phase: 'loading', position: request.position });
    this.unlisten = await this.bridge.listen(event => this.handleEvent(event));
    await this.bridge.start({
      url: request.attempt.url,
      startAtSec: request.position || undefined,
      headers: request.attempt.requestHeaders,
    });
    const requestedAudioId = mpvTrackId(request.tracks.audioId);
    if (requestedAudioId !== null) await this.bridge.setProp('aid', requestedAudioId);
    if (request.tracks.subtitleId === 'off') {
      await this.bridge.setProp('sid', 'no');
    } else {
      const requestedSubtitleId = mpvTrackId(request.tracks.subtitleId);
      if (requestedSubtitleId !== null) await this.bridge.setProp('sid', requestedSubtitleId);
    }
    await this.applySubtitlePreferences(loadSubtitlePreferences());
    this.subtitlePreferenceCleanup = subscribeSubtitlePreferences(preferences => {
      void this.applySubtitlePreferences(preferences);
    });
    if (this.bridge.setGeometry) {
      const syncGeometry = () => this.bridge.setGeometry?.({
        cssLeft: 0,
        cssTop: 0,
        cssWidth: window.innerWidth,
        cssHeight: window.innerHeight,
        cssViewW: window.innerWidth,
        cssViewH: window.innerHeight,
      }).catch(() => undefined);
      await syncGeometry();
      window.addEventListener('resize', syncGeometry);
      this.geometryCleanup = () => window.removeEventListener('resize', syncGeometry);
    }
    for (const subtitle of request.subtitles) {
      await this.bridge.subAdd(rawSubtitleUrl(subtitle.url), {
        title: subtitle.name || subtitle.lang,
        lang: subtitle.lang,
        select: String(request.tracks.subtitleId) === subtitle.id,
      });
    }
  }

  play() { return this.bridge.setProp('pause', false); }
  pause() { return this.bridge.setProp('pause', true); }
  seek(position: number) { return this.bridge.command(['seek', String(position), 'absolute']); }
  setVolume(volume: number) { return this.bridge.setProp('volume', Math.max(0, Math.min(1, volume)) * 100); }
  setMuted(muted: boolean) { return this.bridge.setProp('mute', muted); }
  setPlaybackRate(rate: number) { return this.bridge.setProp('speed', rate); }
  setFullscreen(fullscreen: boolean) { return this.bridge.setFullscreen(fullscreen); }
  setPictureInPicture(enabled: boolean) { return this.bridge.setPictureInPicture(enabled); }
  selectAudioTrack(id: string | number) { return this.bridge.setProp('aid', id); }
  selectSubtitleTrack(id: string | number | 'off') { return this.bridge.setProp('sid', id === 'off' ? 'no' : id); }

  async probeAudioTracks(): Promise<void> {
    const raw = await this.bridge.getProp('track-list');
    this.handleEvent({ event: 'property-change', name: 'track-list', data: raw });
  }

  subscribe(listener: (state: PlayerAdapterState) => void): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  async destroy(): Promise<void> {
    this.geometryCleanup?.();
    this.geometryCleanup = null;
    this.unlisten?.();
    this.unlisten = null;
    this.subtitlePreferenceCleanup?.();
    this.subtitlePreferenceCleanup = null;
    await this.bridge.stop();
    this.listeners.clear();
  }

  private handleEvent(event: MpvEvent): void {
    if (event.event === 'property-change' && event.name === 'time-pos' && typeof event.data === 'number') {
      this.receivedPosition = true;
    }
    this.mpvState = reduceMpvEvent(this.mpvState, event);
    if (event.event === 'property-change' && event.name === 'track-list') this.restorePreferredLanguages();
    const current = this.mpvState;
    const phase = current.error
      ? 'error'
      : current.ended
        ? 'ended'
        : current.buffering
          ? 'buffering'
          : !current.loaded
            ? 'loading'
            : current.paused
              ? 'paused'
              : this.receivedPosition
                ? 'playing'
                : 'ready';
    const audio = tracks(current, 'audio');
    const subtitles = tracks(current, 'subtitles');
    this.emit({
      phase,
      position: current.position,
      duration: current.duration,
      buffered: current.cacheTime,
      paused: current.paused,
      muted: current.muted,
      volume: current.volume / 100,
      playbackRate: current.speed,
      audioTracks: audio,
      subtitleTracks: subtitles,
      selectedAudioId: audio.find(track => track.selected)?.id ?? null,
      selectedSubtitleId: subtitles.find(track => track.selected)?.id ?? 'off',
      hasVideo: current.loaded,
      error: current.error,
    });
  }

  private emit(input: Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'>): void {
    this.state = normalizeAdapterState({ ...this.state, ...input });
    this.listeners.forEach(listener => listener(this.state));
  }

  private async applySubtitlePreferences(preferences: SubtitlePreferences): Promise<void> {
    await Promise.all(Object.entries(subtitlePrefsToMpvProps(preferences)).map(([name, value]) => (
      this.bridge.setProp(name, value)
    )));
  }

  private restorePreferredLanguages(): void {
    if (!this.restoredAudioLanguage && mpvTrackId(this.requestedTracks.audioId) === null && this.requestedTracks.audioLanguage) {
      const match = this.mpvState.tracks.audio.find(track => (
        track.lang?.toLowerCase() === this.requestedTracks.audioLanguage?.toLowerCase()
      ));
      if (match) {
        this.restoredAudioLanguage = true;
        void this.bridge.setProp('aid', match.id);
      }
    }
    if (
      !this.restoredSubtitleLanguage
      && this.requestedTracks.subtitleId !== 'off'
      && mpvTrackId(this.requestedTracks.subtitleId) === null
      && this.requestedTracks.subtitleLanguage
    ) {
      const match = this.mpvState.tracks.subs.find(track => (
        track.lang?.toLowerCase() === this.requestedTracks.subtitleLanguage?.toLowerCase()
      ));
      if (match) {
        this.restoredSubtitleLanguage = true;
        void this.bridge.setProp('sid', match.id);
      }
    }
  }
}
