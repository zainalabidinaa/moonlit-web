import { normalize } from './genre-catalog';

/**
 * Maps Moonlit's canonical genre names to TMDB's genre ids, separately for
 * movies and TV — the two id spaces don't match (e.g. movie "Action" is 28,
 * TV's closest equivalent is "Action & Adventure" at 10759). Some genres have
 * no TV equivalent in TMDB at all (Horror, Romance, Thriller); those resolve
 * to `null` for the series id.
 *
 * Ported from Packages/MoonlitCore/Sources/MoonlitCore/Models/TMDBGenreIDs.swift.
 */

type MediaKind = 'movie' | 'series';

interface Mapping { movieId: number | null; tvId: number | null }

const MAPPING: Record<string, Mapping> = {
  Action: { movieId: 28, tvId: 10759 },
  Adventure: { movieId: 12, tvId: 10759 },
  Animation: { movieId: 16, tvId: 16 },
  Comedy: { movieId: 35, tvId: 35 },
  Crime: { movieId: 80, tvId: 80 },
  Documentary: { movieId: 99, tvId: 99 },
  Drama: { movieId: 18, tvId: 18 },
  Family: { movieId: 10751, tvId: 10751 },
  Fantasy: { movieId: 14, tvId: 10765 },
  Horror: { movieId: 27, tvId: null },
  Mystery: { movieId: 9648, tvId: 9648 },
  Romance: { movieId: 10749, tvId: null },
  'Sci-Fi': { movieId: 878, tvId: 10765 },
  Thriller: { movieId: 53, tvId: null },
  War: { movieId: 10752, tvId: 10768 },
  Western: { movieId: 37, tvId: 37 },
};

/** Canonical genre names in display order for the browse pills. */
export const CANONICAL_ORDER = [
  'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary',
  'Drama', 'Family', 'Fantasy', 'Horror', 'Mystery', 'Romance',
  'Sci-Fi', 'Thriller', 'War', 'Western',
];

/**
 * Aliases for genre labels real metadata sources emit that don't match
 * Moonlit's canonical spelling — TMDB's own TV genre names (which merge
 * several movie genres under one umbrella, e.g. "Sci-Fi & Fantasy"), TMDB's
 * movie genre name for Sci-Fi ("Science Fiction"), and common addon-catalog
 * variants.
 */
const ALIASES: Record<string, string> = {
  'science fiction': 'Sci-Fi',
  'sci fi': 'Sci-Fi',
  scifi: 'Sci-Fi',
  'sci-fi & fantasy': 'Sci-Fi',
  'action & adventure': 'Action',
  'war & politics': 'War',
  kids: 'Family',
  documentaries: 'Documentary',
  'mystery & thriller': 'Thriller',
};

/**
 * Resolves an arbitrary genre label from any metadata source to a canonical
 * Moonlit genre name, or null when it maps to nothing TMDB can discover.
 */
export function canonicalGenreName(rawName: string): string | null {
  const key = normalize(rawName);
  const exact = CANONICAL_ORDER.find(name => normalize(name) === key);
  if (exact) return exact;
  return ALIASES[key] ?? null;
}

/**
 * The TMDB genre id for a genre label and media kind, or null when unmapped
 * (unresolvable label, or no TV equivalent exists).
 */
export function tmdbGenreId(genreName: string, mediaKind: MediaKind): number | null {
  const canonical = canonicalGenreName(genreName);
  if (!canonical) return null;
  const entry = MAPPING[canonical];
  if (!entry) return null;
  return mediaKind === 'movie' ? entry.movieId : entry.tvId;
}

/** Genres that actually resolve for a media kind — e.g. Horror/Romance/Thriller have no TV id. */
export function availableGenres(mediaKind: MediaKind): string[] {
  return CANONICAL_ORDER.filter(name => tmdbGenreId(name, mediaKind) !== null);
}
