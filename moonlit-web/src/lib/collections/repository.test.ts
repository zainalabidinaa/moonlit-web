import { beforeEach, describe, expect, it, vi } from 'vitest';

import { fetchLiveOrganizer, loadCollections, ORGANIZER_FUNCTION_URL } from './repository';
import { supabaseAnonKey } from '@/lib/supabase';
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

describe('fetchLiveOrganizer', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('sends the Supabase anon key headers the edge function requires, not an unauthenticated request', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify([]), { status: 200 }),
    );

    await fetchLiveOrganizer();

    expect(fetchSpy).toHaveBeenCalledWith(ORGANIZER_FUNCTION_URL, {
      headers: {
        apikey: supabaseAnonKey,
        Authorization: `Bearer ${supabaseAnonKey}`,
      },
    });
  });

  it('returns null on the 401 an unauthenticated request would get, rather than throwing', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ code: 'UNAUTHORIZED_NO_AUTH_HEADER' }), { status: 401 }),
    );

    expect(await fetchLiveOrganizer()).toBeNull();
  });
});
