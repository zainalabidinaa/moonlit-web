import { fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { normalizePlayerLaunch } from '@/lib/player/contracts';
import { PlayerOverlay } from './PlayerOverlay';

const launch = normalizePlayerLaunch({
  type: 'movie',
  id: 'tt-overlay',
  metadata: { mediaId: 'tt-overlay', mediaType: 'movie', title: 'Overlay Movie' },
});
const closeMock = vi.hoisted(() => vi.fn());

vi.mock('@/app/PlayerProvider', () => ({
  usePlayer: () => ({ isOpen: true, launch, close: closeMock }),
}));

vi.mock('@/app/AuthProvider', () => ({
  useAuth: () => ({ currentProfile: { id: 'profile-1' } }),
}));

vi.mock('@/components/player/PlayerShell', () => ({
  PlayerShell: ({ profileId }: { profileId?: string }) => (
    <div data-testid="unified-shell" data-profile-id={profileId} />
  ),
}));

vi.mock('@/components/player/LoadingCard', () => ({
  LoadingCard: () => <div data-testid="legacy-loading-card" />,
}));

describe('PlayerOverlay', () => {
  it('mounts one unified player surface without a competing legacy loading layer', () => {
    render(<PlayerOverlay />);

    expect(screen.getByTestId('unified-shell')).toHaveAttribute('data-profile-id', 'profile-1');
    expect(screen.queryByTestId('legacy-loading-card')).not.toBeInTheDocument();
  });

  it('does not close the player when Escape belongs to an open chrome panel', () => {
    render(<PlayerOverlay />);
    const panel = document.createElement('section');
    panel.dataset.playerPanel = 'true';
    document.body.append(panel);

    fireEvent.keyDown(window, { key: 'Escape' });

    expect(closeMock).not.toHaveBeenCalled();
    panel.remove();
  });
});

afterEach(() => closeMock.mockReset());
