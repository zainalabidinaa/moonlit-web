import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { discoverCreativeRails, discoverGeneralRails, discoverGenreRails } from './tmdb-discover';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status });
}

describe('tmdb-discover', () => {
  beforeEach(() => {
    localStorage.clear();
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('returns no rails without an API key, never calling fetch', async () => {
    const fetchSpy = vi.fn();
    vi.stubGlobal('fetch', fetchSpy);
    const rails = await discoverGenreRails('Action', 'movie', '');
    expect(rails).toEqual([]);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('returns no rails for a genre with no TMDB id for that media kind (Horror has no TV genre)', async () => {
    const fetchSpy = vi.fn();
    vi.stubGlobal('fetch', fetchSpy);
    const rails = await discoverGenreRails('Horror', 'series', 'key');
    expect(rails).toEqual([]);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('resolves discover results to IMDb ids and builds the four standard rails', async () => {
    const fetchSpy = vi.fn(async (url: string) => {
      if (url.includes('/discover/movie')) {
        return jsonResponse({
          results: [
            { id: 1, title: 'Movie One', poster_path: '/one.jpg', release_date: '2024-05-01', vote_average: 7.5, popularity: 50 },
          ],
        });
      }
      if (url.includes('/movie/1/external_ids')) {
        return jsonResponse({ imdb_id: 'tt0000001' });
      }
      return jsonResponse({ results: [] });
    });
    vi.stubGlobal('fetch', fetchSpy);

    const rails = await discoverGenreRails('Action', 'movie', 'test-key');

    expect(rails.map(r => r.id)).toEqual(['tmdb-trending', 'tmdb-top-rated', 'tmdb-recent', 'tmdb-hidden-gems']);
    expect(rails[0].title).toBe('Trending Action');
    expect(rails[0].items[0]).toMatchObject({ id: 'tt0000001', name: 'Movie One', imdbRating: '7.5', releaseInfo: '2024' });
  });

  it('drops results with no resolvable IMDb id instead of surfacing them with a placeholder id', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (url.includes('/discover/')) {
        return jsonResponse({ results: [{ id: 2, title: 'No IMDb Match' }] });
      }
      return jsonResponse({ imdb_id: null });
    }));

    const rails = await discoverGenreRails('Action', 'movie', 'test-key');
    for (const rail of rails) {
      expect(rail.items.find(i => i.name === 'No IMDb Match')).toBeUndefined();
    }
  });

  it('caches a confirmed 200 resolution and never re-requests it', async () => {
    const fetchSpy = vi.fn(async (url: string) => {
      if (url.includes('/discover/')) {
        return jsonResponse({ results: [{ id: 3, title: 'Cached Movie' }] });
      }
      return jsonResponse({ imdb_id: 'tt0000003' });
    });
    vi.stubGlobal('fetch', fetchSpy);

    await discoverGenreRails('Action', 'movie', 'test-key');
    const externalIdCallsFirst = fetchSpy.mock.calls.filter(([url]) => url.includes('external_ids')).length;
    expect(externalIdCallsFirst).toBeGreaterThan(0);

    fetchSpy.mockClear();
    await discoverGenreRails('Action', 'movie', 'test-key');
    const externalIdCallsSecond = fetchSpy.mock.calls.filter(([url]) => url.includes('external_ids')).length;
    expect(externalIdCallsSecond).toBe(0);
  });

  it('does not cache a rate-limit/error response as a permanent miss', async () => {
    let externalIdCalls = 0;
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (url.includes('/discover/')) return jsonResponse({ results: [{ id: 4, title: 'Rate Limited' }] });
      externalIdCalls += 1;
      return jsonResponse({ status_message: 'rate limited' }, 429);
    }));

    // discoverGenreRails fires 4 parallel discover queries (trending/top/new/hidden),
    // each independently resolving the same result — with nothing ever cached (every
    // response is a 429), all 4 re-hit external_ids on both invocations: 8 total.
    await discoverGenreRails('Action', 'movie', 'test-key');
    await discoverGenreRails('Action', 'movie', 'test-key');
    expect(externalIdCalls).toBe(8);
  });

  it('builds general "All" rails with kind-appropriate nouns', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (url.includes('/discover/')) return jsonResponse({ results: [{ id: 5, title: 'Series One' }] });
      return jsonResponse({ imdb_id: 'tt0000005' });
    }));

    const rails = await discoverGeneralRails('series', 'test-key');
    expect(rails.map(r => r.title)).toEqual(['Trending Series', 'Popular Series', 'Top Rated Series', 'Hidden Gems', 'New Releases']);
  });

  it('builds creative rails only for genres with a mapping, and skips empty ones', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (url.includes('with_keywords=779')) return jsonResponse({ results: [{ id: 6, title: 'Martial Arts Movie' }] });
      if (url.includes('/discover/')) return jsonResponse({ results: [] });
      return jsonResponse({ imdb_id: 'tt0000006' });
    }));

    const rails = await discoverCreativeRails('Action', 'movie', 'test-key');
    expect(rails.map(r => r.id)).toEqual(['creative-martial-arts']);

    const none = await discoverCreativeRails('Not A Genre', 'movie', 'test-key');
    expect(none).toEqual([]);
  });
});
