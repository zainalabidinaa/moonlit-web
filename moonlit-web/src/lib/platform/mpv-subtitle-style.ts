import { normalizeSubtitlePreferences, type SubtitlePreferences } from '@/lib/subtitle-preferences';

/** Map the shared expanded SubtitlePreferences contract to mpv sub-* properties. */
export function subtitlePrefsToMpvProps(preferences: SubtitlePreferences): Record<string, string | number> {
  const value = normalizeSubtitlePreferences(preferences);
  const alpha = Math.round(value.backgroundOpacity * 255).toString(16).padStart(2, '0').toUpperCase();
  const verticalPosition = Math.round(100 - value.verticalPosition / 2);

  return {
    'sub-font-size': Math.round(value.fontSize * value.scale),
    'sub-color': value.textColorHex,
    'sub-back-color': `${value.backgroundColorHex}${alpha}`,
    'sub-pos': verticalPosition,
    'sub-border-size': Math.max(1, value.textBlur),
    'sub-border-color': value.outlineColorHex,
    'sub-bold': value.isBold ? 'yes' : 'no',
    'sub-italic': value.isItalic ? 'yes' : 'no',
    'sub-align-x': value.horizontalAlignment,
    'sub-margin-x': value.horizontalMargin,
    'sub-scale-with-window': value.scaleWithWindowSize ? 'yes' : 'no',
  };
}
