import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/app/AuthProvider', () => ({
  AuthProvider: ({ children }: { children: unknown }) => children,
  useAuth: () => ({ user: null, guestMode: true, currentProfile: null, isLoading: false }),
}));
vi.mock('@/app/PlayerProvider', () => ({
  PlayerProvider: ({ children }: { children: unknown }) => children,
}));
vi.mock('@/components/PlayerOverlay', () => ({ PlayerOverlay: () => null }));

import { router } from './router';

function matchedRouteIds(path: string): string[] {
  return router.matchRoutes(path).map(match => match.routeId);
}

describe('application routes', () => {
  beforeEach(() => {
    router.history.replace('/home');
  });

  it.each(['/movies', '/series', '/live', '/watchlist'])('matches the %s destination', path => {
    expect(matchedRouteIds(path)).toContain(`/protected${path}`);
  });

  it('preserves detail and watch routes', () => {
    expect(matchedRouteIds('/browse/movie/tt123')).toContain('/protected/browse/$type/$id');
    expect(matchedRouteIds('/watch/series/tt123:1:2')).toContain('/protected/watch/$type/$id');
  });

  it('redirects the legacy library route to watchlist', async () => {
    await router.navigate({ to: '/library' });

    expect(router.state.location.pathname).toBe('/watchlist');
  });
});
