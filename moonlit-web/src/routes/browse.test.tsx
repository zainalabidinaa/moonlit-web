import React from 'react';
import { render, screen, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { MetaDetail } from '@/lib/types';
import DetailPage from './browse';

const {
  fetchMeta,
  fetchStreamsFromAll,
  getWatchProgress,
  isInUserWatchlist,
  openPlayer,
  toggleUserWatchlistItem,
} = vi.hoisted(() => ({
  fetchMeta: vi.fn(),
  fetchStreamsFromAll: vi.fn(),
  getWatchProgress: vi.fn(),
  isInUserWatchlist: vi.fn(),
  openPlayer: vi.fn(),
  toggleUserWatchlistItem: vi.fn(),
}));

let routeParams = { type: 'series', id: 'tt-detail' };

const season = {
  id: 'season-1',
  number: 1,
  episodes: [{
    id: 'tt-detail:1:1',
    title: 'First Light',
    season: 1,
    episode: 1,
    thumbnail: 'https://example.com/episode.jpg',
    overview: 'The first episode.',
  }],
};

const detail: MetaDetail = {
  id: 'tt-detail',
  type: 'series',
  name: 'Detail Series',
  logo: 'https://example.com/logo.png',
  background: 'https://example.com/backdrop.jpg',
  description: 'A detailed overview.',
  releaseInfo: '2026',
  runtime: '52m',
  imdbRating: '8.9',
  genres: ['Drama'],
  tmdbId: '42',
  seasons: [season],
  trailers: [{ id: 'trailer-1', title: 'Official Trailer', youtubeId: 'youtube-1' }],
  cast: [{ id: 'person-1', name: 'Lead Actor', photo: 'https://example.com/person.jpg' }],
  gallery: [{ id: 'gallery-1', url: 'https://example.com/gallery.jpg', caption: 'Production still' }],
  awards: ['2 wins · 7 nominations'],
  links: [
    { name: 'Official site', category: 'official', url: 'https://example.com' },
    { name: 'Download file', category: 'download', url: 'https://example.com/detail.mp4' },
  ],
  moreLikeThis: [{ id: 'tt-related', type: 'series', name: 'Related Series', poster: 'related.jpg' }],
};

vi.mock('@tanstack/react-router', () => ({
  useParams: () => routeParams,
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

vi.mock('@/app/AuthProvider', () => ({
  useAuth: () => ({
    currentProfile: { id: 'profile-1' },
    addons: [{
      id: 'addon-1',
      name: 'Metadata and streams',
      version: '1.0.0',
      transportUrl: 'https://addon.example.com',
      resources: ['meta', 'stream'],
    }],
  }),
}));
vi.mock('@/app/PlayerProvider', () => ({ usePlayer: () => ({ open: openPlayer }) }));
vi.mock('@/components/FusionBackground', () => ({ FusionBackground: () => null }));
vi.mock('@/lib/design/artwork-color', () => ({
  useAmbientColors: () => null,
  useTileHalo: () => null,
}));
vi.mock('@/lib/services/api', () => ({
  getWatchProgress,
  isInUserWatchlist,
  toggleUserWatchlistItem,
}));
vi.mock('@/lib/stremio', () => ({ fetchMeta, fetchStreamsFromAll }));
vi.mock('./catalog-data', () => ({
  useArtworkPreferences: () => ({
    posterScale: 1,
    posterRadius: 14,
    artworkHaloEnabled: true,
    hoverPreviewEnabled: true,
    hoverPreviewDelaySeconds: 0.7,
  }),
}));

function renderDetail() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <DetailPage />
    </QueryClientProvider>,
  );
}

function tmdbResponse(url: string) {
  if (url.includes('/tv/42')) {
    return {
      ok: true,
      json: async () => ({ credits: { cast: [] }, similar: { results: [] }, images: { backdrops: [] } }),
    };
  }
  if (url.includes('/tv/777')) {
    return {
      ok: true,
      json: async () => ({
        id: 777,
        name: 'TMDB Resolved Series',
        overview: 'Resolved from a namespaced recommendation.',
        backdrop_path: '/tmdb-detail.jpg',
        poster_path: '/tmdb-poster.jpg',
        credits: { cast: [] },
        similar: { results: [] },
        images: { backdrops: [] },
      }),
    };
  }
  return { ok: true, json: async () => ({ streams: [] }) };
}

describe('Detail destination parity', () => {
  beforeEach(() => {
    routeParams = { type: 'series', id: 'tt-detail' };
    fetchMeta.mockReset();
    fetchMeta.mockResolvedValue(detail);
    fetchStreamsFromAll.mockReset();
    fetchStreamsFromAll.mockResolvedValue([]);
    isInUserWatchlist.mockReset();
    isInUserWatchlist.mockResolvedValue(false);
    getWatchProgress.mockReset();
    getWatchProgress.mockResolvedValue([]);
    toggleUserWatchlistItem.mockReset();
    openPlayer.mockReset();
    vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request) => tmdbResponse(String(input))));
  });

  it('uses the 780px hero, approved action set, and enrichment section order', async () => {
    const { container } = renderDetail();

    expect(await screen.findByRole('img', { name: 'Detail Series' })).toHaveAttribute('src', detail.logo);
    const hero = container.querySelector('[data-detail-hero]');
    expect(hero).toHaveStyle({ '--detail-hero-height': '780px' });
    expect(screen.getByRole('button', { name: /play first episode/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add to watchlist' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Download' })).toHaveAttribute('href', 'https://example.com/detail.mp4');
    expect(screen.getByRole('link', { name: 'Watch trailer' })).toHaveAttribute(
      'href',
      'https://www.youtube.com/watch?v=youtube-1',
    );
    expect(screen.getByRole('heading', { name: 'Overview' })).toBeInTheDocument();

    const orderedHeadings = [
      'Trailers & Clips',
      'Episodes',
      'Cast & Creators',
      'Gallery',
      'Awards',
      'Links',
      'Recommendations',
    ].map(name => screen.getByRole('heading', { name }));

    for (let index = 1; index < orderedHeadings.length; index += 1) {
      expect(orderedHeadings[index - 1].compareDocumentPosition(orderedHeadings[index]))
        .toBe(Node.DOCUMENT_POSITION_FOLLOWING);
    }
  });

  it('keeps fetched metadata artwork visible when watchlist or progress requests fail', async () => {
    isInUserWatchlist.mockRejectedValue(new Error('watchlist unavailable'));
    getWatchProgress.mockRejectedValue(new Error('progress unavailable'));

    renderDetail();

    expect(await screen.findByRole('img', { name: 'Detail Series' })).toHaveAttribute('src', detail.logo);
    expect(screen.getByRole('region', { name: 'Detail Series details' })).toBeInTheDocument();
  });

  it('namespaces TMDB fallback recommendations so their links remain resolvable', async () => {
    fetchMeta.mockResolvedValue({ ...detail, moreLikeThis: [] });
    vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request) => {
      const url = String(input);
      if (url.includes('/tv/42')) {
        return {
          ok: true,
          json: async () => ({
            credits: { cast: [] },
            images: { backdrops: [] },
            similar: { results: [{ id: 777, name: 'TMDB Recommendation', poster_path: '/rec.jpg', first_air_date: '2026-02-01' }] },
          }),
        };
      }
      return tmdbResponse(url);
    }));

    renderDetail();

    const recommendations = await screen.findByRole('region', { name: 'Recommendations' });
    expect(within(recommendations).getByRole('link', { name: /TMDB Recommendation/ })).toHaveAttribute(
      'href',
      '/browse/series/tmdb:777',
    );
  });

  it('resolves a tmdb namespaced recommendation into usable detail metadata', async () => {
    routeParams = { type: 'series', id: 'tmdb:777' };
    fetchMeta.mockResolvedValue(null);

    renderDetail();

    expect(await screen.findByRole('heading', { name: 'TMDB Resolved Series' })).toBeInTheDocument();
    expect(document.querySelector('[data-detail-hero] img[src="https://image.tmdb.org/t/p/original/tmdb-detail.jpg"]'))
      .toBeInTheDocument();
  });
});
