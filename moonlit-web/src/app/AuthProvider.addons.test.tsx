import { render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AuthProvider, useAuth } from './AuthProvider';
import type { AddonManifest, MoonlitProfile } from '@/lib/types';

const mocks = vi.hoisted(() => ({
  session: null as { user: { id: string } } | null,
  profiles: [] as MoonlitProfile[],
  installedUrls: [] as string[],
  sharedUrls: [] as string[],
  manifests: new Map<string, AddonManifest>(),
}));

vi.mock('@/lib/supabase', () => ({
  DEFAULT_ADDONS: ['https://default.example/manifest.json'],
  supabase: {
    auth: {
      getSession: vi.fn(async () => ({ data: { session: mocks.session } })),
      onAuthStateChange: vi.fn(() => ({ subscription: { unsubscribe: vi.fn() } })),
      signOut: vi.fn(async () => undefined),
    },
    from: vi.fn(() => ({ select: vi.fn().mockReturnThis(), eq: vi.fn().mockReturnThis(), maybeSingle: vi.fn(async () => ({ data: null, error: null })) })),
  },
}));

vi.mock('@/lib/services/api', () => ({
  getProfiles: vi.fn(async () => mocks.profiles),
  getInstalledAddons: vi.fn(async () => mocks.installedUrls),
  getSharedAddons: vi.fn(async () => mocks.sharedUrls),
}));

vi.mock('@/lib/stremio', async () => {
  const actual = await vi.importActual<typeof import('@/lib/stremio')>('@/lib/stremio');
  return {
    ...actual,
    fetchManifest: vi.fn(async (url: string) => {
      const manifest = mocks.manifests.get(url);
      if (!manifest) throw new Error(`no manifest stubbed for ${url}`);
      return manifest;
    }),
  };
});

function manifest(id: string, resources: AddonManifest['resources']): AddonManifest {
  return { id, name: id, version: '1.0.0', resources, transportUrl: `https://${id}.example` };
}

function AddonProbe() {
  const { addons, currentProfile } = useAuth();
  if (!currentProfile) return <span data-testid="scope">none</span>;
  return (
    <ul data-testid="addons">
      {addons.map(a => (
        <li key={a.id} data-testid={`addon-${a.id}`}>
          {a.id}:{(a.resources ?? []).map(r => typeof r === 'string' ? r : r.name).join(',')}
        </li>
      ))}
    </ul>
  );
}

describe('AuthProvider shared-addon inheritance', () => {
  beforeEach(() => {
    mocks.session = { user: { id: 'user-a' } };
    mocks.installedUrls = [];
    mocks.sharedUrls = [];
    mocks.manifests = new Map([
      ['https://default.example/manifest.json', manifest('default', ['catalog', 'meta'])],
    ]);
  });

  it('does not fetch shared addons for an admin profile', async () => {
    mocks.profiles = [{ id: 'admin-1', user_id: 'user-a', name: 'Admin', profile_index: 0, role: 'admin', isAdmin: true }];
    mocks.sharedUrls = ['https://shared.example/manifest.json'];
    mocks.manifests.set('https://shared.example/manifest.json', manifest('shared', ['catalog', 'stream']));

    render(<AuthProvider><AddonProbe /></AuthProvider>);

    await waitFor(() => expect(screen.getByTestId('addon-default')).toBeInTheDocument());
    expect(screen.queryByTestId('addon-shared')).not.toBeInTheDocument();
  });

  it('inherits an admin-shared addon for a non-admin profile with its stream resource stripped', async () => {
    mocks.profiles = [{ id: 'user-1', user_id: 'user-a', name: 'User', profile_index: 0, role: 'user', isAdmin: false }];
    mocks.sharedUrls = ['https://shared.example/manifest.json'];
    mocks.manifests.set('https://shared.example/manifest.json', manifest('shared', ['catalog', 'stream', 'meta']));

    render(<AuthProvider><AddonProbe /></AuthProvider>);

    await waitFor(() => expect(screen.getByTestId('addon-shared')).toBeInTheDocument());
    expect(screen.getByTestId('addon-shared')).toHaveTextContent('shared:catalog,meta');
    expect(screen.getByTestId('addon-shared')).not.toHaveTextContent('stream');
  });

  it('does not duplicate a shared addon already present via defaults or the user\'s own list', async () => {
    mocks.profiles = [{ id: 'user-1', user_id: 'user-a', name: 'User', profile_index: 0, role: 'user', isAdmin: false }];
    mocks.sharedUrls = ['https://default.example/manifest.json'];

    render(<AuthProvider><AddonProbe /></AuthProvider>);

    await waitFor(() => expect(screen.getByTestId('addons')).toBeInTheDocument());
    expect(screen.getAllByTestId('addon-default')).toHaveLength(1);
  });
});
