import { beforeEach, describe, expect, it, vi } from 'vitest';

const { stremioFetch } = vi.hoisted(() => ({ stremioFetch: vi.fn() }));

vi.mock('./platform/net', () => ({
  stremioFetch,
  subtitleTrackUrl: (url: string) => url,
}));

import { fetchCatalog, fetchMeta, selectSubtitleAddonUrls } from './stremio';
import type { AddonManifest } from './types';

beforeEach(() => { stremioFetch.mockReset(); });

describe('Stremio metadata normalization', () => {
  it('preserves catalog badge, preview, and awards enrichment from addon payloads', async () => {
    stremioFetch.mockResolvedValue({
      json: async () => ({
        metas: [{
          id: 'tt-enriched',
          type: 'movie',
          name: 'Enriched Movie',
          poster: 'poster.jpg',
          quality: '4K',
          ageRating: '16+',
          previewVideo: 'preview.mp4',
          awards: '2 wins · 7 nominations',
        }],
      }),
    });

    const [item] = await fetchCatalog('https://addon.example.com', 'movie', 'popular');

    expect(item).toMatchObject({
      quality: '4K',
      ageRating: '16+',
      previewVideo: 'preview.mp4',
      awards: '2 wins · 7 nominations',
    });
  });

  it('normalizes addon gallery and awards fields for the live detail path', async () => {
    stremioFetch.mockResolvedValue({
      json: async () => ({
        meta: {
          id: 'tt-detail',
          type: 'movie',
          name: 'Detail Movie',
          gallery: [
            'still-one.jpg',
            { id: 'still-two', url: 'still-two.jpg', caption: 'On set' },
          ],
          awards: 'Winner · Best Picture',
        },
      }),
    });

    const detail = await fetchMeta('https://addon.example.com', 'movie', 'tt-detail');

    expect(detail?.gallery).toEqual([
      { id: 'gallery-1', url: 'still-one.jpg' },
      { id: 'still-two', url: 'still-two.jpg', caption: 'On set' },
    ]);
    expect(detail?.awards).toEqual(['Winner · Best Picture']);
  });
});

describe('selectSubtitleAddonUrls', () => {
  it('uses declared subtitle addons and the public fallback without probing stream-only addons', () => {
    const addons: AddonManifest[] = [
      {
        id: 'streams',
        name: 'Streams',
        version: '1.0.0',
        transportUrl: 'https://streams.example.com',
        resources: ['stream'],
      },
      {
        id: 'subs',
        name: 'Subtitles',
        version: '1.0.0',
        transportUrl: 'https://subs.example.com',
        resources: [{ name: 'subtitles', types: ['series'] }],
      },
    ];

    expect(selectSubtitleAddonUrls('series', addons)).toEqual([
      'https://subs.example.com',
      'https://opensubtitles-v3.strem.io',
    ]);
  });
});
