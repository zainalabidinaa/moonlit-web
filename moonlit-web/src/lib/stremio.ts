import { AddonManifest, MetaPreview, MetaDetail, MetaVideo, Season, StreamItem } from './types';
import { stremioFetch, subtitleTrackUrl } from './platform/net';

interface RawCatalogMeta extends Omit<Partial<MetaPreview>, 'awards'> {
  age_rating?: string;
  certification?: string;
  preview_video?: string;
  behaviorHints?: { quality?: string; previewVideo?: string };
  awards?: unknown;
}

interface RawMetaVideo extends Partial<MetaVideo> {
  name?: string;
  number?: number;
  description?: string;
  firstAired?: string;
}

interface RawCastMember {
  id?: string;
  name?: string;
  photo?: string;
}

interface RawMetaDetail extends Omit<Partial<MetaDetail>, 'cast' | 'videos' | 'moreLikeThis' | 'gallery' | 'awards'> {
  cast?: (string | RawCastMember)[];
  videos?: RawMetaVideo[];
  moreLikeThis?: Partial<MetaPreview>[];
  moviedb_id?: string | number;
  gallery?: unknown;
  awards?: unknown;
}

interface RawSubtitle {
  id?: string;
  url?: string;
  lang?: string;
}

function normalizeAwards(value: unknown): string[] {
  if (typeof value === 'string' && value.trim()) return [value.trim()];
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === 'string' && Boolean(entry.trim()));
}

function normalizeGallery(value: unknown): NonNullable<MetaDetail['gallery']> {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry, index) => {
    if (typeof entry === 'string' && entry) {
      return [{ id: `gallery-${index + 1}`, url: entry }];
    }
    if (!entry || typeof entry !== 'object') return [];
    const image = entry as { id?: unknown; url?: unknown; caption?: unknown };
    if (typeof image.url !== 'string' || !image.url) return [];
    return [{
      id: typeof image.id === 'string' && image.id ? image.id : `gallery-${index + 1}`,
      url: image.url,
      ...(typeof image.caption === 'string' && image.caption ? { caption: image.caption } : {}),
    }];
  });
}

