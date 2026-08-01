import { describe, expect, it } from 'vitest';

import { normalizePlayerLaunch } from '@/lib/player/contracts';
import { DEFAULT_PLAYER_PREFERENCES } from '@/lib/preferences/profile-preferences';
import { getIntroLookup, selectIntroConfig } from './PlayerShell.intro';

describe('PlayerShell intro preferences', () => {
  it('derives the IntroDB identity from an episodic launch', () => {
    const launch = normalizePlayerLaunch({
      type: 'series',
      id: 'tt1234567:2:4',
      metadata: { mediaId: 'tt1234567:2:4', mediaType: 'series', title: 'Episode' },
    });

    expect(getIntroLookup(launch)).toEqual({ imdbId: 'tt1234567', season: 2, episode: 4 });
  });

  it('prefers a valid IntroDB range and carries prompt/auto-skip choices', () => {
    expect(selectIntroConfig({ start: 18, end: 92 }, {
      ...DEFAULT_PLAYER_PREFERENCES,
      showSkipIntroButton: false,
      autoSkipIntros: true,
    })).toEqual({ start: 18, end: 92, showButton: false, autoSkip: true });
  });

  it('uses the configured fallback window only when fallback skipping is enabled', () => {
    expect(selectIntroConfig(null, {
      ...DEFAULT_PLAYER_PREFERENCES,
      fallbackSkipEnabled: true,
      fallbackSkipSeconds: 70,
    })).toEqual({ start: 0, end: 70, showButton: true, autoSkip: false });
    expect(selectIntroConfig(null, {
      ...DEFAULT_PLAYER_PREFERENCES,
      fallbackSkipEnabled: false,
    })).toBeNull();
  });
});
