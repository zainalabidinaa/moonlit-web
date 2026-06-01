import React from 'react';
import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';

import { FeaturedHomeItem, HomeCatalogRow, MetaDetail, MetaPreview } from '@/lib/types';
import { HomeHero } from './HomeHero';

vi.mock('@tanstack/react-router', () => ({
  Link: ({ children, to, ...props }: { children: React.ReactNode; to?: string }) => (
    <a href={to || '#'} {...props}>{children}</a>
  ),
}));

const mockRow: HomeCatalogRow = {
  id: 'test_movie_trending',
  title: 'Trending Movies',
  type: 'movie',
  catalogId: 'trending',
  items: [],
};

const mockItem: MetaPreview = {
  id: 'tt000',
  type: 'movie',
  name: 'Test Movie Title',
  poster: 'https://example.com/poster.jpg',
  description: 'A short item description.',
  releaseInfo: '2024',
  imdbRating: '8.4',
  genres: ['Action', 'Drama'],
};

const mockMeta: MetaDetail = {
  id: 'tt000',
  type: 'movie',
  name: 'Test Movie Full Name',
  background: 'https://example.com/background.jpg',
  description: 'A longer meta description with more detail.',
  releaseInfo: '2024',
  imdbRating: '8.4',
  runtime: '2h 30m',
  genres: ['Action', 'Drama'],
};

const featured: FeaturedHomeItem = { row: mockRow, item: mockItem };

function renderHero(
  featuredItems: FeaturedHomeItem[],
  metas: Record<string, MetaDetail | null>,
  activeIndex = 0,
) {
  const onIndexChange = vi.fn();
  return render(
    <HomeHero
      featuredItems={featuredItems}
      activeIndex={activeIndex}
      metas={metas}
      onIndexChange={onIndexChange}
    />,
  );
}

describe('HomeHero', () => {
  it('renders hero copy text (title, metadata line, description)', () => {
    renderHero([featured], { tt000: mockMeta });

    expect(screen.getByText('Test Movie Full Name')).toBeInTheDocument();
    expect(screen.getByText(/Action · Drama/)).toBeInTheDocument();
    expect(screen.getByText('A longer meta description with more detail.')).toBeInTheDocument();
    expect(screen.getByText('Watch Now')).toBeInTheDocument();
  });

  it('uses a background image when meta.background is available', () => {
    const { container } = renderHero([featured], { tt000: mockMeta });

    const img = container.querySelector('img');
    expect(img).not.toBeNull();
    expect(img).toHaveAttribute('src', 'https://example.com/background.jpg');
  });

  it('falls back to banner when background is unavailable but banner is present', () => {
    const metaNoBg: MetaDetail = { ...mockMeta, background: undefined };
    const itemWithBanner: MetaPreview = {
      ...mockItem,
      banner: 'https://example.com/banner.jpg',
    };

    const { container } = renderHero(
      [{ row: mockRow, item: itemWithBanner }],
      { tt000: metaNoBg },
    );

    const img = container.querySelector('img');
    expect(img).not.toBeNull();
    expect(img).toHaveAttribute('src', 'https://example.com/banner.jpg');
  });

  it('falls back to poster when background and banner are unavailable', () => {
    const metaNoBg: MetaDetail = { ...mockMeta, background: undefined };
    const realItemNoBgNoBanner: MetaPreview = {
      ...mockItem,
      poster: 'https://example.com/poster.jpg',
    };

    const { container } = renderHero(
      [{ row: mockRow, item: realItemNoBgNoBanner }],
      { tt000: metaNoBg },
    );

    const img = container.querySelector('img');
    expect(img).not.toBeNull();
    expect(img).toHaveAttribute('src', 'https://example.com/poster.jpg');
  });

  it('renders without an image tag when no background, banner, or poster is available', () => {
    const itemNoImages: MetaPreview = { id: 'tt001', type: 'movie', name: 'No Image Item' };

    const { container } = renderHero(
      [{ row: mockRow, item: itemNoImages }],
      { tt001: null },
    );

    expect(container.querySelector('img')).toBeNull();
    expect(screen.getByText('No Image Item')).toBeInTheDocument();
  });

  it('gracefully handles missing MetaDetail by using item fields', () => {
    renderHero([featured], { tt000: null });

    expect(screen.getByText('Test Movie Title')).toBeInTheDocument();
    expect(screen.getByText('A short item description.')).toBeInTheDocument();
  });

  it('renders the row title as the category label', () => {
    renderHero([featured], { tt000: mockMeta });

    expect(screen.getByText('Trending Movies')).toBeInTheDocument();
  });

  it('returns null when featuredItems is empty', () => {
    const { container } = renderHero([], {});
    expect(container.firstChild).toBeNull();
  });
});
