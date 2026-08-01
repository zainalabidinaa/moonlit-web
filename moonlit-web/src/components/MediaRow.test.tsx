import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import type { MetaPreview } from '@/lib/types';
import { MediaRow, type MediaRailVariant } from './MediaRow';

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

const item: MetaPreview = {
  id: 'tt-card',
  type: 'movie',
  name: 'Card Title',
  poster: 'https://example.com/poster.jpg',
  banner: 'https://example.com/banner.jpg',
  releaseInfo: '2026',
  imdbRating: '8.8',
  genres: ['Science Fiction'],
  quality: '4K',
  ageRating: '16+',
  previewVideo: 'https://example.com/preview.mp4',
};

describe('MediaRow parity variants', () => {
  it('applies the 154×231 baseline, artwork settings, halo, and optional badges', () => {
    render(
      <MediaRow
        title="Popular"
        items={[item]}
        artworkPreferences={{
          posterScale: 1.2,
          posterRadius: 18,
          artworkHaloEnabled: true,
          hoverPreviewEnabled: false,
          hoverPreviewDelaySeconds: 0.7,
        }}
        badges={{ trend: true, quality: true, genre: true, rating: true, age: true }}
      />,
    );

    const card = screen.getByRole('link', { name: /Card Title/ });
    expect(card).toHaveAttribute('data-media-card', 'poster');
    expect(card).toHaveStyle({
      '--media-card-width': '184.8px',
      '--media-card-height': '277.2px',
      '--media-card-radius': '18px',
    });
    expect(card).toHaveClass('artwork-halo');
    for (const badge of ['#1', '4K', 'Science Fiction', '★ 8.8', '16+']) {
      expect(screen.getByText(badge)).toBeInTheDocument();
    }
  });

  it.each<MediaRailVariant>(['standard', 'cinematic', 'banner', 'stack', 'carousel', 'top10', 'continue'])(
    'renders the %s rail as a labelled region',
    variant => {
      render(<MediaRow title={`${variant} rail`} items={[item]} variant={variant} />);

      expect(screen.getByRole('region', { name: `${variant} rail` })).toHaveAttribute(
        'data-rail-variant',
        variant,
      );
    },
  );

  it.each([
    ['standard', 'poster', '154px', '231px'],
    ['cinematic', 'landscape', '360px', '203px'],
    ['banner', 'landscape', '320px', '180px'],
    ['stack', 'landscape', '270px', '152px'],
    ['top10', 'poster', '154px', '231px'],
    ['continue', 'landscape', '320px', '180px'],
  ] as const)(
    'gives %s observable geometry distinct from the other rail compositions',
    (variant, shape, width, height) => {
      render(<MediaRow title={`${variant} geometry`} items={[item]} variant={variant} />);

      const card = screen.getByRole('link', { name: /Card Title/ });
      expect(card).toHaveAttribute('data-media-card', shape);
      expect(card).toHaveStyle({ '--media-card-width': width, '--media-card-height': height });
    },
  );

  it('uses a leading-card composition for carousel and visible depth layers for stack', () => {
    const second = { ...item, id: 'tt-card-two', name: 'Second Card' };
    const { rerender } = render(<MediaRow title="Carousel" items={[item, second]} variant="carousel" />);

    expect(screen.getByRole('link', { name: /Card Title/ })).toHaveStyle({ '--media-card-width': '420px' });
    expect(screen.getByRole('link', { name: /Second Card/ })).toHaveStyle({ '--media-card-width': '320px' });

    rerender(<MediaRow title="Stack" items={[item]} variant="stack" />);
    expect(screen.getAllByTestId('media-stack-depth-layer')).toHaveLength(2);
  });

  it('delays an enabled hover preview and keeps it user-triggered', async () => {
    vi.useFakeTimers();
    render(
      <MediaRow
        title="Preview rail"
        items={[item]}
        artworkPreferences={{
          posterScale: 1,
          posterRadius: 12,
          artworkHaloEnabled: true,
          hoverPreviewEnabled: true,
          hoverPreviewDelaySeconds: 0.2,
        }}
      />,
    );

    expect(screen.queryByLabelText('Preview Card Title')).not.toBeInTheDocument();
    fireEvent.mouseEnter(screen.getByRole('link', { name: /Card Title/ }));
    await act(async () => { await vi.advanceTimersByTimeAsync(200); });

    expect(screen.getByLabelText('Preview Card Title')).toHaveAttribute('autoplay');
    vi.useRealTimers();
  });
});
