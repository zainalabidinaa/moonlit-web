import { fireEvent, render, screen } from '@testing-library/react';
import {
  Outlet,
  RouterProvider,
  createMemoryHistory,
  createRootRoute,
  createRoute,
  createRouter,
} from '@tanstack/react-router';
import { describe, expect, it, vi } from 'vitest';

import { AppShell } from './AppShell';

vi.mock('@/app/AuthProvider', () => ({
  useAuth: () => ({ currentProfile: null, selectProfile: vi.fn() }),
}));

function renderShell(path = '/movies') {
  const rootRoute = createRootRoute({
    component: () => (
      <AppShell>
        <Outlet />
      </AppShell>
    ),
  });
  const pageRoute = createRoute({
    getParentRoute: () => rootRoute,
    path: '/$page',
    component: () => <div>Page content</div>,
  });
  const router = createRouter({
    routeTree: rootRoute.addChildren([pageRoute]),
    history: createMemoryHistory({ initialEntries: [path] }),
  });

  return render(<RouterProvider router={router} />);
}

describe('AppShell navigation', () => {
  it('renders the approved brand and primary destinations', async () => {
    renderShell();

    expect(await screen.findByRole('img', { name: 'Moonlit' })).toHaveAttribute('src', '/moonlit-icon.png');
    expect(screen.getByText('MOONLIT')).toHaveClass('font-brand');
    expect(screen.getByRole('navigation', { name: 'Primary' })).toBeInTheDocument();

    for (const label of ['Home', 'Movies', 'Series', 'Live TV', 'Watchlist']) {
      expect(screen.getByRole('link', { name: label })).toBeInTheDocument();
    }
  });

  it('marks the matching primary destination as the current page', async () => {
    renderShell('/movies');

    expect(await screen.findByRole('link', { name: 'Movies' })).toHaveAttribute('aria-current', 'page');
    expect(screen.getByRole('link', { name: 'Home' })).not.toHaveAttribute('aria-current');
  });

  it('provides an accessible responsive menu toggle', async () => {
    renderShell();

    const openButton = await screen.findByRole('button', { name: 'Open navigation menu' });
    expect(openButton).toHaveAttribute('aria-expanded', 'false');

    fireEvent.click(openButton);

    expect(screen.getByRole('button', { name: 'Close navigation menu' })).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByRole('navigation', { name: 'Mobile' })).toBeInTheDocument();
  });
});
