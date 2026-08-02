import { describe, expect, it, vi } from 'vitest';

import { buildCollectionRows } from './builder';
import { fetchCatalog } from './fetcher';
import type { AddonManifest, CollectionDisplayPreferences, MetaPreview, OrganizedCollections } from './types';

vi.mock('./fetcher', async () => {
  const actual = await vi.importActual<typeof import('./fetcher')>('./fetcher');
  return { ...actual, fetchCatalog: vi.fn() };
});

const prefs: CollectionDisplayPreferences = {
  disabledCollectionIds: new Set(),
  expandedCollectionIds: new Set(),
  hiddenFolderIds: new Set(),
};

const emptyOrganized: OrganizedCollections = {
  collections: [],
  folders: [],
  folderCatalogs: [],
  folderSources: [],
};

function addonWithCatalogs(catalogs: AddonManifest['catalogs']): AddonManifest {
  return {
    id: 'com.aiostreams.viren070.4a17bbef-911',
    name: 'AIOStreams',
    version: '1.0.0',
    transportUrl: 'https://aiostreams.example.com',
    resources: ['catalog'],
    catalogs,
  };
}

describe('buildCollectionRows', () => {
  it('deduplicates supplementary addon rows with the same generated row id', async () => {
    const rows = await buildCollectionRows({
      organized: emptyOrganized,
      prefs,
      addons: [
        addonWithCatalogs([
          { type: 'other', id: '0c9791b.peerflix-torbox', name: 'Peerflix TorBox' },
          { type: 'other', id: '0c9791b.peerflix-torbox', name: 'Peerflix TorBox Duplicate' },
        ]),
      ],
    });

    expect(rows.map(row => row.id)).toEqual([
      'com.aiostreams.viren070.4a17bbef-911-other-0c9791b.peerflix-torbox',
    ]);
  });

  it('keeps supplementary addon rows with the same catalog id but different media types', async () => {
    const rows = await buildCollectionRows({
      organized: emptyOrganized,
      prefs,
      addons: [
        addonWithCatalogs([
          { type: 'movie', id: 'popular', name: 'Popular Movies' },
          { type: 'series', id: 'popular', name: 'Popular Series' },
        ]),
      ],
    });

    expect(rows.map(row => row.id)).toEqual([
      'com.aiostreams.viren070.4a17bbef-911-movie-popular',
      'com.aiostreams.viren070.4a17bbef-911-series-popular',
    ]);
  });

  it('fetches a second page for a folder catalog row and merges it in, matching native\'s deeper Home rows', async () => {
    const page = (offset: number, n: number): MetaPreview[] => Array.from({ length: n }, (_, i) => ({
      id: `tt${offset + i}`, type: 'movie', name: `Item ${offset + i}`,
    }));
    const mockFetchCatalog = vi.mocked(fetchCatalog);
    mockFetchCatalog.mockImplementation(async ({ extras }) =>
      extras?.skip === '100' ? page(100, 30) : page(0, 100));

    const organized: OrganizedCollections = {
      collections: [{ id: 'c1', name: 'Popular', sortOrder: 0 } as OrganizedCollections['collections'][number]],
      folders: [{ id: 'f1', collectionId: 'c1', name: 'Popular Movies', sortOrder: 0 } as OrganizedCollections['folders'][number]],
      folderCatalogs: [{ folderId: 'f1', catalogId: 'popular', mediaType: 'movie' } as OrganizedCollections['folderCatalogs'][number]],
      folderSources: [],
    };
    const addons = [addonWithCatalogs([{ type: 'movie', id: 'popular', name: 'Popular Movies' }])];

    const rows = await buildCollectionRows({ organized, prefs, addons });

    expect(mockFetchCatalog).toHaveBeenCalledTimes(2);
    expect(mockFetchCatalog).toHaveBeenCalledWith(expect.objectContaining({ extras: undefined }));
    expect(mockFetchCatalog).toHaveBeenCalledWith(expect.objectContaining({ extras: { skip: '100' } }));

    const row = rows.find(r => r.id === 'folder-f1')!;
    expect(row.items).toHaveLength(130);
    // Second page came back short (30 < 100), so there's nothing more to fetch.
    expect(row.hasMore).toBe(false);
  });
});
