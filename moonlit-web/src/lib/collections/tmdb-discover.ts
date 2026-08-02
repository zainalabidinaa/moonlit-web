import type { MetaPreview } from '@/lib/types';
import type { LoadedBrowseRail } from './genre-catalog';
import { normalize } from './genre-catalog';
import { tmdbGenreId } from './tmdb-genre-ids';

/**
 * Builds curated TMDB-discover-backed rails for genre/language hubs (Trending,
 * Top Rated, New, Hidden Gems, hand-authored "creative" theme rails) and
 * resolves each result's TMDB id to an IMDb id, since the rest of the app is
 * keyed by IMDb id.
 *
 * Ported from Packages/MoonlitCore/Sources/MoonlitCore/Services/TMDBDiscoverService.swift
 * (discoverRails / discoverGeneral / discoverCreativeRails + IMDb resolution only —
 * discoverSimilar/discoverUpcoming/discoverByYear/discoverByProvider/trailers belong
 * to other screens and aren't needed here). Keep the two in sync when either changes.
 */

const BASE = 'https://api.themoviedb.org/3';
const RESOLVE_CONCURRENCY = 6;
const IMDB_CACHE_KEY = 'moonlit.tmdbImdbMap';

type MediaKind = 'movie' | 'series';

interface TMDBDiscoverItem {
  id: number;
  title?: string;
  name?: string;
  poster_path?: string | null;
  release_date?: string;
  first_air_date?: string;
  popularity?: number;
  vote_average?: number;
  vote_count?: number;
}

function kindPath(kind: MediaKind): 'movie' | 'tv' {
  return kind === 'movie' ? 'movie' : 'tv';
}

function loadImdbCache(): Record<string, string> {
  try {
    return JSON.parse(localStorage.getItem(IMDB_CACHE_KEY) ?? '{}');
  } catch {
    return {};
  }
}

function saveImdbCache(cache: Record<string, string>): void {
  try { localStorage.setItem(IMDB_CACHE_KEY, JSON.stringify(cache)); } catch { /* best-effort */ }
}

/**
 * The value to persist in the tmdbId->imdbId cache, or null for "don't cache".
 * Only a 200 counts as a confirmed answer — TMDB error bodies (429 rate limit,
 * 401) would otherwise be cached forever as a miss, permanently hiding a title.
 */
function imdbCacheEntry(status: number, imdbId: string | null): string | null {
  if (status !== 200) return null;
  return imdbId ?? '';
}

async function resolveImdbId(
  tmdbId: number,
  kind: MediaKind,
  apiKey: string,
  cache: Record<string, string>,
): Promise<string | null> {
  const cacheKey = `${kind}:${tmdbId}`;
  if (cacheKey in cache) return cache[cacheKey] || null;
  try {
    const res = await fetch(`${BASE}/${kindPath(kind)}/${tmdbId}/external_ids?api_key=${apiKey}`);
    const data = await res.json().catch(() => ({}));
    const entry = imdbCacheEntry(res.status, data.imdb_id ?? null);
    if (entry === null) return null;
    cache[cacheKey] = entry;
    return data.imdb_id ?? null;
  } catch {
    return null;
  }
}

function asMetaPreview(item: TMDBDiscoverItem, imdbId: string, kind: MediaKind): MetaPreview {
  const tmdbPoster = item.poster_path ? `https://image.tmdb.org/t/p/w500${item.poster_path}` : undefined;
  const date = item.release_date ?? item.first_air_date;
  return {
    id: imdbId,
    type: kind,
    name: item.title ?? item.name ?? 'Unknown',
    poster: tmdbPoster,
    releaseInfo: date ? date.split('-')[0] : undefined,
    popularity: item.popularity,
    imdbRating: typeof item.vote_average === 'number' ? item.vote_average.toFixed(1) : undefined,
  };
}

/** Resolves TMDB ids to IMDb ids with bounded concurrency, preserving TMDB's original order. */
async function resolveItems(
  items: TMDBDiscoverItem[],
  kind: MediaKind,
  apiKey: string,
): Promise<MetaPreview[]> {
  const cache = loadImdbCache();
  const results: (MetaPreview | undefined)[] = new Array(items.length);
  for (let index = 0; index < items.length; index += RESOLVE_CONCURRENCY) {
    const chunk = items.slice(index, index + RESOLVE_CONCURRENCY);
    await Promise.all(chunk.map(async (item, offset) => {
      const imdbId = await resolveImdbId(item.id, kind, apiKey, cache);
      if (imdbId) results[index + offset] = asMetaPreview(item, imdbId, kind);
    }));
  }
  saveImdbCache(cache);
  return results.filter((item): item is MetaPreview => item !== undefined);
}

