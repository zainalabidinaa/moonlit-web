import { StreamItem } from './types';
import { streamMatchesUrl } from './player-utils';

// ── In-memory + localStorage stream cache, matches iOS StreamWarmupRepository ──
// TTL: 60 min (same as iOS). localStorage key: moonlit.streams.<type:id>

const CACHE_TTL_MS = 60 * 60 * 1000;
const LS_PREFIX = 'moonlit.streams.';

interface CacheEntry { streams: StreamItem[]; ts: number }

const memCache = new Map<string, CacheEntry>();

function lsKey(key: string) { return LS_PREFIX + key; }

export function cacheStreams(key: string, streams: StreamItem[]) {
  const entry: CacheEntry = { streams, ts: Date.now() };
  memCache.set(key, entry);
  try { localStorage.setItem(lsKey(key), JSON.stringify(entry)); } catch {}
}

export function getCachedStreams(key: string): StreamItem[] | null {
  const mem = memCache.get(key);
  if (mem && Date.now() - mem.ts < CACHE_TTL_MS) return mem.streams;

  try {
    const raw = localStorage.getItem(lsKey(key));
    if (!raw) return null;
    const entry: CacheEntry = JSON.parse(raw);
    if (Date.now() - entry.ts > CACHE_TTL_MS) {
      localStorage.removeItem(lsKey(key));
      return null;
    }
    memCache.set(key, entry);
    return entry.streams;
  } catch { return null; }
}

export function getCachedStream(key: string, streamUrl: string): StreamItem | null {
  const streams = getCachedStreams(key);
  if (!streams) return null;
  return streams.find(s => streamMatchesUrl(s, streamUrl)) ?? null;
}

export function clearCache() {
  memCache.clear();
  try {
    Object.keys(localStorage)
      .filter(k => k.startsWith(LS_PREFIX))
      .forEach(k => localStorage.removeItem(k));
  } catch {}
}
