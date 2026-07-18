import { describe, expect, it } from 'vitest';

import { buildCollectionRows } from './builder';
import type { AddonManifest, CollectionDisplayPreferences, OrganizedCollections } from './types';

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
});
