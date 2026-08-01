import React from 'react';
import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

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

const detail = {
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
  seasons: [season],
  cast: [{ id: 'person-1', name: 'Lead Actor', photo: 'https://example.com/person.jpg' }],
  gallery: [{ id: 'gallery-1', url: 'https://example.com/gallery.jpg', caption: 'Production still' }],
  awards: ['2 wins · 7 nominations'],
  links: [{ name: 'Official site', category: 'official', url: 'https://example.com' }],
  moreLikeThis: [{ id: 'tt-related', type: 'series', name: 'Related Series', poster: 'related.jpg' }],
};

vi.mock('@tanstack/react-query', () => ({
  useQuery: () => ({
    data: {
      meta: detail,
      inLib: false,
      savedPosition: 0,
      trailers: [{ id: 'trailer-1', title: 'Official Trailer', youtubeId: 'youtube-1' }],
      initialSeason: season,
      recentEp: null,
      epProgress: {},
    },
    isLoading: false,
    isError: false,
  }),
  useQueryClient: () => ({ invalidateQueries: vi.fn() }),
}));

vi.mock('@tanstack/react-router', () => ({
  useParams: () => ({ type: 'series', id: 'tt-detail' }),
  useNavigate: () => vi.fn(),
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
  useAuth: () => ({ currentProfile: { id: 'profile-1' }, addons: [{ id: 'addon-1' }] }),
}));

vi.mock('@/app/PlayerProvider', () => ({ usePlayer: () => ({ open: vi.fn() }) }));
vi.mock('@/components/FusionBackground', () => ({ FusionBackground: () => null }));
vi.mock('@/lib/design/artwork-color', () => ({
  useAmbientColors: () => null,
  useTileHalo: () => null,
}));
vi.mock('@/lib/stremio', () => ({
  fetchMeta: vi.fn(),
  fetchStreamsFromAll: vi.fn(async () => []),
}));

import DetailPage from './browse';

describe('Detail destination parity', () => {
  it('uses the 780px hero and keeps the enrichment sections in the approved order', () => {
    const { container } = render(<DetailPage />);

    const hero = container.querySelector('[data-detail-hero]');
    expect(hero).toHaveStyle({ '--detail-hero-height': '780px' });
    expect(screen.getByRole('img', { name: 'Detail Series' })).toHaveAttribute('src', detail.logo);
    expect(screen.getByRole('button', { name: /play first episode/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add to watchlist' })).toBeInTheDocument();
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
});
