// Mirrors iOS LastPlaybackSourceStore — persists the last-chosen stream URL per media item.
// localStorage key: moonlit.lastPlaybackSource.<mediaId>

export interface LastStream {
  url: string;
  addonName?: string;
  streamTitle?: string;
  savedAt: number;
}

const PREFIX = 'moonlit.lastPlaybackSource.';
const MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

export function saveLastStream(mediaId: string, stream: { url: string; addonName?: string; streamTitle?: string }) {
  try {
    const entry: LastStream = { ...stream, savedAt: Date.now() };
    localStorage.setItem(PREFIX + mediaId, JSON.stringify(entry));
  } catch {}
}

export function getLastStream(mediaId: string): LastStream | null {
  try {
    const raw = localStorage.getItem(PREFIX + mediaId);
    if (!raw) return null;
    const entry: LastStream = JSON.parse(raw);
    if (Date.now() - entry.savedAt > MAX_AGE_MS) {
      localStorage.removeItem(PREFIX + mediaId);
      return null;
    }
    return entry;
  } catch { return null; }
}
