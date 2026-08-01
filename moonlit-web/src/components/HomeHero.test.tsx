import React from 'react';
import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';

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
  awards: Record<string, string> = {},
) {
  const onIndexChange = vi.fn();
  return render(
    <HomeHero
      featuredItems={featuredItems}
      activeIndex={activeIndex}
      metas={metas}
      awards={awards}
      onIndexChange={onIndexChange}
    />,
  );
}

describe('HomeHero', () => {
  it('renders logo-first copy with rating and awards metadata', () => {
    renderHero([featured], { tt000: { ...mockMeta, logo: 'https://example.com/logo.png' } }, 0, {
      tt000: '2 wins · 7 nominations',
    });

    expect(screen.getByRole('img', { name: 'Test Movie Full Name' })).toHaveAttribute('src', 'https://example.com/logo.png');
    expect(screen.getAllByText('Action')).toHaveLength(2);
    expect(screen.getByText('Drama')).toBeInTheDocument();
    expect(screen.getByText(/8\.4/)).toBeInTheDocument();
    expect(screen.getByText('2 wins · 7 nominations')).toBeInTheDocument();
    expect(screen.getByText('A longer meta description with more detail.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Go to Movie' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /more info/i })).not.toBeInTheDocument();
  });

  it('uses a background image when meta.background is available', () => {
    const { container } = renderHero([featured], { tt000: mockMeta });

    const img = container.querySelector('img');
    expect(img).not.toBeNull();
    expect(img).toHaveAttribute('src', 'https://example.com/background.jpg');
  });

  it('uses addon-provided title logos before falling back to text', () => {
    renderHero(
      [{ row: mockRow, item: { ...mockItem, logo: 'https://example.com/addon-logo.png' } }],
      { tt000: null },
    );

    expect(screen.getByRole('img', { name: 'Test Movie Title' })).toHaveAttribute(
      'src',
      'https://example.com/addon-logo.png',
    );
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

  it('renders no background image when background and banner are unavailable (poster not used for hero)', () => {
    const metaNoBg: MetaDetail = { ...mockMeta, background: undefined };
    const realItemNoBgNoBanner: MetaPreview = {
      ...mockItem,
      poster: 'https://example.com/poster.jpg',
    };

    const { container } = renderHero(
      [{ row: mockRow, item: realItemNoBgNoBanner }],
      { tt000: metaNoBg },
    );

    expect(container.querySelector('img')).toBeNull();
    expect(screen.getByText(metaNoBg.name!)).toBeInTheDocument();
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

  it('prefers addon landscape art before metadata and TMDB backdrop fallbacks', () => {
    const { container } = renderHero(
      [{ row: mockRow, item: { ...mockItem, banner: 'https://example.com/addon-landscape.jpg' } }],
      { tt000: mockMeta },
    );

    expect(container.querySelector('img[fetchpriority="high"]')).toHaveAttribute(
      'src',
      'https://example.com/addon-landscape.jpg',
    );
  });

  it('exposes the Mac 560px desktop hero contract', () => {
    const { container } = renderHero([featured], { tt000: mockMeta });

    expect(container.firstElementChild).toHaveStyle({ '--hero-desktop-height': '560px' });
  });

  it('offers native carousel navigation and a visible pause control', () => {
    const second = { ...featured, item: { ...mockItem, id: 'tt002', name: 'Second title' } };
    const onIndexChange = vi.fn();
    const onPauseChange = vi.fn();
    render(
      <HomeHero
        featuredItems={[featured, second]}
        activeIndex={0}
        metas={{ tt000: mockMeta, tt002: null }}
        onIndexChange={onIndexChange}
        isPaused={false}
        onPauseChange={onPauseChange}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Next featured title' }));
    fireEvent.click(screen.getByRole('button', { name: 'Pause featured titles' }));

    expect(onIndexChange).toHaveBeenCalledWith(1);
    expect(onPauseChange).toHaveBeenCalledWith(true);
  });

  it('returns null when featuredItems is empty', () => {
    const { container } = renderHero([], {});
    expect(container.firstChild).toBeNull();
  });
});
