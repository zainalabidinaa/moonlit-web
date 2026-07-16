/// Pure pixel → dominant-color math (no DOM, testable).
/// Port of the Mac TileHaloColor pipeline (CGImage → 16³ histogram) and
/// FusionAmbientBackground extraction (vImage box-blur → dual-peak).

export interface RGB {
  r: number; // 0-255
  g: number;
  b: number;
}

/** Convert RGB to CSS hex. */
export function rgbToHex({ r, g, b }: RGB): string {
  return `#${[r, g, b].map((c) => Math.round(c).toString(16).padStart(2, '0')).join('')}`;
}

/** Relative luminance (sRGB). */
export function luminance({ r, g, b }: RGB): number {
  // Normalize to 0-1
  return 0.2126 * (r / 255) + 0.7152 * (g / 255) + 0.0722 * (b / 255);
}

/** Chroma²-weighted dominant color from a flat RGBA pixel buffer.
 *  Uses 16³ histogram with chroma² weight (matching Mac TileHaloColor).
 *  Filters: brightness ∈ [0.10, 0.92], saturation ≥ 0.12.
 */
export function dominantColor(pixels: Uint8ClampedArray, width: number, height: number): RGB | null {
  const bins = 16;
  const weightMap = new Float64Array(bins * bins * bins);
  const sumR = new Float64Array(bins * bins * bins);
  const sumG = new Float64Array(bins * bins * bins);
  const sumB = new Float64Array(bins * bins * bins);
  let total = 0;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      const r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
      const max = Math.max(r, g, b);
      const min = Math.min(r, g, b);
      const chroma = max - min;
      const bright = max / 255;
      if (bright < 0.10 || bright > 0.92) continue;
      if (chroma < 0.12 * 255) continue;
      const weight = (chroma / 255) ** 2;
      const ri = Math.min(bins - 1, Math.floor((r / 255) * bins));
      const gi = Math.min(bins - 1, Math.floor((g / 255) * bins));
      const bi = Math.min(bins - 1, Math.floor((b / 255) * bins));
      const idx = (ri * bins + gi) * bins + bi;
      weightMap[idx] += weight;
      sumR[idx] += r * weight;
      sumG[idx] += g * weight;
      sumB[idx] += b * weight;
      total += weight;
    }
  }
  if (total === 0) return null;

  let maxVal = 0, maxIdx = 0;
  for (let i = 0; i < weightMap.length; i++) {
    if (weightMap[i] > maxVal) { maxVal = weightMap[i]; maxIdx = i; }
  }
  const w = weightMap[maxIdx];
  return {
    r: sumR[maxIdx] / w,
    g: sumG[maxIdx] / w,
    b: sumB[maxIdx] / w,
  };
}

/** Boosts color for tile halo (Mac: sat ×1.7 [clamp 0.70–1.0], bright ×1.25 [clamp 0.60–0.95]). */
export function boostForHalo(c: RGB): RGB {
  // Convert to HSL, boost sat, return to RGB
  const r = c.r / 255, g = c.g / 255, b = c.b / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  const l = (max + min) / 2;
  const d = max - min;
  const sat = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  const newSat = Math.min(1, Math.max(0.70, sat * 1.7));
  const newBright = Math.min(0.95, Math.max(0.60, l * 1.25));
  // Reconstruct with boosted sat + brightness (simple lerp to white)
  const factor = newBright / Math.max(l, 0.001);
  const t = Math.max(0, Math.min(1, (newSat / Math.max(sat, 0.001))));
  // Mix: original RGB → gray (sat=0) → boosted
  const gray = newBright;
  const nr = gray + t * (r * factor - gray);
  const ng = gray + t * (g * factor - gray);
  const nb = gray + t * (b * factor - gray);
  return {
    r: Math.round(Math.max(0, Math.min(255, nr * 255))),
    g: Math.round(Math.max(0, Math.min(255, ng * 255))),
    b: Math.round(Math.max(0, Math.min(255, nb * 255))),
  };
}

/** Boost for ambient backgrounds (Mac: sat ×3.0 [clamp 0.70–1.0], bright ×1.5 [clamp 0.45–0.80]). */
export function boostForAmbient(c: RGB): RGB {
  const r = c.r / 255, g = c.g / 255, b = c.b / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  const l = (max + min) / 2;
  const d = max - min;
  const sat = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  const newSat = Math.min(1, Math.max(0.70, sat * 3.0));
  const newBright = Math.min(0.80, Math.max(0.45, l * 1.5));
  const factor = newBright / Math.max(l, 0.001);
  const t = Math.max(0, Math.min(1, (newSat / Math.max(sat, 0.001))));
  const gray = newBright;
  return {
    r: Math.round(Math.max(0, Math.min(255, (gray + t * (r * factor - gray)) * 255))),
    g: Math.round(Math.max(0, Math.min(255, (gray + t * (g * factor - gray)) * 255))),
    b: Math.round(Math.max(0, Math.min(255, (b === 0 ? 0 : gray + t * (b * factor - gray)) * 255))),
  };
}

/** Dual-peak extractor for ambient: dominant color of left/right halves, boosted. */
export function ambientColors(pixels: Uint8ClampedArray, width: number, height: number): [RGB, RGB] | null {
  const half = Math.floor(width / 2);
  const leftBuf = new Uint8ClampedArray(half * height * 4);
  const rightW = width - half;
  const rightBuf = new Uint8ClampedArray(rightW * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const src = (y * width + x) * 4;
      if (x < half) {
        const dst = (y * half + x) * 4;
        leftBuf.set(pixels.subarray(src, src + 4), dst);
      } else {
        const dst = (y * rightW + (x - half)) * 4;
        rightBuf.set(pixels.subarray(src, src + 4), dst);
      }
    }
  }
  const left = dominantColor(leftBuf, half, height);
  const right = dominantColor(rightBuf, rightW, height);
  if (!left && !right) return null;
  const a = left ?? right!;
  const b = right ?? left!;
  return [boostForAmbient(a), boostForAmbient(b)];
}