export async function fetchManifest(url: string): Promise<AddonManifest> {
  const res = await stremioFetch('manifest', { url });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Manifest fetch failed (${res.status}): ${text.slice(0, 120)}`);
  }
  const json = await res.json();

  const baseURL = json.transportUrl || url.replace(/\/manifest\.json(\?.*)?$/, '');

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

/**
 * Strips the `stream` resource from a manifest — used for admin-curated addons
 * inherited via get_shared_addons(), so the backend can propagate catalog/
 * metadata/subtitle addons to other users without ever handing them a stream
 * source through that channel. Mirrors AddonManifest.strippingStreamResource()
 * in native (Packages/MoonlitCore).
 */
export function stripStreamResource(manifest: AddonManifest): AddonManifest {
  if (!manifest.resources) return manifest;
  const resources = manifest.resources.filter(resource =>
    (typeof resource === 'string' ? resource : resource.name) !== 'stream',
  );
  return { ...manifest, resources };
}

export async function fetchCatalog(
  baseURL: string,
  type: string,
  id: string,
  extras?: Record<string, string>
): Promise<MetaPreview[]> {
  const params = new URLSearchParams({ url: baseURL, type, id });
  if (extras && Object.keys(extras).length > 0) {
    params.set('extras', JSON.stringify(extras));
  }
  const res = await stremioFetch('catalog', { url: baseURL, type, id, extras });
  const json = await res.json() as { metas?: RawCatalogMeta[] };

  return (json.metas || [])
    .filter((m): m is RawCatalogMeta & Pick<MetaPreview, 'id'> => typeof m.id === 'string')
    .map(m => ({
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
      popularity: m.popularity,
      quality: m.quality || m.behaviorHints?.quality,
      ageRating: m.ageRating || m.age_rating || m.certification,
      previewVideo: m.previewVideo || m.preview_video || m.behaviorHints?.previewVideo,
      awards: normalizeAwards(m.awards)[0],
    }));
}

export async function fetchMeta(
  baseURL: string,
  type: string,
  id: string
): Promise<MetaDetail | null> {
  try {
    const res = await stremioFetch('meta', { url: baseURL, type, id });
    const json = await res.json() as { meta?: RawMetaDetail };
    const m = json.meta;

    if (!m) return null;

    const videos: MetaVideo[] = (m.videos || []).map(v => ({
      id: v.id || `${id}:${v.season ?? 0}:${v.episode ?? v.number ?? 0}`,
      title: v.name || v.title || `Episode ${v.episode}`,
      season: v.season,
      episode: v.episode || v.number,
      thumbnail: v.thumbnail,
      overview: v.overview || v.description,
      released: v.released || v.firstAired,
    }));

    // Build seasons from videos if seasons not provided; filter out season 0 (specials)
    let seasons: Season[] | undefined = m.seasons?.filter(s => s.number !== 0);
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
          episodes: eps.sort((a, b) => (a.episode || 0) - (b.episode || 0)),
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
      cast: (m.cast || []).map(c => {
        if (typeof c === 'string') return { id: c, name: c, photo: undefined };
        const name = c.name || String(c);
        return { id: c.id || name, name, photo: c.photo };
      }).filter(c => c.name),
      trailers: m.trailers,
      links: m.links,
      moreLikeThis: (m.moreLikeThis || []).filter(
        (recommendation): recommendation is Partial<MetaPreview> & Pick<MetaPreview, 'id' | 'name'> =>
          typeof recommendation.id === 'string' && typeof recommendation.name === 'string',
      ).map(r => ({
        id: r.id, type: r.type || type, name: r.name,
        poster: r.poster, releaseInfo: r.releaseInfo, imdbRating: r.imdbRating,
      })),
      videos,
      seasons,
      tmdbId: m.moviedb_id ? String(m.moviedb_id) : undefined,
      gallery: normalizeGallery(m.gallery),
      awards: normalizeAwards(m.awards),
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
    const res = await stremioFetch('stream', { url: baseURL, type, id });
    const json = await res.json() as { streams?: StreamItem[] };
    return json.streams || [];
  } catch {
    return [];
  }
}

function hasResource(addon: AddonManifest, name: string): boolean {
  return !!addon.resources?.some(r => (typeof r === 'string' ? r : r.name) === name);
}

/**
 * Returns true if the addon can provide `resourceName` for `contentType`.
 * Checks resource-level types first (Stremio v4+ manifests), then falls
 * back to the top-level `types` array. If neither declares types, assume
 * the addon supports all types (some older addons omit the field entirely).
 */
function addonSupportsType(addon: AddonManifest, resourceName: string, contentType: string): boolean {
  if (!addon.resources) return false;
  for (const r of addon.resources) {
    const rName = typeof r === 'string' ? r : r.name;
    if (rName !== resourceName) continue;
    // Resource found — check its declared types
    const rTypes = typeof r === 'string' ? null : r.types;
    if (rTypes && rTypes.length > 0) return rTypes.includes(contentType);
    // Fall back to top-level types; if absent, assume all types supported
    return addon.types ? addon.types.includes(contentType) : true;
  }
  return false;
}

export interface SubtitleItem {
  id: string;
  url: string;
  lang: string;
  name?: string;
}

async function fetchSubtitles(baseURL: string, type: string, id: string): Promise<SubtitleItem[]> {
  try {
    const res = await stremioFetch('subtitles', { url: baseURL, type, id });
    const json = await res.json() as { subtitles?: RawSubtitle[] };
    const langNames = new Intl.DisplayNames(['en'], { type: 'language' });
    return (json.subtitles || [])
      .filter((subtitle): subtitle is RawSubtitle & { url: string } => Boolean(subtitle.url))
      .map((s, i) => {
        const lang = s.lang || 'und';
        let displayName: string;
        try { displayName = langNames.of(lang) || lang; } catch { displayName = lang; }
        return {
          id: s.id || s.url || String(i),
          url: subtitleTrackUrl(s.url),
          lang,
          name: displayName,
        };
      });
  } catch {
    return [];
  }
}

// Community OpenSubtitles Stremio addon — public, no auth, always available
const OPENSUBTITLES_ADDON_URL = 'https://opensubtitles-v3.strem.io';

export function selectSubtitleAddonUrls(type: string, addons: AddonManifest[]): string[] {
  return [
    ...addons
      .filter(a => a.transportUrl && addonSupportsType(a, 'subtitles', type))
      .map(a => a.transportUrl!),
    OPENSUBTITLES_ADDON_URL,
  ].filter((url, index, all) => all.indexOf(url) === index);
}

export async function fetchSubtitlesFromAll(
  type: string,
  id: string,
  addons: AddonManifest[]
): Promise<SubtitleItem[]> {
  const urls = selectSubtitleAddonUrls(type, addons);
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
      .filter(a => a.transportUrl && addonSupportsType(a, 'stream', type))
      .map(async addon => {
        const streams = await fetchStreams(addon.transportUrl!, type, id);
        return streams.map(s => ({ ...s, addonName: addon.name, addonId: addon.id }));
      })
  );

  return results
    .flatMap(result => result.status === 'fulfilled' ? result.value : []);
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
  type CatalogResult = { id: string; title: string; items: MetaPreview[] };
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
    .filter((r): r is PromiseFulfilledResult<CatalogResult> => r.status === 'fulfilled')
    .map(r => r.value)
    .filter(row => row.items.length > 0);
}
