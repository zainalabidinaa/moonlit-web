/// Artwork-derived colors: canvas downsample + dominant-color extraction,
/// cached per URL. Drives tile halos and ambient hero/detail backgrounds
/// (Mac TileHaloColor / MacFusionAmbientBackground parity).
import { useEffect, useState } from 'react';
import { ambientColors, boostForHalo, dominantColor, rgbToHex, type RGB } from './color-extract';

const haloCache = new Map<string, string | null>();
const ambientCache = new Map<string, [string, string] | null>();

function loadImagePixels(url: string, targetW: number): Promise<{ pixels: Uint8ClampedArray; w: number; h: number } | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      try {
        const scale = targetW / img.naturalWidth;
        const w = targetW;
        const h = Math.max(1, Math.round(img.naturalHeight * scale));
        const canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext('2d', { willReadFrequently: true });
        if (!ctx) return resolve(null);
        ctx.drawImage(img, 0, 0, w, h);
        resolve({ pixels: ctx.getImageData(0, 0, w, h).data, w, h });
      } catch {
        resolve(null); // canvas tainted (no CORS headers) — degrade gracefully
      }
    };
    img.onerror = () => resolve(null);
    img.src = url;
  });
}

/** Dominant artwork color for tile hover halos (boosted, hex) — null if unavailable. */
export async function extractHaloColor(url: string): Promise<string | null> {
  if (haloCache.has(url)) return haloCache.get(url)!;
  const data = await loadImagePixels(url, 36);
  let result: string | null = null;
  if (data) {
    const dom: RGB | null = dominantColor(data.pixels, data.w, data.h);
    if (dom) result = rgbToHex(boostForHalo(dom));
  }
  haloCache.set(url, result);
  return result;
}

/** Two ambient colors (left/right) for hero/detail washes — null if unavailable. */
export async function extractAmbientColors(url: string): Promise<[string, string] | null> {
  if (ambientCache.has(url)) return ambientCache.get(url)!;
  const data = await loadImagePixels(url, 40);
  let result: [string, string] | null = null;
  if (data) {
    const pair = ambientColors(data.pixels, data.w, data.h);
    if (pair) result = [rgbToHex(pair[0]), rgbToHex(pair[1])];
  }
  ambientCache.set(url, result);
  return result;
}

/** React hook: artwork halo color (hex) or null while loading/unavailable. */
export function useTileHalo(url: string | undefined): string | null {
  const [color, setColor] = useState<string | null>(url ? haloCache.get(url) ?? null : null);
  useEffect(() => {
    if (!url) return;
    let alive = true;
    extractHaloColor(url).then((c) => { if (alive) setColor(c); });
    return () => { alive = false; };
  }, [url]);
  return color;
}

/** React hook: [colorA, colorB] ambient pair or null. */
export function useAmbientColors(url: string | undefined): [string, string] | null {
  const [colors, setColors] = useState<[string, string] | null>(url ? ambientCache.get(url) ?? null : null);
  useEffect(() => {
    if (!url) return;
    let alive = true;
    extractAmbientColors(url).then((c) => { if (alive) setColors(c); });
    return () => { alive = false; };
  }, [url]);
  return colors;
}
