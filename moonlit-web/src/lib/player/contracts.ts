import type { SubtitleItem } from '@/lib/stremio';
import type { StreamItem } from '@/lib/types';

export type PlayerAdapterKind = 'html-video' | 'mediabunny' | 'webcodecs' | 'mpv';

export type PlaybackMethod =
  | 'native'
  | 'native-hls'
  | 'hls-mse'
  | 'mpeg-ts'
  | 'chromium-mkv'
  | 'mediabunny-remux'
  | 'webcodecs'
  | 'server-remux'
  | 'server-transcode'
  | 'mpv';

export type PlaybackOutcome = 'play-here' | 'external' | 'unsupported';

export interface PlayerMetadata {
  mediaId: string;
  mediaType: string;
  title: string;
  secondaryTitle?: string;
  logo?: string;
  poster?: string;
  background?: string;
  season?: number;
  episode?: number;
}

export interface PlayerTrackSelection {
  audioId: string | number | null;
  subtitleId: string | number | 'off' | null;
  audioLanguage: string | null;
  subtitleLanguage: string | null;
}

export interface PlayerLaunch {
  type: string;
  id: string;
  streamUrl?: string;
  streams?: StreamItem[];
  metadata: PlayerMetadata;
  startPosition?: number;
  subtitles?: SubtitleItem[];
  isLive?: boolean;
  requestHeaders?: Record<string, string>;
  preferredTracks?: Partial<PlayerTrackSelection>;
}

export interface NormalizedPlayerLaunch extends Omit<PlayerLaunch, 'startPosition' | 'isLive' | 'preferredTracks'> {
  startPosition: number;
  isLive: boolean;
  preferredTracks: PlayerTrackSelection;
}

export function normalizePlayerLaunch(launch: PlayerLaunch): NormalizedPlayerLaunch {
  const startPosition = Number.isFinite(launch.startPosition)
    ? Math.max(0, launch.startPosition ?? 0)
    : 0;
  return {
    ...launch,
    startPosition,
    isLive: launch.isLive ?? (launch.type === 'tv' || launch.type === 'live'),
    preferredTracks: {
      audioId: launch.preferredTracks?.audioId ?? null,
      subtitleId: launch.preferredTracks?.subtitleId ?? null,
      audioLanguage: launch.preferredTracks?.audioLanguage ?? null,
      subtitleLanguage: launch.preferredTracks?.subtitleLanguage ?? null,
    },
  };
}

export interface PlaybackAttempt {
  id: string;
  adapter: PlayerAdapterKind;
  method: PlaybackMethod;
  url: string;
  sourceType: 'video' | 'hls' | 'mpeg-ts' | 'mkv';
  isLive: boolean;
  reason: string;
  requestHeaders?: Record<string, string>;
}

export interface PlaybackPlan {
  outcome: PlaybackOutcome;
  label: string;
  detail: string;
  stream: StreamItem;
  attempts: PlaybackAttempt[];
  externalUrl?: string;
}

export type AdapterPhase =
  | 'idle'
  | 'loading'
  | 'ready'
  | 'playing'
  | 'paused'
  | 'buffering'
  | 'ended'
  | 'error';

export interface PlayerTrack {
  id: string | number;
  kind: 'audio' | 'subtitles';
  label: string;
  language?: string;
  codec?: string;
  channels?: string;
  embedded?: boolean;
  selected: boolean;
}

export interface PlayerAdapterCapabilities {
  seek: boolean;
  volume: boolean;
  playbackRate: boolean;
  fullscreen: boolean;
  pictureInPicture: boolean;
  remotePlayback: boolean;
  audioTracks: boolean;
  subtitleTracks: boolean;
  seekPreview: boolean;
  screenshot: boolean;
  anime4k: boolean;
}

export interface PlayerAdapterState {
  phase: AdapterPhase;
  position: number;
  duration: number;
  buffered: number;
  paused: boolean;
  muted: boolean;
  volume: number;
  playbackRate: number;
  fullscreen: boolean;
  pictureInPicture: boolean;
  audioTracks: PlayerTrack[];
  subtitleTracks: PlayerTrack[];
  selectedAudioId: string | number | null;
  selectedSubtitleId: string | number | 'off' | null;
  hasVideo: boolean | null;
  videoWidth: number;
  videoHeight: number;
  blackFrameDetected: boolean;
  droppedFrames: number;
  error: string | null;
}

export type PlayerAdapterStateInput = Partial<PlayerAdapterState> & Pick<PlayerAdapterState, 'phase'>;

function finite(value: number | undefined, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

export function normalizeAdapterState(input: PlayerAdapterStateInput): PlayerAdapterState {
  const duration = Math.max(0, finite(input.duration, 0));
  const position = Math.max(0, Math.min(duration || Number.POSITIVE_INFINITY, finite(input.position, 0)));
  return {
    phase: input.phase,
    position,
    duration,
    buffered: Math.max(0, Math.min(duration || Number.POSITIVE_INFINITY, finite(input.buffered, 0))),
    paused: input.paused ?? input.phase !== 'playing',
    muted: input.muted ?? false,
    volume: Math.max(0, Math.min(1, finite(input.volume, 1))),
    playbackRate: finite(input.playbackRate, 1) > 0 ? finite(input.playbackRate, 1) : 1,
    fullscreen: input.fullscreen ?? false,
    pictureInPicture: input.pictureInPicture ?? false,
    audioTracks: input.audioTracks ?? [],
    subtitleTracks: input.subtitleTracks ?? [],
    selectedAudioId: input.selectedAudioId ?? null,
    selectedSubtitleId: input.selectedSubtitleId ?? 'off',
    hasVideo: input.hasVideo ?? null,
    videoWidth: Math.max(0, finite(input.videoWidth, 0)),
    videoHeight: Math.max(0, finite(input.videoHeight, 0)),
    blackFrameDetected: input.blackFrameDetected ?? false,
    droppedFrames: Math.max(0, finite(input.droppedFrames, 0)),
    error: input.error ?? null,
  };
}

export interface PlayerAdapterLoadRequest {
  attempt: PlaybackAttempt;
  position: number;
  tracks: PlayerTrackSelection;
  subtitles: SubtitleItem[];
  signal: AbortSignal;
}

export interface PlayerSeekPreview {
  position: number;
  imageUrl: string;
}

export interface PlayerAdapter {
  readonly kind: PlayerAdapterKind;
  readonly capabilities: PlayerAdapterCapabilities;
  load(request: PlayerAdapterLoadRequest): Promise<void>;
  play(): void | Promise<void>;
  pause(): void | Promise<void>;
  seek(position: number): void | Promise<void>;
  setVolume(volume: number): void | Promise<void>;
  setMuted(muted: boolean): void | Promise<void>;
  setPlaybackRate(rate: number): void | Promise<void>;
  setFullscreen(fullscreen: boolean): void | Promise<void>;
  setPictureInPicture(enabled: boolean): void | Promise<void>;
  requestRemotePlayback?(): void | Promise<void>;
  selectAudioTrack(id: string | number): void | Promise<void>;
  selectSubtitleTrack(id: string | number | 'off'): void | Promise<void>;
  updateSubtitles?(subtitles: SubtitleItem[], tracks: PlayerTrackSelection): void | Promise<void>;
  probeAudioTracks?(): void | Promise<void>;
  requestSeekPreview?(position: number): PlayerSeekPreview | null | Promise<PlayerSeekPreview | null>;
  subscribe(listener: (state: PlayerAdapterState) => void): () => void;
  destroy(): void | Promise<void>;
}