async function fetchItems(
  kind: MediaKind,
  apiKey: string,
  params: Record<string, string>,
): Promise<MetaPreview[]> {
  const query = new URLSearchParams({ api_key: apiKey, ...params });
  try {
    const res = await fetch(`${BASE}/discover/${kindPath(kind)}?${query.toString()}`);
    if (!res.ok) return [];
    const data = await res.json();
    const items: TMDBDiscoverItem[] = (data.results ?? []).slice(0, 20);
    return resolveItems(items, kind, apiKey);
  } catch {
    return [];
  }
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Trending / Top Rated / New / Hidden Gems for a single genre — the core rails
 * a genre hub screen shows for its selected media kind.
 */
export async function discoverGenreRails(
  genreName: string,
  mediaKind: MediaKind,
  apiKey: string,
): Promise<LoadedBrowseRail[]> {
  const genreId = tmdbGenreId(genreName, mediaKind);
  if (!apiKey || genreId === null) return [];
  const [trending, topRated, recent, hiddenGems] = await Promise.all([
    fetchItems(mediaKind, apiKey, { with_genres: String(genreId), sort_by: 'popularity.desc', 'vote_count.gte': '50' }),
    fetchItems(mediaKind, apiKey, { with_genres: String(genreId), sort_by: 'vote_average.desc', 'vote_count.gte': '400' }),
    fetchItems(mediaKind, apiKey, {
      with_genres: String(genreId), sort_by: 'primary_release_date.desc',
      'vote_count.gte': '10', 'primary_release_date.lte': today(),
    }),
    fetchItems(mediaKind, apiKey, {
      with_genres: String(genreId), sort_by: 'vote_average.desc',
      'vote_count.gte': '50', 'vote_count.lte': '300',
    }),
  ]);

  const rails: LoadedBrowseRail[] = [];
  if (trending.length) rails.push({ id: 'tmdb-trending', title: `Trending ${genreName}`, items: trending });
  if (topRated.length) rails.push({ id: 'tmdb-top-rated', title: `Top Rated ${genreName}`, items: topRated });
  if (recent.length) rails.push({ id: 'tmdb-recent', title: `New ${genreName}`, items: recent });
  if (hiddenGems.length) rails.push({ id: 'tmdb-hidden-gems', title: 'Hidden Gems', items: hiddenGems });
  return rails;
}

/** Default "All" browse rails for a media kind (no genre selected). */
export async function discoverGeneralRails(mediaKind: MediaKind, apiKey: string): Promise<LoadedBrowseRail[]> {
  if (!apiKey) return [];
  const dateField = mediaKind === 'movie' ? 'primary_release_date' : 'first_air_date';
  const noun = mediaKind === 'movie' ? 'Movies' : 'Series';

  const [popular, topRated, recent, hiddenGems, trending] = await Promise.all([
    fetchItems(mediaKind, apiKey, { sort_by: 'popularity.desc', 'vote_count.gte': '80' }),
    fetchItems(mediaKind, apiKey, { sort_by: 'vote_average.desc', 'vote_count.gte': '800' }),
    fetchItems(mediaKind, apiKey, { sort_by: `${dateField}.desc`, 'vote_count.gte': '15', [`${dateField}.lte`]: today() }),
    fetchItems(mediaKind, apiKey, { sort_by: 'vote_average.desc', 'vote_count.gte': '20', 'vote_count.lte': '150' }),
    fetchItems(mediaKind, apiKey, { sort_by: 'popularity.desc', 'vote_count.gte': '100' }),
  ]);

  const rails: LoadedBrowseRail[] = [];
  if (trending.length) rails.push({ id: 'gen-trending', title: `Trending ${noun}`, items: trending });
  if (popular.length) rails.push({ id: 'gen-popular', title: `Popular ${noun}`, items: popular });
  if (topRated.length) rails.push({ id: 'gen-top', title: `Top Rated ${noun}`, items: topRated });
  if (hiddenGems.length) rails.push({ id: 'gen-hidden-gems', title: 'Hidden Gems', items: hiddenGems });
  if (recent.length) rails.push({ id: 'gen-new', title: 'New Releases', items: recent });
  return rails;
}

interface CreativeRailSpec { id: string; title: string; params: Record<string, string> }

/** Hand-authored, keyword-driven "creative" rails per genre (Martial Arts for Action, Zombies for Horror, etc). */
function creativeRailSpecs(genre: string): CreativeRailSpec[] {
  switch (normalize(genre)) {
    case 'action': return [
      { id: 'martial-arts', title: 'Martial Arts & Mayhem', params: { with_keywords: '779', 'vote_count.gte': '40' } },
      { id: 'blockbuster', title: 'Blockbuster Action', params: { with_genres: '28', 'vote_count.gte': '300', sort_by: 'revenue.desc' } },
      { id: 'action-thriller', title: 'Action Thrillers', params: { with_genres: '28,53', 'vote_count.gte': '100' } },
    ];
    case 'adventure': return [
      { id: 'treasure', title: 'Treasure Hunts', params: { with_keywords: '9882', 'vote_count.gte': '30' } },
      { id: 'survival', title: 'Survival Against Nature', params: { with_keywords: '9717', 'vote_count.gte': '40' } },
      { id: 'historical', title: 'Historical Adventures', params: { with_genres: '12,36', 'vote_count.gte': '60' } },
    ];
    case 'animation': return [
      { id: 'anime', title: 'Anime', params: { with_keywords: '210024', 'vote_count.gte': '40' } },
      { id: 'pixar-dw', title: 'Pixar & DreamWorks Gems', params: { with_genres: '16,10751', 'vote_average.gte': '7.2', 'vote_count.gte': '200', sort_by: 'vote_average.desc' } },
      { id: 'adult-animation', title: 'Adult Animation', params: { with_genres: '16', 'vote_count.gte': '80', sort_by: 'vote_average.desc', without_genres: '10751', 'with_runtime.gte': '60' } },
    ];
    case 'comedy': return [
      { id: 'standup', title: 'Stand-Up & Specials', params: { with_keywords: '9716' } },
      { id: 'action-comedy', title: 'Action Comedies', params: { with_genres: '28,35', 'vote_count.gte': '100' } },
      { id: 'satire', title: 'Satire & Dark Humor', params: { with_genres: '35', 'vote_count.gte': '80', sort_by: 'vote_average.desc' } },
    ];
    case 'crime': return [
      { id: 'heists', title: 'Heists & Capers', params: { with_keywords: '10051', 'vote_count.gte': '40' } },
      { id: 'noir', title: 'Film Noir & Neo-Noir', params: { with_keywords: '10223', 'vote_count.gte': '30' } },
      { id: 'crime-thriller', title: 'Crime Thrillers', params: { with_genres: '80,53', 'vote_count.gte': '80', sort_by: 'vote_average.desc' } },
    ];
    case 'documentary': return [
      { id: 'true-crime-doc', title: 'True Crime Docs', params: { with_keywords: '12995', 'vote_count.gte': '20' } },
      { id: 'nature-doc', title: 'Nature & Wildlife', params: { with_keywords: '1907', 'vote_count.gte': '20' } },
      { id: 'music-doc', title: 'Music & Concert Films', params: { with_keywords: '1638', 'vote_count.gte': '20' } },
    ];
    case 'drama': return [
      { id: 'true-story', title: 'Based on a True Story', params: { with_keywords: '9672', 'vote_count.gte': '100' } },
      { id: 'coming-of-age', title: 'Coming of Age', params: { with_keywords: '1909', 'vote_count.gte': '60' } },
      { id: 'biopic', title: 'Biographical Dramas', params: { with_keywords: '1701', 'vote_count.gte': '50', sort_by: 'vote_average.desc' } },
    ];
    case 'family': return [
      { id: 'feelgood', title: 'Feel-Good Family', params: { with_genres: '10751', 'vote_count.gte': '50' } },
      { id: 'family-animation', title: 'Animated Family', params: { with_genres: '16,10751', 'vote_average.gte': '7', 'vote_count.gte': '150', sort_by: 'vote_average.desc' } },
    ];
    case 'fantasy': return [
      { id: 'superheroes', title: 'Superhero Sagas', params: { with_keywords: '9715', 'vote_count.gte': '60' } },
      { id: 'fairy-tales', title: 'Fairy Tales Retold', params: { with_keywords: '3205', 'vote_count.gte': '30' } },
      { id: 'fantasy-adventure', title: 'Fantasy Adventures', params: { with_genres: '14,12', 'vote_count.gte': '100', sort_by: 'vote_average.desc' } },
    ];
    case 'history': return [
      { id: 'biopics', title: 'Biographical Epics', params: { with_keywords: '1701', 'vote_count.gte': '50', sort_by: 'vote_average.desc' } },
      { id: 'wwii', title: 'WWII Stories', params: { with_keywords: '1964', 'vote_count.gte': '60' } },
      { id: 'ancient', title: 'Ancient Worlds', params: { with_genres: '36', 'vote_count.gte': '50', sort_by: 'vote_average.desc' } },
    ];
    case 'horror': return [
      { id: 'zombies', title: 'Zombies & the Undead', params: { with_keywords: '12377', 'vote_count.gte': '30' } },
      { id: 'slasher', title: 'Slashers', params: { with_keywords: '12338', 'vote_count.gte': '30' } },
      { id: 'haunted', title: 'Haunted Houses', params: { with_keywords: '14796', 'vote_count.gte': '20' } },
      { id: 'found-footage', title: 'Found Footage', params: { with_keywords: '10170', 'vote_count.gte': '20' } },
    ];
    case 'music': return [
      { id: 'music-doc', title: 'Music Documentaries', params: { with_keywords: '1638', 'vote_count.gte': '20' } },
      { id: 'music-drama', title: 'Music Dramas', params: { with_genres: '18', with_keywords: '1638', 'vote_count.gte': '40', sort_by: 'vote_average.desc' } },
    ];
    case 'mystery': return [
      { id: 'detective', title: 'Detectives & Sleuths', params: { with_keywords: '4275', 'vote_count.gte': '40' } },
      { id: 'conspiracy', title: 'Conspiracy Theories', params: { with_keywords: '13015', 'vote_count.gte': '30' } },
      { id: 'mystery-thriller', title: 'Mindfucks & Twists', params: { with_genres: '9648,53', 'vote_count.gte': '80', sort_by: 'vote_average.desc' } },
    ];
    case 'romance': return [
      { id: 'romcoms', title: 'Rom-Coms', params: { with_genres: '10749,35', 'vote_count.gte': '60' } },
      { id: 'drama-romance', title: 'Romantic Dramas', params: { with_genres: '10749,18', 'vote_count.gte': '80', sort_by: 'vote_average.desc' } },
      { id: 'forbidden-love', title: 'Forbidden Love', params: { with_keywords: '9888', 'vote_count.gte': '30' } },
    ];
    case 'sci-fi': return [
      { id: 'time-travel', title: 'Time-Travel & Beyond', params: { with_keywords: '4379', 'vote_count.gte': '40' } },
      { id: 'aliens', title: 'Alien Encounters', params: { with_keywords: '9951', 'vote_count.gte': '40' } },
      { id: 'cyberpunk', title: 'Cyberpunk', params: { with_keywords: '4563', 'vote_count.gte': '30' } },
      { id: 'space-opera', title: 'Space Operas', params: { with_keywords: '10014', 'vote_count.gte': '50' } },
      { id: 'ai', title: 'Artificial Intelligence', params: { with_keywords: '4565', 'vote_count.gte': '40' } },
    ];
    case 'thriller': return [
      { id: 'dystopia', title: 'Dystopian Futures', params: { with_keywords: '4458', 'vote_count.gte': '40' } },
      { id: 'kidnapping', title: 'Kidnapped', params: { with_keywords: '1879', 'vote_count.gte': '30' } },
      { id: 'serial-killer', title: 'Serial Killers', params: { with_keywords: '197951', 'vote_count.gte': '30' } },
      { id: 'psycho', title: 'Psychological Thrills', params: { with_genres: '53', 'vote_count.gte': '100', sort_by: 'vote_average.desc' } },
    ];
    case 'war': return [
      { id: 'wwii', title: 'WWII Stories', params: { with_keywords: '1964', 'vote_count.gte': '50' } },
      { id: 'vietnam', title: 'Vietnam War', params: { with_keywords: '2315', 'vote_count.gte': '30' } },
      { id: 'war-classics', title: 'War Classics', params: { with_genres: '10752', 'vote_count.gte': '100', sort_by: 'vote_average.desc' } },
    ];
    case 'western': return [
      { id: 'gunslingers', title: 'Gunslingers', params: { with_genres: '37', 'vote_count.gte': '40' } },
      { id: 'western-classics', title: 'Western Classics', params: { with_genres: '37', 'vote_count.gte': '60', sort_by: 'vote_average.desc' } },
    ];
    default: return [];
  }
}

export async function discoverCreativeRails(
  genreName: string,
  mediaKind: MediaKind,
  apiKey: string,
): Promise<LoadedBrowseRail[]> {
  const specs = creativeRailSpecs(genreName);
  if (!apiKey || specs.length === 0) return [];

  const rails = await Promise.all(specs.map(async spec => {
    const params = spec.params.sort_by ? spec.params : { ...spec.params, sort_by: 'popularity.desc' };
    const items = await fetchItems(mediaKind, apiKey, params);
    return items.length ? { id: `creative-${spec.id}`, title: spec.title, items } : null;
  }));
  return rails.filter((rail): rail is LoadedBrowseRail => rail !== null);
}
