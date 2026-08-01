import React from 'react';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { CatalogRow } from '@/lib/collections/types';
import type { WatchProgressEntry } from '@/lib/types';
import { CatalogDestination } from './catalog-destination';

const { fetchMeta, getWatchProgress, openPlayer } = vi.hoisted(() => ({
  fetchMeta: vi.fn(),
  getWatchProgress: vi.fn(),
  openPlayer: vi.fn(),
}));

let catalogError = false;

const rows: CatalogRow[] = [
  {
    id: 'movies',
    title: 'Trending Movies',
    page: 0,
    hasMore: false,
    items: [
      {
        id: 'tt-feature',
        type: 'movie',
        name: 'Destination Feature',
        poster: 'https://example.com/feature-poster.jpg',
        description: 'The featured movie description.',
        genres: ['Science Fiction'],
        imdbRating: '8.6',
      },
      {
        id: 'tt-action',
        type: 'movie',
        name: 'Action Pick',
        poster: 'https://example.com/action.jpg',
        genres: ['Action'],
      },
    ],
  },
  {
    id: 'cinematic',
    title: 'Cinematic Showcase',
    viewMode: 'cinematic',
    page: 0,
    hasMore: false,
    items: [{ id: 'tt-cinematic', type: 'movie', name: 'Cinematic Pick', poster: 'cinematic.jpg' }],
  },
  {
    id: 'carousel',
    title: 'Carousel Spotlight',
    viewMode: 'carousel',
    page: 0,
    hasMore: false,
    items: [{ id: 'tt-carousel', type: 'movie', name: 'Carousel Pick', poster: 'carousel.jpg' }],
  },
  {
    id: 'series',
    title: 'Trending Series',
    page: 0,
    hasMore: false,
    items: [{ id: 'tt-series', type: 'series', name: 'Series Pick', poster: 'series.jpg' }],
  },
];

vi.mock('@/app/AuthProvider', () => ({
  useAuth: () => ({
    currentProfile: { id: 'profile-1' },
    addons: [{
      id: 'addon-1',
      name: 'Metadata addon',
      version: '1.0.0',
      transportUrl: 'https://addon.example.com',
      resources: ['meta', 'stream'],
    }],
  }),
}));

vi.mock('@/app/PlayerProvider', () => ({ usePlayer: () => ({ open: openPlayer }) }));
vi.mock('@/components/FusionBackground', () => ({ FusionBackground: () => null }));
vi.mock('@/lib/design/artwork-color', () => ({ useTileHalo: () => null }));
vi.mock('@/lib/services/api', () => ({ getWatchProgress }));
vi.mock('@/lib/stremio', () => ({ fetchMeta }));
vi.mock('./catalog-data', () => ({
  useCatalogRowsData: () => ({ data: rows, isLoading: false, isError: catalogError }),
  useArtworkPreferences: () => ({
    posterScale: 1,
    posterRadius: 14,
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

function renderDestination(mediaType: 'movie' | 'series', title: string) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <CatalogDestination mediaType={mediaType} title={title} />
    </QueryClientProvider>,
  );
}

function progress(overrides: Partial<WatchProgressEntry>): WatchProgressEntry {
  return {
    id: 'progress',
    profile_id: 'profile-1',
    media_id: 'tt-feature',
    media_type: 'movie',
    position_seconds: 600,
    duration_seconds: 3600,
    completed: false,
    updated_at: '2026-07-31T12:00:00Z',
    name: 'Destination Feature',
    poster: 'https://example.com/progress.jpg',
    ...overrides,
  };
}

describe('CatalogDestination', () => {
  beforeEach(() => {
    catalogError = false;
    openPlayer.mockReset();
    getWatchProgress.mockResolvedValue([progress({})]);
    fetchMeta.mockImplementation(async (_baseUrl: string, _type: string, id: string) => ({
      id,
      type: _type,
      name: id === 'tt-feature' ? 'Destination Feature' : id,
      logo: id === 'tt-feature' ? 'https://example.com/feature-logo.png' : undefined,
      awards: id === 'tt-feature' ? ['2 wins · 7 nominations'] : undefined,
    }));
    vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request) => {
      const url = String(input);
      if (url.includes('/find/tt-feature')) {
        return { ok: true, json: async () => ({ movie_results: [{ id: 77, backdrop_path: '/community.jpg' }] }) };
      }
      return { ok: true, json: async () => ({ movie_results: [], tv_results: [] }) };
    }));
  });

  it('enriches a poster-only catalog hero with shared metadata, TMDB artwork, logo, and awards', async () => {
    renderDestination('movie', 'Movies');

    expect(await screen.findByRole('img', { name: 'Destination Feature' })).toHaveAttribute(
      'src',
      'https://example.com/feature-logo.png',
    );
    expect(document.querySelector('img[fetchpriority="high"]')).toHaveAttribute(
      'src',
      'https://image.tmdb.org/t/p/w1280/community.jpg',
    );
    expect(screen.getByText('2 wins · 7 nominations')).toBeInTheDocument();
  });

  it('keeps the Home rhythm and selects cinematic and carousel as distinct rail variants', async () => {
    renderDestination('movie', 'Movies');

    expect(await screen.findByRole('group', { name: 'Filter Movies by genre' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'All' })).toHaveAttribute('aria-pressed', 'true');
    expect(await screen.findByRole('region', { name: 'Continue Watching' })).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Trending Movies' })).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Cinematic Showcase' })).toHaveAttribute('data-rail-variant', 'cinematic');
    expect(screen.getByRole('region', { name: 'Carousel Spotlight' })).toHaveAttribute('data-rail-variant', 'carousel');

    fireEvent.click(screen.getByRole('button', { name: 'Science Fiction' }));
    expect(screen.queryByText('Action Pick')).not.toBeInTheDocument();
  });

  it('preserves hero artwork and loaded rails when a refresh partially fails', async () => {
    catalogError = true;
    renderDestination('movie', 'Movies');

    expect(await screen.findByRole('alert')).toHaveTextContent('Some movie rows could not be refreshed');
    expect(screen.getByRole('region', { name: 'Trending Movies' })).toBeInTheDocument();
  });

  it('deduplicates Series Continue Watching to the newest episode and resumes that playback identity', async () => {
    getWatchProgress.mockResolvedValue([
      progress({
        id: 'episode-old',
        media_id: 'tt-series:1:1',
        media_type: 'series',
        name: 'Series Pick',
        position_seconds: 300,
        updated_at: '2026-07-31T10:00:00Z',
      }),
      progress({
        id: 'episode-new',
        media_id: 'tt-series:1:2',
        media_type: 'series',
        name: 'Series Pick',
        position_seconds: 900,
        updated_at: '2026-07-31T12:00:00Z',
      }),
    ]);

    renderDestination('series', 'Series');

    const rail = await screen.findByRole('region', { name: 'Continue Watching' });
    expect(within(rail).getAllByText('Series Pick')).toHaveLength(1);
    expect(within(rail).getByText('S1 E2')).toBeInTheDocument();
    expect(within(rail).queryByText('S1 E1')).not.toBeInTheDocument();

    fireEvent.click(within(rail).getByRole('button', { name: /Series Pick/ }));
    expect(openPlayer).toHaveBeenCalledWith(expect.objectContaining({ id: 'tt-series:1:2' }));
  });
});
