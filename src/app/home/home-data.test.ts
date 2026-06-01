import { describe, expect, it } from 'vitest';

import type { AddonManifest, MetaPreview } from '@/lib/types';

import { buildHomeRows, pickFeaturedItem, selectInitialCatalogs } from './home-data';

describe('selectInitialCatalogs', () => {
  it('limits first-paint catalogs and prefers strong rows', () => {
    const manifest: AddonManifest = {
      id: 'addon.test',
      name: 'Test Addon',
      version: '1.0.0',
      catalogs: [
        { type: 'channel', id: 'live', name: 'Live TV' },
        { type: 'movie', id: 'library', name: 'Library Movies' },
        { type: 'movie', id: 'popular', name: 'Popular Movies' },
        { type: 'series', id: 'trending', name: 'Trending Series' },
        { type: 'movie', id: 'featured', name: 'Featured Movies' },
        { type: 'series', id: 'recent', name: 'Recently Added Series' },
      ],
    };

    expect(selectInitialCatalogs(manifest)).toEqual([
      manifest.catalogs![2],
      manifest.catalogs![3],
      manifest.catalogs![4],
      manifest.catalogs![1],
    ]);
  });
});

describe('buildHomeRows', () => {
  it('returns an empty list when the manifest has no catalogs', () => {
    const manifest: AddonManifest = {
      id: 'addon.test',
      name: 'Test Addon',
      version: '1.0.0',
    };

    expect(buildHomeRows(manifest, {})).toEqual([]);
  });

  it('builds addon-driven rows from the manifest and skips empty catalogs', () => {
    const manifest: AddonManifest = {
      id: 'addon.test',
      name: 'Test Addon',
      version: '1.0.0',
      catalogs: [
        { type: 'movie', id: 'popular-movies', name: 'Popular Movies' },
        { type: 'series', id: 'trending-series', name: 'Trending Series' },
        { type: 'movie', id: 'empty-movies', name: 'Empty Movies' },
      ],
    };

    const movieItems: MetaPreview[] = [
      { id: 'tt1', type: 'movie', name: 'Movie One' },
      { id: 'tt2', type: 'movie', name: 'Movie Two' },
    ];
    const seriesItems: MetaPreview[] = [
      { id: 'ts1', type: 'series', name: 'Series One' },
    ];

    expect(
      buildHomeRows(manifest, {
        'popular-movies': movieItems,
        'trending-series': seriesItems,
        'empty-movies': [],
      })
    ).toEqual([
      {
        id: 'addon.test_movie_popular-movies',
        title: 'Popular Movies',
        type: 'movie',
        catalogId: 'popular-movies',
        items: movieItems,
        isMainRow: true,
      },
      {
        id: 'addon.test_series_trending-series',
        title: 'Trending Series',
        type: 'series',
        catalogId: 'trending-series',
        items: seriesItems,
        isMainRow: false,
      },
    ]);
  });

  it('prefers composite catalog lookup keys when catalog ids repeat across types', () => {
    const manifest: AddonManifest = {
      id: 'addon.test',
      name: 'Test Addon',
      version: '1.0.0',
      catalogs: [
        { type: 'movie', id: 'popular', name: 'Popular Movies' },
        { type: 'series', id: 'popular', name: 'Popular Series' },
      ],
    };

    const movieItems: MetaPreview[] = [
      { id: 'm1', type: 'movie', name: 'Movie One' },
    ];
    const seriesItems: MetaPreview[] = [
      { id: 's1', type: 'series', name: 'Series One' },
    ];

    expect(
      buildHomeRows(manifest, {
        popular: [{ id: 'fallback', type: 'movie', name: 'Fallback Item' }],
        'movie:popular': movieItems,
        'series:popular': seriesItems,
      })
    ).toEqual([
      {
        id: 'addon.test_movie_popular',
        title: 'Popular Movies',
        type: 'movie',
        catalogId: 'popular',
        items: movieItems,
        isMainRow: true,
      },
      {
        id: 'addon.test_series_popular',
        title: 'Popular Series',
        type: 'series',
        catalogId: 'popular',
        items: seriesItems,
        isMainRow: false,
      },
    ]);
  });
});

describe('pickFeaturedItem', () => {
  it('returns null when there are no rows', () => {
    expect(pickFeaturedItem([])).toBeNull();
  });

  it('prefers popular or trending movie and series rows for the hero', () => {
    const genericMovie: MetaPreview = { id: 'm1', type: 'movie', name: 'Generic Movie' };
    const featuredChannel: MetaPreview = { id: 'c1', type: 'channel', name: 'Featured Channel' };
    const trendingSeries: MetaPreview = { id: 's1', type: 'series', name: 'Trending Series Item' };
    const backupTrendingSeries: MetaPreview = { id: 's2', type: 'series', name: 'Backup Trending Series Item' };

    const rows = [
      {
        id: 'recent-movies',
        title: 'Recently Added',
        type: 'movie',
        catalogId: 'recent-movies',
        items: [genericMovie],
      },
      {
        id: 'featured-channels',
        title: 'Featured Channels',
        type: 'channel',
        catalogId: 'featured-channels',
        items: [featuredChannel],
      },
      {
        id: 'trending-series',
        title: 'Trending Series',
        type: 'series',
        catalogId: 'trending-series',
        items: [trendingSeries, backupTrendingSeries],
      },
    ];

    expect(pickFeaturedItem(rows)).toEqual({
      row: rows[2],
      item: trendingSeries,
    });
  });

  it('keeps the earliest row when scores are tied', () => {
    const firstItem: MetaPreview = { id: 'm1', type: 'movie', name: 'First Movie' };
    const secondItem: MetaPreview = { id: 'm2', type: 'movie', name: 'Second Movie' };

    const rows = [
      {
        id: 'row-1',
        title: 'Popular Movies',
        type: 'movie',
        catalogId: 'popular-1',
        items: [firstItem],
      },
      {
        id: 'row-2',
        title: 'Popular Films',
        type: 'movie',
        catalogId: 'popular-2',
        items: [secondItem],
      },
    ];

    expect(pickFeaturedItem(rows)).toEqual({
      row: rows[0],
      item: firstItem,
    });
  });

  it('does not let composite row ids influence hero scoring', () => {
    const plainMovie: MetaPreview = { id: 'm1', type: 'movie', name: 'Plain Movie' };
    const trendingSeries: MetaPreview = { id: 's1', type: 'series', name: 'Trending Series' };

    const rows = [
      {
        id: 'addon_popular_featured_movie_library',
        title: 'Library',
        type: 'movie',
        catalogId: 'library',
        items: [plainMovie],
      },
      {
        id: 'addon.test_series_trending',
        title: 'Trending Series',
        type: 'series',
        catalogId: 'trending',
        items: [trendingSeries],
      },
    ];

    expect(pickFeaturedItem(rows)).toEqual({
      row: rows[1],
      item: trendingSeries,
    });
  });
});
