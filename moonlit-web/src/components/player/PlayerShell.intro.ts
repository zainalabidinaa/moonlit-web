import type { NormalizedPlayerLaunch } from '@/lib/player/contracts';
import type { PlayerPreferences } from '@/lib/preferences/profile-preferences';
import type { PlayerIntro } from './UnifiedPlayer';

export interface IntroLookup {
  imdbId: string;
  season?: number;
  episode?: number;
}

export interface IntroRange {
  start: number;
  end: number;
}

export function getIntroLookup(launch: NormalizedPlayerLaunch): IntroLookup | null {
  if (launch.type !== 'series') return null;
  const match = launch.id.match(/^(tt\d+):(\d+):(\d+)$/);
  if (match) {
    return { imdbId: match[1], season: Number(match[2]), episode: Number(match[3]) };
  }
  const imdbId = launch.id.split(':')[0];
  if (!/^tt\d+$/.test(imdbId)) return null;
  return {
    imdbId,
    season: launch.metadata.season,
    episode: launch.metadata.episode,
  };
}

export function selectIntroConfig(
  remote: IntroRange | null,
  preferences: PlayerPreferences,
): PlayerIntro | null {
  const validRemote = remote
    && Number.isFinite(remote.start)
    && Number.isFinite(remote.end)
    && remote.end > remote.start
    ? { start: Math.max(0, remote.start), end: remote.end }
    : null;
  const range = validRemote ?? (preferences.fallbackSkipEnabled
    ? { start: 0, end: preferences.fallbackSkipSeconds }
    : null);
  if (!range) return null;
  return {
    ...range,
    showButton: preferences.showSkipIntroButton,
    autoSkip: preferences.autoSkipIntros,
  };
}
