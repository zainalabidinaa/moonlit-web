/// Typed bridge for the desktop libmpv player (Windows-only).
/// Pure functions tested in vitest; thin adapters exercised at runtime.
import { isDesktop } from './index';

// ── Types ────────────────────────────────────────────────────────────────────
export interface MpvEvent {
  event: string;
  name?: string;
  data?: unknown;
  reason?: string;
  message?: string;
  level?: string;
  text?: string;
  prefix?: string;
}

export interface MpvTrack {
  id: number;
  lang?: string;
  label: string;
  selected: boolean;
  external?: boolean;
  sourceUrl?: string;
}

export interface MpvState {
  position: number;
  duration: number;
  paused: boolean;
  muted: boolean;
  volume: number;
  speed: number;
  buffering: boolean;
  cacheTime: number;
  loaded: boolean;
  ended: boolean;
  error: string | null;
  subDelay: number;
  audioDelay: number;
  aspect: number | null;
  hasVideoTrack: boolean | null;
  tracks: { audio: MpvTrack[]; subs: MpvTrack[] };
}

export function initialMpvState(): MpvState {
  return {
    position: 0, duration: 0, paused: false, muted: false, volume: 100, speed: 1,
    buffering: false, cacheTime: 0, loaded: false, ended: false, error: null,
    subDelay: 0, audioDelay: 0, aspect: null, hasVideoTrack: null, tracks: { audio: [], subs: [] },
  };
}

// ── Pure reducers ────────────────────────────────────────────────────────────
type RawTrack = Record<string, unknown>;

export function parseTrackList(raw: unknown): MpvState['tracks'] {
  if (!Array.isArray(raw)) return { audio: [], subs: [] };
  const toTrack = (t: RawTrack): MpvTrack => {
    const lang = typeof t.lang === 'string' ? t.lang : undefined;
    const title = typeof t.title === 'string' ? t.title : undefined;
    const codec = typeof t.codec === 'string' ? t.codec : undefined;
    const sourceUrl = typeof t['external-filename'] === 'string' ? t['external-filename'] : undefined;
    const parts = [title ?? lang ?? `Track ${t.id}`, codec?.toUpperCase()].filter(Boolean);
    return {
      id: Number(t.id),
      lang,
      label: parts.join(' \u00b7 '),
      selected: t.selected === true,
      external: t.external === true,
      sourceUrl,
    };
  };
  const items = raw as RawTrack[];
  return {
    audio: items.filter((t) => t.type === 'audio').map(toTrack),
    subs: items.filter((t) => t.type === 'sub').map(toTrack),
  };
}

export function reduceMpvEvent(state: MpvState, ev: MpvEvent): MpvState {
  switch (ev.event) {
    case 'property-change': {
      const d = ev.data;
      switch (ev.name) {
        case 'time-pos': return typeof d === 'number' ? { ...state, position: d } : state;
        case 'duration': return typeof d === 'number' ? { ...state, duration: d } : state;
        case 'pause': return { ...state, paused: d === true };
        case 'mute': return { ...state, muted: d === true };
        case 'volume': return typeof d === 'number' ? { ...state, volume: d } : state;
        case 'speed': return typeof d === 'number' ? { ...state, speed: d } : state;
        case 'sub-delay': return typeof d === 'number' ? { ...state, subDelay: d } : state;
        case 'audio-delay': return typeof d === 'number' ? { ...state, audioDelay: d } : state;
        case 'demuxer-cache-time': return typeof d === 'number' ? { ...state, cacheTime: d } : state;
        case 'paused-for-cache': return { ...state, buffering: d === true };
        case 'video-params/aspect': return typeof d === 'number' ? { ...state, aspect: d } : state;
        case 'eof-reached': return d === true ? { ...state, ended: true } : state;
        case 'track-list': return {
          ...state,
          tracks: parseTrackList(d),
          hasVideoTrack: Array.isArray(d) ? d.some(track => track && typeof track === 'object' && (track as RawTrack).type === 'video') : null,
        };
        default: return state;
      }
    }
    case 'file-loaded': return { ...state, loaded: true, ended: false, error: null };
    case 'end-file':
      if (ev.reason && /error/i.test(ev.reason)) return { ...state, error: 'Playback failed' };
      return { ...state, ended: true };
    case 'error': return { ...state, error: ev.message ?? 'Playback failed' };
    default: return state;
  }
}

// ── Command bridge ───────────────────────────────────────────────────────────
async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

export const mpv = {
  probe: () => invoke<{ available: boolean; reason: string | null }>('mpv_probe'),
  start: (payload: { url: string; startAtSec?: number; headers?: Record<string, string> }) =>
    invoke<void>('mpv_start', { payload }),
  stop: () => invoke<void>('mpv_stop'),
  setProp: (name: string, value: unknown) => invoke<void>('mpv_set_property', { name, value }),
  getProp: <T = unknown>(name: string) => invoke<T>('mpv_get_property', { name }),
  command: (parts: string[]) => invoke<void>('mpv_command', { parts }),
  subAdd: (url: string, opts?: { title?: string; lang?: string; select?: boolean }) =>
    invoke<void>('mpv_sub_add', { url, ...opts }),
  screenshot: (path: string) => invoke<string>('mpv_screenshot', { path }),
  setGeometry: (css: {
    cssLeft: number; cssTop: number; cssWidth: number; cssHeight: number;
    cssViewW: number; cssViewH: number;
  }) => invoke<void>('mpv_set_geometry', { css }),
  shaderDir: () => invoke<string>('shader_dir'),
};

export async function onMpvEvent(handler: (ev: MpvEvent) => void): Promise<() => void> {
  if (!isDesktop()) return () => {};
  const { listen } = await import('@tauri-apps/api/event');
  return listen<MpvEvent>('mpv://event', (e) => handler(e.payload));
}

let probeCache: Promise<boolean> | null = null;

export function mpvAvailable(): Promise<boolean> {
  if (!isDesktop()) return Promise.resolve(false);
  probeCache ??= mpv.probe().then((p) => p.available).catch(() => false);
  return probeCache;
}
