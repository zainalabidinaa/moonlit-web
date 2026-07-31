import type { CSSProperties } from 'react';

import {
  DEFAULT_SUBTITLE_PREFERENCES,
  normalizeSubtitlePreferences,
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

const STORAGE_KEY = 'moonlit_subtitle_preferences';

export function loadSubtitlePreferences(): SubtitlePreferences {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? normalizeSubtitlePreferences(JSON.parse(raw)) : normalizeSubtitlePreferences({});
  } catch {
    return normalizeSubtitlePreferences({});
  }
}

export function saveSubtitlePreferences(preferences: SubtitlePreferences): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(normalizeSubtitlePreferences(preferences)));
  } catch {
    // Private browsing can make localStorage unavailable.
  }
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
