import type { CSSProperties } from 'react';

export type SubtitleSize = 'small' | 'medium' | 'large' | 'xlarge';
export type SubtitleColor = 'white' | 'yellow' | 'cyan' | 'green';
export type SubtitlePosition = 'low' | 'medium' | 'high';

export interface SubtitlePreferences {
  size: SubtitleSize;
  color: SubtitleColor;
  backgroundOpacity: number;
  position: SubtitlePosition;
}

export const DEFAULT_SUBTITLE_PREFERENCES: SubtitlePreferences = {
  size: 'medium',
  color: 'white',
  backgroundOpacity: 70,
  position: 'low',
};

const STORAGE_KEY = 'moonlit_subtitle_preferences';

const SIZE_PX: Record<SubtitleSize, number> = {
  small: 18,
  medium: 24,
  large: 30,
  xlarge: 38,
};

const COLORS: Record<SubtitleColor, string> = {
  white: '#ffffff',
  yellow: '#fde68a',
  cyan: '#a5f3fc',
  green: '#bbf7d0',
};

const BOTTOM_PX: Record<SubtitlePosition, number> = {
  low: 112,
  medium: 168,
  high: 232,
};

function normalizePreferences(value: Partial<SubtitlePreferences> | null | undefined): SubtitlePreferences {
  return {
    size: value?.size && value.size in SIZE_PX ? value.size : DEFAULT_SUBTITLE_PREFERENCES.size,
    color: value?.color && value.color in COLORS ? value.color : DEFAULT_SUBTITLE_PREFERENCES.color,
    backgroundOpacity: typeof value?.backgroundOpacity === 'number'
      ? Math.max(0, Math.min(100, Math.round(value.backgroundOpacity)))
      : DEFAULT_SUBTITLE_PREFERENCES.backgroundOpacity,
    position: value?.position && value.position in BOTTOM_PX ? value.position : DEFAULT_SUBTITLE_PREFERENCES.position,
  };
}

export function loadSubtitlePreferences(): SubtitlePreferences {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_SUBTITLE_PREFERENCES;
    return normalizePreferences(JSON.parse(raw));
  } catch {
    return DEFAULT_SUBTITLE_PREFERENCES;
  }
}

export function saveSubtitlePreferences(preferences: SubtitlePreferences): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(normalizePreferences(preferences)));
  } catch {
    // Ignore storage failures in private mode.
  }
}

export function getSubtitlePreferenceStyle(preferences: SubtitlePreferences): CSSProperties & Record<`--${string}`, string | number> {
  const normalized = normalizePreferences(preferences);
  const opacity = normalized.backgroundOpacity / 100;
  return {
    '--moonlit-subtitle-font-size': `${SIZE_PX[normalized.size]}px`,
    '--moonlit-subtitle-color': COLORS[normalized.color],
    '--moonlit-subtitle-bg': `rgba(0, 0, 0, ${opacity})`,
    '--moonlit-subtitle-bottom': `${BOTTOM_PX[normalized.position]}px`,
  };
}
