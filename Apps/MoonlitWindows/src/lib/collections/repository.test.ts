import { beforeEach, describe, expect, it, vi } from 'vitest';

import { loadCollections } from './repository';
import type { AddonManifest } from './types';

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

describe('loadCollections fallback rows', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it('deduplicates fallback addon rows with the same generated row id', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 404 }));

    const rows = await loadCollections([
      addonWithCatalogs([
        { type: 'other', id: '0c9791b.peerflix-torbox', name: 'Peerflix TorBox' },
        { type: 'other', id: '0c9791b.peerflix-torbox', name: 'Peerflix TorBox Duplicate' },
      ]),
    ]);

    expect(rows.map(row => row.id)).toEqual([
      'com.aiostreams.viren070.4a17bbef-911-other-0c9791b.peerflix-torbox',
    ]);
  });
});
