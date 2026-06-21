import { NuvioSource, DBFolderCatalog, DBFolderSource } from './types';

// DISCOVER title → catalogId mapping (from iOS CollectionOrganizerParser)
const DISCOVER_TITLE_MAP: Record<string, Record<string, string>> = {
  movie: {
    'new movies': 'tmdb.discover.movie.new-movies.069d5312',
    'popular movies': 'tmdb.discover.movie.popular-movies.29727d26',
    'top all time movies': 'tmdb.discover.movie.top-all-time-movies.39f5a0c4',
    'top of the year movies': 'tmdb.discover.movie.top-of-the-year-movies.870b3ada',
    'anime movies': 'tmdb.discover.movie.anime-movies.8caaddea',
    'top anime movies': 'tmdb.discover.movie.top-anime-movies.ef410dcc',
    'upcoming anime movies': 'tmdb.discover.movie.upcoming-anime-movies.e57db259',
  },
  series: {
    'new series': 'tmdb.discover.series.new-series.76fc7ade',
    'popular series': 'tmdb.discover.series.popular-series.20af3ad9',
    'top all time series': 'tmdb.discover.series.top-all-time-series.53046f30',
    'top of the year series': 'tmdb.discover.series.top-of-the-year-series.f0fd20b7',
    'anime series': 'tmdb.discover.series.anime-series.193e8308',
    'top anime series': 'tmdb.discover.series.top-anime-series.63ff4f07',
    'upcoming anime series': 'tmdb.discover.series.upcoming-anime-series.e71e22cf',
  },
};

interface ResolvedSource {
  catalog?: DBFolderCatalog;
  raw?: DBFolderSource;
}

export function resolveNuvioSource(source: NuvioSource, folderId: string): ResolvedSource | null {
  // Determine effective catalogId
  let catalogId: string | null = null;

  if (source.catalogId) {
    catalogId = source.catalogId;
  } else if (source.traktListId) {
    catalogId = `trakt.list.${source.traktListId}`;
  } else if (source.tmdbId && source.tmdbSourceType === 'COLLECTION') {
    catalogId = `tmdb.collection.${source.tmdbId}`;
  } else if (source.tmdbSourceType === 'DISCOVER') {
    // Try title match first
    const titleLower = (source.title || '').toLowerCase();
    const mediaType = (source.mediaType || source.type || 'movie').toLowerCase();
    const titleMap = DISCOVER_TITLE_MAP[mediaType];
    if (titleMap && titleMap[titleLower]) {
      catalogId = titleMap[titleLower];
    } else if (source.filters?.releaseDateGte) {
      // Decade catalog
      const decade = getDecadeName(Number(source.filters.releaseDateGte.slice(0, 4)));
      catalogId = `tmdb.discover.${mediaType}.decades.${decade}s`;
    }
  }

  if (!catalogId) return null;

  const mediaType = normalizeMediaType(source.mediaType || source.type || '');

  // Build extras from filters
  const extras: Record<string, string> = {};
  if (source.filters?.releaseDateGte) extras['primary_release_date.gte'] = source.filters.releaseDateGte;
  if (source.filters?.releaseDateLte) extras['primary_release_date.lte'] = source.filters.releaseDateLte;
  if (source.filters?.voteCountGte) extras['vote_count.gte'] = String(source.filters.voteCountGte);
  if (source.filters?.voteAverageGte) extras['vote_average.gte'] = String(Math.round(source.filters.voteAverageGte));
  if (source.filters?.withOriginalLanguage) extras['with_original_language'] = source.filters.withOriginalLanguage;
  if (source.filters?.year) extras['year'] = String(source.filters.year);
  if (source.sortBy) extras['sort_by'] = source.sortBy;

  // Determine if this is an addon source or a raw provider source
  const provider = (source.provider || '').toLowerCase();
  const isRaw = ['trakt', 'tmdb', 'mdblist', 'tvdb', 'streaming'].includes(provider);

  if (isRaw) {
    return {
      raw: {
        folderId,
        provider,
        title: source.title,
        mediaType,
        tmdbId: extractTmdbId(catalogId, provider),
        tmdbSourceType: catalogId.includes('discover') ? 'discover' : undefined,
        sortBy: source.sortBy,
        filtersJson: source.filters ? JSON.stringify(source.filters) : undefined,
      },
    };
  }

  return {
    catalog: {
      folderId,
      catalogId,
      mediaType,
      genre: source.genre || resolveGenre(source),
      extras: Object.keys(extras).length > 0 ? extras : undefined,
    },
  };
}

function normalizeMediaType(type: string): string {
  const t = type.toUpperCase();
  if (t === 'MOVIE' || t === 'MOVIES') return 'movie';
  if (t === 'SERIES' || t === 'TV' || t === 'TV SHOW') return 'series';
  if (t === 'ALL') return 'all';
  return t.toLowerCase() || 'movie';
}

function extractTmdbId(catalogId: string, provider: string): string {
  if (provider === 'trakt') {
    return catalogId.replace('trakt.list.', '');
  }
  const parts = catalogId.split('.');
  return parts[parts.length - 1] || '';
}

function getDecadeName(year: number): string {
  const d = Math.floor(year / 10) * 10;
  return String(d);
}

function resolveGenre(source: NuvioSource): string | undefined {
  if (source.filters?.withGenres) {
    // Just pass through the first genre ID — genre resolution happens at fetch time
    const firstGenre = source.filters.withGenres.split(',')[0].trim();
    return firstGenre;
  }
  return undefined;
}
