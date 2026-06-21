import { MetaPreview, StremioCatalogQuery } from './types';

const CACHE_TTL_MS = 30 * 60 * 1000;
const CACHE_PREFIX = 'moonlit.catalog.';

interface CacheEntry {
  items: MetaPreview[];
  ts: number;
}

const memCache = new Map<string, CacheEntry>();

function cacheKey(query: StremioCatalogQuery): string {
  const extras = query.extras
    ? Object.entries(query.extras).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}:${v}`).join(',')
    : '';
  return `${query.baseURL}|${query.type}|${query.id}|${extras}`;
}

function getFromCache(query: StremioCatalogQuery): MetaPreview[] | null {
  const key = cacheKey(query);
  const mem = memCache.get(key);
  if (mem && Date.now() - mem.ts < CACHE_TTL_MS) return mem.items;

  try {
    const lsKey = CACHE_PREFIX + key;
    const raw = localStorage.getItem(lsKey);
    if (!raw) return null;
    const entry: CacheEntry = JSON.parse(raw);
    if (Date.now() - entry.ts > CACHE_TTL_MS) {
      localStorage.removeItem(lsKey);
      return null;
    }
    memCache.set(key, entry);
    return entry.items;
  } catch {
    return null;
  }
}

function setCache(query: StremioCatalogQuery, items: MetaPreview[]) {
  const key = cacheKey(query);
  const entry: CacheEntry = { items, ts: Date.now() };
  memCache.set(key, entry);
  try {
    localStorage.setItem(CACHE_PREFIX + key, JSON.stringify(entry));
  } catch {}
}

function buildCatalogUrl(query: StremioCatalogQuery): string {
  const extrasStr = query.extras
    ? Object.entries(query.extras).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')
    : '';
  const path = `${query.baseURL}/catalog/${query.type}/${query.id}.json`;
  return extrasStr ? `${path}?${extrasStr}` : path;
}

export async function fetchCatalog(query: StremioCatalogQuery): Promise<MetaPreview[]> {
  const cached = getFromCache(query);
  if (cached) return cached;

  const url = buildCatalogUrl(query);
  try {
    const res = await fetch(`/api/stremio/catalog?url=${encodeURIComponent(url)}`);
    if (!res.ok) return [];
    const data = await res.json();
    const items: MetaPreview[] = (data.metas || []).map((m: any) => ({
      id: String(m.id || ''),
      type: m.type || query.type,
      name: m.name || 'Unknown',
      poster: m.poster || undefined,
      description: m.description || undefined,
      releaseInfo: m.releaseInfo || m.year ? String(m.releaseInfo || m.year) : undefined,
      imdbId: m.imdb_id || undefined,
      imdbRating: m.imdbRating || undefined,
      genres: m.genres || undefined,
    }));
    setCache(query, items);
    return items;
  } catch {
    return [];
  }
}

// TMDB collection direct API (not through addons)
export async function fetchTMDBCollection(tmdbId: string, apiKey: string): Promise<MetaPreview[]> {
  const cached = memCache.get(`tmdb-collection-${tmdbId}`);
  if (cached && Date.now() - cached.ts < CACHE_TTL_MS) return cached.items;

  try {
    const res = await fetch(`https://api.themoviedb.org/3/collection/${tmdbId}?api_key=${apiKey}`);
    if (!res.ok) return [];
    const data = await res.json();

    const items: MetaPreview[] = [];
    for (const part of data.parts || []) {
      // Fetch external IDs to get IMDb ID
      let imdbId: string | undefined;
      try {
        const extRes = await fetch(`https://api.themoviedb.org/3/movie/${part.id}/external_ids?api_key=${apiKey}`);
        if (extRes.ok) {
          const ext = await extRes.json();
          if (ext.imdb_id) imdbId = ext.imdb_id;
        }
      } catch {}

      items.push({
        id: imdbId || String(part.id),
        type: 'movie',
        name: part.title || part.original_title || 'Unknown',
        poster: part.poster_path ? `https://image.tmdb.org/t/p/w342${part.poster_path}` : undefined,
        releaseInfo: part.release_date?.slice(0, 4),
        imdbId,
      });
    }

    const entry: CacheEntry = { items, ts: Date.now() };
    memCache.set(`tmdb-collection-${tmdbId}`, entry);
    return items;
  } catch {
    return [];
  }
}
