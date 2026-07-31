import { beforeEach, describe, expect, it } from 'vitest';

import {
  DEFAULT_SUBTITLE_PREFERENCES,
  getSubtitlePreferenceStyle,
  loadSubtitlePreferences,
  saveSubtitlePreferences,
} from './subtitle-preferences';

describe('subtitle preferences compatibility storage', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('loads the expanded Mac defaults when no preference is stored', () => {
    expect(loadSubtitlePreferences()).toEqual(DEFAULT_SUBTITLE_PREFERENCES);
  });

  it('persists normalized expanded subtitle preferences', () => {
    saveSubtitlePreferences({
      ...DEFAULT_SUBTITLE_PREFERENCES,
      preset: 'boxed',
      fontSize: 90,
      backgroundOpacity: 2,
      horizontalAlignment: 'right',
    });

    expect(loadSubtitlePreferences()).toEqual({
      ...DEFAULT_SUBTITLE_PREFERENCES,
      preset: 'boxed',
      fontSize: 72,
      backgroundOpacity: 1,
      horizontalAlignment: 'right',
    });
  });

  it('maps expanded preferences to caption CSS variables', () => {
    expect(getSubtitlePreferenceStyle({
      ...DEFAULT_SUBTITLE_PREFERENCES,
      fontSize: 38,
      scale: 1.5,
      textColorHex: '#A5F3FC',
      outlineColorHex: '#123456',
      backgroundColorHex: '#101010',
      backgroundOpacity: 0.25,
      verticalPosition: 168,
      horizontalAlignment: 'left',
      horizontalMargin: 24,
      textBlur: 2,
    })).toMatchObject({
      '--moonlit-subtitle-font-size': '57px',
      '--moonlit-subtitle-color': '#A5F3FC',
      '--moonlit-subtitle-outline': '#123456',
      '--moonlit-subtitle-bg': 'rgba(16, 16, 16, 0.25)',
      '--moonlit-subtitle-bottom': '168px',
      '--moonlit-subtitle-align': 'left',
      '--moonlit-subtitle-margin': '24px',
      '--moonlit-subtitle-blur': '2px',
    });
  });
});
