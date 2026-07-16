import { describe, it, expect } from 'vitest';
import { dominantColor, boostForHalo, rgbToHex } from './color-extract';

function rgba(r: number, g: number, b: number, a = 255): Uint8ClampedArray {
  return new Uint8ClampedArray([r, g, b, a]);
}

describe('dominantColor', () => {
  it('finds the dominant hue in a solid-color image', () => {
    const pix = new Uint8ClampedArray(16 * 4); // 4 × 1
    for (let i = 0; i < 16; i += 4) { pix[i] = 212; pix[i + 1] = 175; pix[i + 2] = 55; pix[i + 3] = 255; }
    const color = dominantColor(pix, 4, 1);
    expect(color).toBeTruthy();
    expect(rgbToHex(color!).toUpperCase()).toBe('#D4AF37');
  });

  it('filters out near-black and near-white', () => {
    const pix = new Uint8ClampedArray([0, 0, 0, 255, 255, 255, 255, 255, 212, 175, 55, 255]);
    const color = dominantColor(pix, 3, 1);
    expect(rgbToHex(color!).toUpperCase()).toBe('#D4AF37');
  });

  it('returns null when all pixels are filtered', () => {
    const pix = new Uint8ClampedArray([0, 0, 0, 255, 255, 255, 255, 255]);
    expect(dominantColor(pix, 2, 1)).toBeNull();
  });
});

describe('boostForHalo', () => {
  it('boosts saturation and brightness', () => {
    const result = boostForHalo({ r: 100, g: 80, b: 50 });
    expect(result.r).toBeGreaterThan(100);
    expect(result.r).toBeGreaterThan(result.b); // warm color stays warm
  });
});
