import React from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const api = vi.hoisted(() => ({
  getUserWatchlist: vi.fn(),
  removeUserWatchlistItem: vi.fn(),
  getWatchProgress: vi.fn(),
  getLibrary: vi.fn(),
  toggleLibrary: vi.fn(),
}));

vi.mock('@/app/AuthProvider', () => ({
  useAuth: () => ({ currentProfile: { id: 'profile-1' } }),
}));

vi.mock('@/lib/services/api', () => api);

vi.mock('@/lib/liked', () => ({
  getLikedItems: () => [],
  removeLiked: vi.fn(),
  refreshUpcoming: vi.fn(async () => ({})),
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
  useNavigate: () => vi.fn(),
}));

import LibraryPage from './library';

const item = {
  id: 'item-1',
  list_id: 'list-1',
  media_id: 'tt1',
  media_type: 'movie',
  name: 'Saved Movie',
  poster: 'poster.jpg',
  added_at: '2026-07-31T11:00:00Z',
};

function renderPage() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <LibraryPage />
    </QueryClientProvider>,
  );
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

describe('Watchlist destination', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.getWatchProgress.mockResolvedValue([]);
    api.getLibrary.mockResolvedValue([]);
    api.toggleLibrary.mockResolvedValue(undefined);
  });

  it('announces loading and explains the empty state', async () => {
    const pending = deferred<never>();
    api.getUserWatchlist.mockReturnValue(pending.promise);

    const { unmount } = renderPage();
    expect(screen.getByRole('status')).toHaveTextContent('Loading your watchlist');
    unmount();

    api.getUserWatchlist.mockResolvedValue({ id: 'list-1', name: 'Watchlist', items: [] });
    renderPage();
    expect(await screen.findByRole('heading', { name: 'Your watchlist is empty' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Browse movies' })).toHaveAttribute('href', '/movies');
  });

  it('shows a recoverable error state', async () => {
    api.getUserWatchlist.mockRejectedValue(new Error('offline'));
    renderPage();

    expect(await screen.findByRole('alert')).toHaveTextContent('Your watchlist could not be loaded');
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument();
  });

  it('removes a title optimistically and restores it when the mutation fails', async () => {
    api.getUserWatchlist.mockResolvedValue({ id: 'list-1', name: 'Watchlist', items: [item] });
    const removal = deferred<void>();
    api.removeUserWatchlistItem.mockReturnValue(removal.promise);
    renderPage();

    expect(await screen.findByText('Saved Movie')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Remove Saved Movie from watchlist' }));
    expect(screen.queryByText('Saved Movie')).not.toBeInTheDocument();

    removal.reject(new Error('offline'));
    expect(await screen.findByText('Saved Movie')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('Saved Movie was not removed'));
  });
});
