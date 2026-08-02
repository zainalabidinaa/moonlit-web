import { describe, expect, it } from 'vitest';

import { availableGenres, canonicalGenreName, tmdbGenreId } from './tmdb-genre-ids';

describe('tmdb-genre-ids', () => {
  it('resolves movie and series ids for a directly-named genre', () => {
    expect(tmdbGenreId('Action', 'movie')).toBe(28);
    expect(tmdbGenreId('Action', 'series')).toBe(10759);
  });

  it('resolves aliases TMDB/addon metadata actually emits', () => {
    expect(canonicalGenreName('Science Fiction')).toBe('Sci-Fi');
    expect(canonicalGenreName('Sci-Fi & Fantasy')).toBe('Sci-Fi');
    expect(canonicalGenreName('Action & Adventure')).toBe('Action');
    expect(canonicalGenreName('Kids')).toBe('Family');
  });

  it('returns null for a series id when TMDB has no TV equivalent', () => {
    expect(tmdbGenreId('Horror', 'series')).toBeNull();
    expect(tmdbGenreId('Romance', 'series')).toBeNull();
    expect(tmdbGenreId('Thriller', 'series')).toBeNull();
  });

  it('returns null for an unresolvable genre label', () => {
    expect(tmdbGenreId('Not A Genre', 'movie')).toBeNull();
  });

  it('drops series-less genres from the available list for series', () => {
    const genres = availableGenres('series');
    expect(genres).not.toContain('Horror');
    expect(genres).not.toContain('Romance');
    expect(genres).not.toContain('Thriller');
    expect(genres).toContain('Action');
  });
});
