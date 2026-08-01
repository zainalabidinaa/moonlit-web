import React from 'react';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import HomePage from './home';

const { fetchManifest, fetchMeta, getSystemAddon, getWatchProgress } = vi.hoisted(() => ({
  fetchManifest: vi.fn(),
  fetchMeta: vi.fn(),
  getSystemAddon: vi.fn(),
  getWatchProgress: vi.fn(),
}));

vi.mock('@/app/AuthProvider', () => ({
  useAuth: () => ({
    currentProfile: { id: 'profile-1' },
    addons: [{
      id: 'addon-1',
      name: 'Metadata addon',
      version: '1.0.0',
      transportUrl: 'https://addon.example.com',
      resources: ['meta'],
    }],
  }),
}));
vi.mock('@/app/PlayerProvider', () => ({ usePlayer: () => ({ open: vi.fn() }) }));
vi.mock('@/components/FusionBackground', () => ({ FusionBackground: () => null }));
vi.mock('@/lib/design/artwork-color', () => ({ useTileHalo: () => null }));
vi.mock('@/lib/services/api', () => ({ getSystemAddon, getWatchProgress }));
vi.mock('@/lib/stremio', () => ({ fetchManifest, fetchMeta }));
vi.mock('./catalog-data', () => ({
  useCatalogRowsData: () => ({
    data: [{
      id: 'popular',
      title: 'Popular Movies',
      page: 0,
      hasMore: false,
      items: [{ id: 'tt-home', type: 'movie', name: 'Home Feature', poster: 'poster.jpg' }],
    }],
  }),
  useArtworkPreferences: () => ({
    posterScale: 1,
    posterRadius: 12,
    artworkHaloEnabled: true,
    hoverPreviewEnabled: true,
    hoverPreviewDelaySeconds: 0.7,
  }),
}));
vi.mock('@tanstack/react-router', () => ({
  Link: ({ children, to, params, ...props }: {
    children: React.ReactNode;
    to?: string;
    params?: Record<string, string>;
  }) => (
    <a href={to?.replace('$type', params?.type ?? '').replace('$id', params?.id ?? '') || '#'} {...props}>
      {children}
    </a>
  ),
}));

describe('Home featured enrichment integration', () => {
  beforeEach(() => {
    getWatchProgress.mockResolvedValue([]);
    getSystemAddon.mockResolvedValue({ manifest_url: 'https://addon.example.com/manifest.json' });
    fetchManifest.mockResolvedValue({
      id: 'addon-1',
      name: 'Metadata addon',
      version: '1.0.0',
      transportUrl: 'https://addon.example.com',
      resources: ['meta'],
    });
    fetchMeta.mockResolvedValue({
      id: 'tt-home',
      type: 'movie',
      name: 'Home Feature',
      logo: 'home-logo.png',
      background: 'home-background.jpg',
      awards: ['Winner · Best Feature'],
    });
    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      json: async () => ({ movie_results: [] }),
    })));
  });

  it('renders awards delivered by the production metadata enrichment path', async () => {
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queryClient}>
        <HomePage />
      </QueryClientProvider>,
    );

    expect(await screen.findByRole('img', { name: 'Home Feature' })).toHaveAttribute('src', 'home-logo.png');
    expect(await screen.findByText('Winner · Best Feature')).toBeInTheDocument();
  });
});
