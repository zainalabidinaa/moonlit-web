import { describe, it, expect } from 'vitest';
import { subtitlePrefsToMpvProps } from './mpv-subtitle-style';

describe('subtitlePrefsToMpvProps', () => {
  it('maps defaults to mpv properties', () => {
    const props = subtitlePrefsToMpvProps({ size: 'medium', color: 'white', backgroundOpacity: 70, position: 'low' });
    expect(props['sub-font-size']).toBe(38);
    expect(props['sub-color']).toBe('#FFFFFF');
    expect(props['sub-back-color']).toBe('#000000B3');
    expect(props['sub-pos']).toBe(98);
  });
  it('maps size/color/position variants', () => {
    const props = subtitlePrefsToMpvProps({ size: 'xlarge', color: 'yellow', backgroundOpacity: 0, position: 'high' });
    expect(props['sub-font-size']).toBe(55);
    expect(props['sub-color']).toBe('#FFD54A');
    expect(props['sub-back-color']).toBe('#00000000');
    expect(props['sub-pos']).toBe(60);
  });
});
