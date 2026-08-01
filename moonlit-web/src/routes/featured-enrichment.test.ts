import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { AddonManifest, FeaturedHomeItem, MetaDetail } from '@/lib/types';
import { loadFeaturedEnrichment } from './featured-enrichment';

const { fetchMeta } = vi.hoisted(() => ({ fetchMeta: vi.fn() }));

vi.mock('@/lib/stremio', () => ({ fetchMeta }));
vi.mock('@/lib/supabase', () => ({ TMDB_API_KEY: 'test-key' }));

const addons: AddonManifest[] = [{
  id: 'metadata-addon',
  name: 'Metadata addon',
  version: '1.0.0',
  transportUrl: 'https://addon.example.com',
  resources: ['meta'],
}];

const featured: FeaturedHomeItem = {
  row: {
    id: 'featured-row',
    title: 'Featured',
    type: 'movie',
    catalogId: 'featured',
    items: [],
  },
  item: {
    id: 'tt-feature',
    type: 'movie',
    name: 'Feature',
    poster: 'https://example.com/catalog-poster.jpg',
  },
};

describe('loadFeaturedEnrichment source isolation', () => {
  beforeEach(() => {
    fetchMeta.mockReset();
  });

  it('publishes successful addon metadata and fallback artwork when TMDB rejects', async () => {
    const meta: MetaDetail = {
      id: 'tt-feature',
      type: 'movie',
      name: 'Enriched Feature',
      logo: 'https://example.com/logo.png',
      poster: 'https://example.com/addon-poster.jpg',
      awards: ['3 wins · 5 nominations'],
    };
    fetchMeta.mockResolvedValue(meta);
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('TMDB unavailable')));

    const result = await loadFeaturedEnrichment([featured], addons);

    expect(result.metas['tt-feature']).toEqual(meta);
    expect(result.awards['tt-feature']).toBe('3 wins · 5 nominations');
    expect(result.backdrops['tt-feature']).toBe('https://example.com/addon-poster.jpg');
  });

  it('publishes TMDB artwork when addon metadata rejects', async () => {
    fetchMeta.mockRejectedValue(new Error('Addon unavailable'));
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ movie_results: [{ id: 77, backdrop_path: '/community.jpg' }] }),
    }));

    const result = await loadFeaturedEnrichment([featured], addons);

    expect(result.metas['tt-feature']).toBeNull();
    expect(result.backdrops['tt-feature']).toBe('https://image.tmdb.org/t/p/w1280/community.jpg');
  });
});
