import { describe, expect, it } from 'vitest';

import { DEFAULT_SUBTITLE_PREFERENCES } from '@/lib/subtitle-preferences';
import { subtitlePrefsToMpvProps } from './mpv-subtitle-style';

describe('subtitlePrefsToMpvProps', () => {
  it('maps expanded defaults to mpv properties', () => {
    const props = subtitlePrefsToMpvProps(DEFAULT_SUBTITLE_PREFERENCES);

    expect(props['sub-font-size']).toBe(32);
    expect(props['sub-color']).toBe('#FFFFFF');
    expect(props['sub-back-color']).toBe('#00000000');
    expect(props['sub-pos']).toBe(50);
    expect(props['sub-border-color']).toBe('#000000');
  });

  it('maps scale, opacity, style, and vertical position', () => {
    const props = subtitlePrefsToMpvProps({
      ...DEFAULT_SUBTITLE_PREFERENCES,
      fontSize: 40,
      scale: 1.5,
      textColorHex: '#FFD54A',
      backgroundColorHex: '#102030',
      backgroundOpacity: 0.5,
      outlineColorHex: '#010203',
      isBold: true,
      isItalic: true,
      verticalPosition: 200,
    });

    expect(props).toMatchObject({
      'sub-font-size': 60,
      'sub-color': '#FFD54A',
      'sub-back-color': '#10203080',
      'sub-border-color': '#010203',
      'sub-bold': 'yes',
      'sub-italic': 'yes',
      'sub-pos': 0,
    });
  });
});
