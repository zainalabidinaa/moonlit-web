import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { CatalogRow } from '@/lib/collections/types';
import { CatalogDestination } from './catalog-destination';

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
        banner: 'https://example.com/feature.jpg',
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
    id: 'series',
    title: 'Trending Series',
    page: 0,
    hasMore: false,
    items: [{ id: 'tt-series', type: 'series', name: 'Series Pick' }],
  },
];

vi.mock('@/app/AuthProvider', () => ({
  useAuth: () => ({
    currentProfile: { id: 'profile-1' },
    addons: [{ id: 'addon-1' }],
  }),
}));

vi.mock('@tanstack/react-query', () => ({
  useQuery: ({ queryKey }: { queryKey: unknown[] }) => {
    if (queryKey[0] === 'watch-progress') {
      return {
        data: [{
          id: 'progress-1',
          profile_id: 'profile-1',
          media_id: 'tt-feature',
          media_type: 'movie',
          position_seconds: 600,
          duration_seconds: 3600,
          completed: false,
          updated_at: '2026-07-31T12:00:00Z',
          name: 'Destination Feature',
          poster: 'https://example.com/progress.jpg',
        }],
        isLoading: false,
        isError: false,
      };
    }
    return { data: rows, isLoading: false, isError: catalogError };
  },
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

describe('CatalogDestination', () => {
  beforeEach(() => { catalogError = false; });

  it('keeps the Home rhythm with hero, genre filters, continue watching, and catalog rails', () => {
    render(<CatalogDestination mediaType="movie" title="Movies" />);

    expect(screen.getByRole('heading', { level: 1, name: 'Destination Feature' })).toBeInTheDocument();
    expect(screen.getByRole('group', { name: 'Filter Movies by genre' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'All' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('region', { name: 'Continue Watching' })).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Trending Movies' })).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Science Fiction' }));
    expect(screen.getByRole('heading', { level: 1, name: 'Destination Feature' })).toBeInTheDocument();
    expect(screen.queryByText('Action Pick')).not.toBeInTheDocument();
  });

  it('preserves hero artwork and loaded rails when a refresh partially fails', () => {
    catalogError = true;
    const { container } = render(<CatalogDestination mediaType="movie" title="Movies" />);

    expect(screen.getByRole('alert')).toHaveTextContent('Some movie rows could not be refreshed');
    expect(container.querySelector('img[fetchpriority="high"]')).toHaveAttribute('src', 'https://example.com/feature.jpg');
    expect(screen.getByRole('region', { name: 'Trending Movies' })).toBeInTheDocument();
  });
});
