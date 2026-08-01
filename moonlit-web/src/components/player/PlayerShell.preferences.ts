import type { PlayerEnginePreference, PlayerPreferences } from '@/lib/preferences/profile-preferences';
import type { NormalizedPlayerLaunch } from '@/lib/player/contracts';

export interface AppliedPlayerPreferences {
  launch: NormalizedPlayerLaunch;
  enginePreference: PlayerEnginePreference;
  showOnlyCompatibleFormats: boolean;
}

export function applyPlayerPreferences(
  launch: NormalizedPlayerLaunch,
  preferences: PlayerPreferences,
): AppliedPlayerPreferences {
  let enginePreference: PlayerEnginePreference = 'auto';
  if (preferences.usePerTypePlayers) {
    if (launch.isLive || launch.type === 'tv' || launch.type === 'live') {
      enginePreference = preferences.livePlayer;
    } else if (launch.type === 'series') {
      enginePreference = preferences.seriesPlayer;
    } else {
      enginePreference = preferences.moviePlayer;
    }
  }

  return {
    enginePreference,
    showOnlyCompatibleFormats: preferences.showOnlyCompatibleFormats,
    launch: {
      ...launch,
      preferredTracks: {
        ...launch.preferredTracks,
        audioLanguage: launch.preferredTracks.audioLanguage ?? preferences.preferredAudioLanguage,
        subtitleLanguage: launch.preferredTracks.subtitleLanguage ?? preferences.preferredSubtitleLanguage,
      },
    },
  };
}
