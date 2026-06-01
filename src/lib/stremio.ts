import { AddonManifest, MetaPreview, MetaDetail, StreamItem } from './types';

export async function fetchManifest(url: string): Promise<AddonManifest> {
  const res = await fetch(url);
  const json = await res.json();

  const baseURL = json.transportUrl || url.replace(/\/manifest\.json$/, '');

  return {
    id: json.id || new URL(url).hostname,
    name: json.name || 'Unknown',
    version: json.version || '0.0.0',
    description: json.description,
    types: json.types,
    resources: json.resources,
    catalogs: json.catalogs,
    transportUrl: baseURL.endsWith('/') ? baseURL.slice(0, -1) : baseURL,
    logo: json.logo
  };
}

export async function fetchCatalog(
  baseURL: string,
  type: string,
  id: string,
  extras?: Record<string, string>
): Promise<MetaPreview[]> {
  // Stremio extras are path segments, NOT query params
  // Correct format: /catalog/{type}/{id}/{key1}={val1}&{key2}={val2}.json
  let url: string;
  if (extras && Object.keys(extras).length > 0) {
    const extraParts = Object.entries(extras)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
      .join('&');
    url = `${baseURL}/catalog/${type}/${id}/${extraParts}.json`;
  } else {
    url = `${baseURL}/catalog/${type}/${id}.json`;
  }

  const res = await fetch(url);
  const json = await res.json();

  return (json.metas || []).map((m: any) => ({
    id: m.id,
    type: m.type || type,
    name: m.name || 'Unknown',
    poster: m.poster,
    banner: m.banner,
    logo: m.logo,
    posterShape: m.posterShape,
    description: m.description,
    releaseInfo: m.releaseInfo,
    imdbRating: m.imdbRating,
    genres: m.genres,
    popularity: m.popularity
  }));
}

export async function fetchMeta(
  baseURL: string,
  type: string,
  id: string
): Promise<MetaDetail | null> {
  try {
    const url = `${baseURL}/meta/${type}/${id}.json`;
    const res = await fetch(url);
    const json = await res.json();
    const m = json.meta;

    if (!m) return null;

    const videos = (m.videos || []).map((v: any) => ({
      id: v.id,
      title: v.name || v.title || `Episode ${v.episode}`,
      season: v.season,
      episode: v.episode || v.number,
      thumbnail: v.thumbnail,
      overview: v.overview || v.description,
      released: v.released || v.firstAired,
    }));

    // Build seasons from videos if seasons not provided
    let seasons = m.seasons || null;
    if ((!seasons || seasons.length === 0) && videos.length > 0) {
      const seasonMap = new Map<number, typeof videos>();
      for (const v of videos) {
        if (!v.season) continue;
        if (!seasonMap.has(v.season)) seasonMap.set(v.season, []);
        seasonMap.get(v.season)!.push(v);
      }
      seasons = Array.from(seasonMap.entries())
        .sort(([a], [b]) => a - b)
        .map(([num, eps]) => ({
          id: `${id}:${num}`,
          number: num,
          name: `Season ${num}`,
          episodes: eps.sort((a: any, b: any) => (a.episode || 0) - (b.episode || 0)),
        }));
    }

    return {
      id: m.id || id,
      type: m.type || type,
      name: m.name || 'Unknown',
      poster: m.poster,
      background: m.background,
      logo: m.logo,
      description: m.description,
      releaseInfo: m.releaseInfo,
      status: m.status,
      imdbRating: m.imdbRating,
      runtime: m.runtime,
      genres: m.genres,
      director: m.director,
      cast: (m.cast || []).map((c: any) =>
        typeof c === 'string'
          ? { id: c, name: c, photo: undefined }
          : { id: c.id || c.name, name: c.name || String(c), photo: c.photo }
      ).filter((c: any) => c.name),
      trailers: m.trailers,
      links: m.links,
      moreLikeThis: (m.moreLikeThis || []).map((r: any) => ({
        id: r.id, type: r.type || type, name: r.name,
        poster: r.poster, releaseInfo: r.releaseInfo, imdbRating: r.imdbRating,
      })),
      videos,
      seasons,
    };
  } catch {
    return null;
  }
}

export async function fetchStreams(
  baseURL: string,
  type: string,
  id: string
): Promise<StreamItem[]> {
  try {
    const url = `${baseURL}/stream/${type}/${id}.json`;
    const res = await fetch(url);
    const json = await res.json();
    return json.streams || [];
  } catch {
    return [];
  }
}

function hasResource(addon: AddonManifest, name: string): boolean {
  return !!addon.resources?.some(r => (typeof r === 'string' ? r : r.name) === name);
}

