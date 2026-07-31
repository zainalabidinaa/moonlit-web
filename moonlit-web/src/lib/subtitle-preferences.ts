import type { CSSProperties } from 'react';

import {
  DEFAULT_SUBTITLE_PREFERENCES,
  createProfilePreferencesRepository,
  normalizeSubtitlePreferences,
  type ProfilePreferencesRepository,
  type SubtitleAlignment,
  type SubtitlePreferences,
  type SubtitlePreset,
} from '@/lib/preferences/profile-preferences';

export {
  DEFAULT_SUBTITLE_PREFERENCES,
  normalizeSubtitlePreferences,
  type SubtitleAlignment,
  type SubtitlePreferences,
  type SubtitlePreset,
};

type SubtitlePreferencesListener = (preferences: SubtitlePreferences) => void;

let repository: ProfilePreferencesRepository | undefined;
let activeProfileId: string | null = null;
let activationRevision = 0;
const listeners = new Set<SubtitlePreferencesListener>();

function preferencesRepository(): ProfilePreferencesRepository {
  repository ??= createProfilePreferencesRepository();
  return repository;
}

function publish(preferences: SubtitlePreferences): void {
  const normalized = normalizeSubtitlePreferences(preferences);
  listeners.forEach(listener => listener(normalized));
}

export async function activateSubtitlePreferences(profileId: string | null): Promise<SubtitlePreferences> {
  activeProfileId = profileId;
  const revision = ++activationRevision;
  const targetRepository = preferencesRepository();
  const cached = targetRepository.loadCached(profileId, 'subtitles').value;
  publish(cached);

  const reconciled = await targetRepository.load(profileId, 'subtitles');
  if (revision === activationRevision && profileId === activeProfileId) publish(reconciled.value);
  return reconciled.value;
}

export function subscribeSubtitlePreferences(listener: SubtitlePreferencesListener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function loadSubtitlePreferences(): SubtitlePreferences {
  return preferencesRepository().loadCached(activeProfileId, 'subtitles').value;
}

export function saveSubtitlePreferences(preferences: SubtitlePreferences): void {
  const normalized = normalizeSubtitlePreferences(preferences);
  void preferencesRepository().save(activeProfileId, 'subtitles', normalized);
  publish(normalized);
}

function rgba(hex: string, opacity: number): string {
  const channels = hex.slice(1).match(/.{2}/g)?.map(channel => Number.parseInt(channel, 16)) ?? [0, 0, 0];
  return `rgba(${channels[0]}, ${channels[1]}, ${channels[2]}, ${opacity})`;
}

export function getSubtitlePreferenceStyle(preferences: SubtitlePreferences): CSSProperties & Record<`--${string}`, string | number> {
  const normalized = normalizeSubtitlePreferences(preferences);
  return {
    '--moonlit-subtitle-font-size': `${Math.round(normalized.fontSize * normalized.scale)}px`,
    '--moonlit-subtitle-color': normalized.textColorHex,
    '--moonlit-subtitle-outline': normalized.outlineColorHex,
    '--moonlit-subtitle-bg': rgba(normalized.backgroundColorHex, normalized.backgroundOpacity),
    '--moonlit-subtitle-bottom': `${normalized.verticalPosition}px`,
    '--moonlit-subtitle-align': normalized.horizontalAlignment,
    '--moonlit-subtitle-margin': `${normalized.horizontalMargin}px`,
    '--moonlit-subtitle-blur': `${normalized.textBlur}px`,
    '--moonlit-subtitle-font-weight': normalized.isBold ? 700 : 400,
    '--moonlit-subtitle-font-style': normalized.isItalic ? 'italic' : 'normal',
  };
}
