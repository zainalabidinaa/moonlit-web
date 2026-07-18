import type { SubtitlePreferences } from '@/lib/subtitle-preferences';

const SIZE_PT: Record<SubtitlePreferences['size'], number> = { small: 30, medium: 38, large: 46, xlarge: 55 };
const COLOR_HEX: Record<SubtitlePreferences['color'], string> = { white: '#FFFFFF', yellow: '#FFD54A', cyan: '#4AD8FF', green: '#4AFF6A' };
const POSITION_PCT: Record<SubtitlePreferences['position'], number> = { low: 98, medium: 80, high: 60 };

/** Map web SubtitlePreferences to mpv sub-* properties. */
export function subtitlePrefsToMpvProps(p: SubtitlePreferences): Record<string, string | number> {
  const alpha = Math.round((p.backgroundOpacity / 100) * 255)
    .toString(16).padStart(2, '0').toUpperCase();
  return {
    'sub-font-size': SIZE_PT[p.size],
    'sub-color': COLOR_HEX[p.color],
    'sub-back-color': `#000000${alpha}`,
    'sub-pos': POSITION_PCT[p.position],
    'sub-border-size': 1.5,
    'sub-border-color': '#000000',
  };
}