export interface SubtitleItem {
  id: string;
  url: string;
  lang: string;
  name?: string;
}

async function fetchSubtitles(baseURL: string, type: string, id: string): Promise<SubtitleItem[]> {
  try {
    const res = await fetch(`${baseURL}/subtitles/${type}/${id}.json`);
    const json = await res.json();
    return (json.subtitles || []).map((s: any, i: number) => ({
      id: s.id || s.url || String(i),
      url: s.url,
      lang: s.lang || 'und',
      name: s.id || undefined,
    }));
  } catch {
    return [];
  }
}

// Community OpenSubtitles Stremio addon — public, no auth, always available
const OPENSUBTITLES_ADDON_URL = 'https://opensubtitles-v3.strem.io';

export async function fetchSubtitlesFromAll(
  type: string,
  id: string,
  addons: AddonManifest[]
): Promise<SubtitleItem[]> {
  // Collect all addon URLs + always append OpenSubtitles as a guaranteed fallback.
  // Many addons also support subtitles without declaring it in their manifest, so
  // we try all of them rather than filtering by resource declaration.
  const urls = [
    ...addons.filter(a => !!a.transportUrl).map(a => a.transportUrl!),
    OPENSUBTITLES_ADDON_URL,
  ];
  const results = await Promise.allSettled(
    urls.map(url => fetchSubtitles(url, type, id))
  );
  // Deduplicate by subtitle URL so the same track doesn't appear twice
  const seen = new Set<string>();
  return results
    .filter((r): r is PromiseFulfilledResult<SubtitleItem[]> => r.status === 'fulfilled')
    .flatMap(r => r.value)
    .filter(s => { if (seen.has(s.url)) return false; seen.add(s.url); return true; });
}

export async function fetchStreamsFromAll(
  type: string,
  id: string,
  addons: AddonManifest[]
): Promise<StreamItem[]> {
  const results = await Promise.allSettled(
    addons
      .filter(a => a.transportUrl && hasResource(a, 'stream') && a.types?.includes(type))
      .map(async addon => {
        const streams = await fetchStreams(addon.transportUrl!, type, id);
        return streams.map(s => ({ ...s, addonName: addon.name, addonId: addon.id }));
      })
  );

  return results
    .filter((r): r is PromiseFulfilledResult<any[]> => r.status === 'fulfilled')
    .flatMap(r => r.value) as StreamItem[];
}

/**
 * Search across all addons that support the search extra.
 * Returns deduplicated results sorted by popularity.
 */
export async function searchCatalogs(
  addons: AddonManifest[],
  query: string
): Promise<MetaPreview[]> {
  if (!query.trim()) return [];

  const results: MetaPreview[] = [];

  await Promise.allSettled(
    addons
      .filter(a => a.transportUrl && a.catalogs && hasResource(a, 'catalog'))
      .flatMap(addon => {
        const searchableCatalogs = (addon.catalogs || []).filter(c =>
          c.extra?.some(e => e.name === 'search')
        );

        // If no search-enabled catalogs, try first 2 catalogs as fallback
        const catalogs = searchableCatalogs.length > 0
          ? searchableCatalogs
          : (addon.catalogs || []).slice(0, 2);

        return ['movie', 'series'].flatMap(mediaType =>
          catalogs
            .filter(c => c.type === mediaType || !c.type)
            .map(async catalog => {
              try {
                const items = await fetchCatalog(
                  addon.transportUrl!,
                  mediaType,
                  catalog.id,
                  { search: query }
                );
                results.push(...items);
              } catch { /* ignore */ }
            })
        );
      })
  );

  // Deduplicate by id and sort by popularity
  const seen = new Set<string>();
  return results
    .filter(item => {
      if (seen.has(item.id)) return false;
      seen.add(item.id);
      return true;
    })
    .sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0));
}

export async function fetchAllCatalogs(
  addons: AddonManifest[]
): Promise<{ id: string; title: string; items: MetaPreview[] }[]> {
  const results = await Promise.allSettled(
    addons
      .filter(a => a.transportUrl && a.catalogs && hasResource(a, 'catalog'))
      .flatMap(addon =>
        (addon.catalogs || []).map(async catalog => {
          const items = await fetchCatalog(addon.transportUrl!, catalog.type, catalog.id);
          return {
            id: `${addon.id}_${catalog.id}`,
            title: catalog.name || catalog.id,
            items
          };
        })
      )
  );

  return results
    .filter((r): r is PromiseFulfilledResult<any> => r.status === 'fulfilled')
    .map(r => r.value)
    .filter(row => row.items.length > 0);
}
