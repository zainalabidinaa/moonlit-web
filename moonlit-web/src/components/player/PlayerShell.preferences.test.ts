import { describe, expect, it } from 'vitest';

import { DEFAULT_PLAYER_PREFERENCES } from '@/lib/preferences/profile-preferences';
import { normalizePlayerLaunch } from '@/lib/player/contracts';
import { applyPlayerPreferences } from './PlayerShell.preferences';

describe('applyPlayerPreferences', () => {
  it.each([
    ['movie', 'moviePlayer', 'native'],
    ['series', 'seriesPlayer', 'mpv'],
    ['tv', 'livePlayer', 'native'],
  ] as const)('uses the per-type engine for %s launches', (type, key, expected) => {
    const launch = normalizePlayerLaunch({
      type,
      id: 'media-id',
      metadata: { mediaId: 'media-id', mediaType: type, title: 'Media' },
      isLive: type === 'tv',
    });
    const preferences = {
      ...DEFAULT_PLAYER_PREFERENCES,
      usePerTypePlayers: true,
      moviePlayer: 'auto' as const,
      seriesPlayer: 'auto' as const,
      livePlayer: 'auto' as const,
      [key]: expected,
    };

    expect(applyPlayerPreferences(launch, preferences).enginePreference).toBe(expected);
  });

  it('keeps auto routing when per-type engines are disabled', () => {
    const launch = normalizePlayerLaunch({
      type: 'movie',
      id: 'tt123',
      metadata: { mediaId: 'tt123', mediaType: 'movie', title: 'Movie' },
    });

    expect(applyPlayerPreferences(launch, {
      ...DEFAULT_PLAYER_PREFERENCES,
      usePerTypePlayers: false,
      moviePlayer: 'mpv',
    }).enginePreference).toBe('auto');
  });

  it('uses profile languages without overwriting explicit launch track choices', () => {
    const launch = normalizePlayerLaunch({
      type: 'series',
      id: 'tt123:1:2',
      metadata: { mediaId: 'tt123:1:2', mediaType: 'series', title: 'Episode' },
      preferredTracks: { audioLanguage: 'ja' },
    });

    expect(applyPlayerPreferences(launch, {
      ...DEFAULT_PLAYER_PREFERENCES,
      preferredAudioLanguage: 'en',
      preferredSubtitleLanguage: 'sv',
    }).launch.preferredTracks).toMatchObject({
      audioLanguage: 'ja',
      subtitleId: null,
      subtitleLanguage: 'sv',
    });
  });
});
