import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { useState } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AuthProvider, useAuth } from './AuthProvider';
import {
  activateSubtitlePreferences,
  DEFAULT_SUBTITLE_PREFERENCES,
  loadSubtitlePreferences,
  saveSubtitlePreferences,
  subscribeSubtitlePreferences,
} from '@/lib/subtitle-preferences';
import type { ProfilePreferenceRow } from '@/lib/preferences/profile-preferences';
import type { MoonlitProfile } from '@/lib/types';

const authMocks = vi.hoisted(() => {
  const cloudRows = new Map<string, ProfilePreferenceRow>();
  return {
    session: null as { user: { id: string } } | null,
    profiles: [] as MoonlitProfile[],
    cloudRows,
    preferenceRead: vi.fn(async () => ({ data: null, error: null })),
    preferenceUpsert: vi.fn(async (row: ProfilePreferenceRow) => {
      cloudRows.set(`${row.profile_id}:${row.namespace}`, row);
      return { error: null };
    }),
  };
});

vi.mock('@/lib/supabase', () => {
  const preferenceQuery = {
    select: vi.fn(),
    eq: vi.fn(),
    maybeSingle: authMocks.preferenceRead,
    upsert: authMocks.preferenceUpsert,
  };
  preferenceQuery.select.mockReturnValue(preferenceQuery);
  preferenceQuery.eq.mockReturnValue(preferenceQuery);

  return {
    DEFAULT_ADDONS: [],
    supabase: {
      auth: {
        getSession: vi.fn(async () => ({ data: { session: authMocks.session } })),
        onAuthStateChange: vi.fn(() => ({ subscription: { unsubscribe: vi.fn() } })),
        signOut: vi.fn(async () => undefined),
      },
      from: vi.fn(() => preferenceQuery),
    },
  };
});

vi.mock('@/lib/services/api', () => ({
  getProfiles: vi.fn(async () => authMocks.profiles),
  getInstalledAddons: vi.fn(async () => []),
  getSharedAddons: vi.fn(async () => []),
}));

vi.mock('@/lib/stremio', () => ({
  fetchManifest: vi.fn(),
}));

const PROFILE: MoonlitProfile = {
  id: 'profile-a',
  user_id: 'user-a',
  name: 'Profile A',
  profile_index: 0,
  role: 'user',
  isAdmin: false,
};

function storedSubtitles(profileId: string | 'guest', fontSize: number) {
  localStorage.setItem(`moonlit.preferences.${profileId}.subtitles`, JSON.stringify({
    schemaVersion: 1,
    value: { ...DEFAULT_SUBTITLE_PREFERENCES, fontSize },
    updatedAt: '2026-08-01T09:00:00.000Z',
  }));
}

function PreferenceProbe() {
  const { currentProfile, guestMode, enterGuestMode } = useAuth();
  const [, setRevision] = useState(0);
  const fontSize = currentProfile || guestMode ? loadSubtitlePreferences().fontSize : null;

  return (
    <div>
      <span data-testid="scope">{currentProfile?.id ?? (guestMode ? 'guest' : 'none')}</span>
      <span data-testid="font-size">{fontSize ?? 'uninitialized'}</span>
      <button type="button" onClick={enterGuestMode}>Enter guest</button>
      <button
        type="button"
        onClick={() => {
          saveSubtitlePreferences({ ...loadSubtitlePreferences(), fontSize: 42 });
          setRevision(revision => revision + 1);
        }}
      >
        Save subtitle size
      </button>
    </div>
  );
}

describe('AuthProvider subtitle preference lifecycle', () => {
  beforeEach(() => {
    localStorage.clear();
    authMocks.session = null;
    authMocks.profiles = [];
    authMocks.cloudRows.clear();
    authMocks.preferenceRead.mockReset().mockResolvedValue({ data: null, error: null });
    authMocks.preferenceUpsert.mockReset().mockImplementation(async (row: ProfilePreferenceRow) => {
      authMocks.cloudRows.set(`${row.profile_id}:${row.namespace}`, row);
      return { error: null };
    });
  });

  it('activates the selected profile before synchronous subtitle consumers read and write', async () => {
    authMocks.session = { user: { id: 'user-a' } };
    authMocks.profiles = [PROFILE];
    storedSubtitles(PROFILE.id, 38);

    render(<AuthProvider><PreferenceProbe /></AuthProvider>);

    await waitFor(() => expect(screen.getByTestId('scope')).toHaveTextContent(PROFILE.id));
    await waitFor(() => expect(screen.getByTestId('font-size')).toHaveTextContent('38'));

    fireEvent.click(screen.getByRole('button', { name: 'Save subtitle size' }));

    const saved = JSON.parse(localStorage.getItem(`moonlit.preferences.${PROFILE.id}.subtitles`) ?? '{}');
    expect(saved.value.fontSize).toBe(42);
    expect(localStorage.getItem('moonlit_subtitle_preferences')).toBeNull();
  });

  it('activates guest-local subtitle storage without calling the legacy global key', async () => {
    storedSubtitles('guest', 24);
    render(<AuthProvider><PreferenceProbe /></AuthProvider>);

    fireEvent.click(screen.getByRole('button', { name: 'Enter guest' }));

    await waitFor(() => expect(screen.getByTestId('scope')).toHaveTextContent('guest'));
    expect(screen.getByTestId('font-size')).toHaveTextContent('24');

    fireEvent.click(screen.getByRole('button', { name: 'Save subtitle size' }));

    const saved = JSON.parse(localStorage.getItem('moonlit.preferences.guest.subtitles') ?? '{}');
    expect(saved.value.fontSize).toBe(42);
    expect(localStorage.getItem('moonlit_subtitle_preferences')).toBeNull();
  });

  it('keeps subscriber and cloud state on a save made during a delayed activation upsert', async () => {
    const profileId = 'profile-race';
    storedSubtitles(profileId, 24);
    const publications: number[] = [];
    const unsubscribe = subscribeSubtitlePreferences(preferences => {
      publications.push(preferences.fontSize);
    });
    let resolveActivationUpsert: (() => void) | undefined;

    authMocks.preferenceUpsert.mockImplementationOnce((row: ProfilePreferenceRow) => new Promise(resolve => {
      resolveActivationUpsert = () => {
        authMocks.cloudRows.set(`${row.profile_id}:${row.namespace}`, row);
        resolve({ error: null });
      };
    }));

    const activation = activateSubtitlePreferences(profileId);
    await vi.waitFor(() => expect(resolveActivationUpsert).toBeTypeOf('function'));

    saveSubtitlePreferences({ ...loadSubtitlePreferences(), fontSize: 42 });
    expect(publications.at(-1)).toBe(42);

    resolveActivationUpsert?.();
    await activation;

    await vi.waitFor(() => {
      expect(authMocks.cloudRows.get(`${profileId}:subtitles`)?.value).toMatchObject({ fontSize: 42 });
    });
    expect(publications.at(-1)).toBe(42);
    expect(loadSubtitlePreferences().fontSize).toBe(42);
    unsubscribe();
  });
});
