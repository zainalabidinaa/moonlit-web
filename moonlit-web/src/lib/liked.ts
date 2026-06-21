import { TMDB_API_KEY } from './supabase';

export interface LikedItem {
  id: string;
  mediaId: string;
  mediaType: string;
  name: string;
  poster?: string;
  tmdbId?: number;
  likedAt: string;
}

export interface UpcomingInfo {
  badge: string;
  releaseDate?: string;
}

const STORAGE_KEY = 'moonlit.liked.items';

export function getLikedItems(): LikedItem[] {
  try {
    const data = localStorage.getItem(STORAGE_KEY);
    return data ? JSON.parse(data) : [];
  } catch { return []; }
}

export function addLiked(item: Omit<LikedItem, 'id' | 'likedAt'>): void {
  const items = getLikedItems().filter(i => i.mediaId !== item.mediaId);
  items.unshift({ ...item, id: item.mediaId, likedAt: new Date().toISOString() });
  localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  window.dispatchEvent(new Event('moonlit-liked-changed'));
}

export function removeLiked(mediaId: string): void {
  const items = getLikedItems().filter(i => i.mediaId !== mediaId);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  window.dispatchEvent(new Event('moonlit-liked-changed'));
}

export function isLiked(mediaId: string): boolean {
  return getLikedItems().some(i => i.mediaId === mediaId);
}

// ── Upcoming (TMDB-based, matches iOS UpcomingItemsService) ───────────────

const CACHE_KEY = 'moonlit.upcoming.cache';
const CACHE_TTL_MS = 4 * 60 * 60 * 1000; // 4 hours

interface CacheEntry { data: Record<string, UpcomingInfo>; ts: number }

function getCached(): Record<string, UpcomingInfo> {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return {};
    const entry: CacheEntry = JSON.parse(raw);
    if (Date.now() - entry.ts > CACHE_TTL_MS) return {};
    return entry.data;
  } catch { return {}; }
}

function setCached(data: Record<string, UpcomingInfo>): void {
  try { localStorage.setItem(CACHE_KEY, JSON.stringify({ data, ts: Date.now() })); } catch {}
}

async function resolveTmdbId(imdbId: string, mediaType: string): Promise<number | null> {
  const root = imdbId.split(':')[0];
  if (!root.startsWith('tt')) return null;
  try {
    const res = await fetch(
      `https://api.themoviedb.org/3/find/${root}?api_key=${TMDB_API_KEY}&external_source=imdb_id`
    );
    if (!res.ok) return null;
    const data = await res.json();
    return mediaType === 'movie'
      ? (data.movie_results?.[0]?.id ?? null)
      : (data.tv_results?.[0]?.id ?? null);
  } catch { return null; }
}

function formatDate(str: string): string {
  try {
    return new Date(str).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  } catch { return str; }
}

async function fetchUpcoming(item: LikedItem): Promise<UpcomingInfo | null> {
  const tmdbId = item.tmdbId ?? await resolveTmdbId(item.mediaId, item.mediaType);
  if (!tmdbId) return null;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  try {
    if (item.mediaType === 'movie') {
      const res = await fetch(`https://api.themoviedb.org/3/movie/${tmdbId}?api_key=${TMDB_API_KEY}`);
      if (!res.ok) return null;
      const data = await res.json();
      if (!data.release_date) return null;
      const release = new Date(data.release_date);
      if (release <= today) return null;
      return { badge: formatDate(data.release_date), releaseDate: data.release_date };
    } else {
      const res = await fetch(`https://api.themoviedb.org/3/tv/${tmdbId}?api_key=${TMDB_API_KEY}`);
      if (!res.ok) return null;
      const data = await res.json();
      if (data.status === 'Ended' || data.status === 'Canceled') return null;
      const next = data.next_episode_to_air;
      if (!next) return null;
      const season = next.season_number;
      const badge = next.air_date
        ? `Season ${season} · ${formatDate(next.air_date)}`
        : `Season ${season} · No air date`;
      return { badge, releaseDate: next.air_date };
    }
  } catch { return null; }
}

export async function refreshUpcoming(items: LikedItem[]): Promise<Record<string, UpcomingInfo>> {
  const cached = getCached();
  if (Object.keys(cached).length > 0 && items.every(i => i.mediaId in cached)) return cached;

  const results = await Promise.allSettled(items.map(async item => {
    const info = await fetchUpcoming(item);
    return { mediaId: item.mediaId, info };
  }));

  const map: Record<string, UpcomingInfo> = {};
  for (const r of results) {
    if (r.status === 'fulfilled' && r.value.info) {
      map[r.value.mediaId] = r.value.info;
    }
  }
  setCached(map);
  return map;
}
