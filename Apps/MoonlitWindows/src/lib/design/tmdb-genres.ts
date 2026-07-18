export const TMDB_MOVIE_GENRES: Record<string, number> = {
  'Action': 28,
  'Adventure': 12,
  'Animation': 16,
  'Comedy': 35,
  'Crime': 80,
  'Documentary': 99,
  'Drama': 18,
  'Family': 10751,
  'Fantasy': 14,
  'History': 36,
  'Horror': 27,
  'Music': 10402,
  'Mystery': 9648,
  'Romance': 10749,
  'Science Fiction': 878,
  'Thriller': 53,
  'War': 10752,
  'Western': 37,
};

export const TMDB_TV_GENRES: Record<string, number> = {
  'Action & Adventure': 10759,
  'Animation': 16,
  'Comedy': 35,
  'Crime': 80,
  'Documentary': 99,
  'Drama': 18,
  'Family': 10751,
  'Kids': 10762,
  'Mystery': 9648,
  'News': 10763,
  'Reality': 10764,
  'Sci-Fi & Fantasy': 10765,
  'Soap': 10766,
  'Talk': 10767,
  'War & Politics': 10768,
  'Western': 37,
};

export function availableGenres(mediaKind: 'movie' | 'series'): string[] {
  return Object.keys(mediaKind === 'movie' ? TMDB_MOVIE_GENRES : TMDB_TV_GENRES);
}

export function tmdbGenreId(mediaKind: 'movie' | 'series', genre: string): number | undefined {
  return mediaKind === 'movie' ? TMDB_MOVIE_GENRES[genre] : TMDB_TV_GENRES[genre];
}

export async function fetchTMDBDiscover(
  mediaKind: 'movie' | 'series',
  genre: string,
  sortBy: string,
  apiKey: string,
): Promise<{ items: import('@/lib/types').MetaPreview[] }> {
  const genreId = tmdbGenreId(mediaKind, genre);
  const type = mediaKind === 'movie' ? 'movie' : 'tv';
  let url = `https://api.themoviedb.org/3/discover/${type}?api_key=${apiKey}&sort_by=${sortBy}&vote_count.gte=100&with_original_language=en`;
  if (genreId) url += `&with_genres=${genreId}`;

  try {
    const res = await fetch(url);
    if (!res.ok) return { items: [] };
    const data = await res.json();
    const items: import('@/lib/types').MetaPreview[] = (data.results || []).map((m: any) => ({
      id: type === 'movie' ? `tt${m.id}` : `series:tmdb:${m.id}`,
      type: mediaKind,
      name: m.title || m.name || 'Unknown',
      poster: m.poster_path ? `https://image.tmdb.org/t/p/w342${m.poster_path}` : undefined,
      releaseInfo: (m.release_date || m.first_air_date || '').slice(0, 4),
      imdbRating: m.vote_average ? String(m.vote_average.toFixed(1)) : undefined,
      description: m.overview,
    }));
    return { items };
  } catch {
    return { items: [] };
  }
}
