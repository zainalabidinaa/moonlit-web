import { useEffect, useRef, useState } from 'react';
import { useAmbientColors } from '@/lib/design/artwork-color';
import { EASE } from '@/lib/design/motion';

function hexToRgb(hex: string): [number, number, number] | null {
  const m = hex.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
  if (!m) return null;
  return [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)];
}

interface FusionBackgroundProps {
  backdropUrl?: string | null;
  /** Height of the hero above the color band (px). Used for scroll tracking. */
  heroHeight?: number;
  /** When true, the base is pure #141414 instead of the charcoal gradient */
  noCharcoal?: boolean;
}

export function FusionBackground({ backdropUrl, heroHeight = 0, noCharcoal = false }: FusionBackgroundProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const ambient = useAmbientColors(backdropUrl ?? undefined);
  const [colorA, colorB] = ambient ?? [null, null];
  const [bandOffset, setBandOffset] = useState(0);
  const prefersReducedMotion = typeof window !== 'undefined'
    && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  useEffect(() => {
    if (prefersReducedMotion || !heroHeight) return;

    let ticking = false;
    const handleScroll = () => {
      if (!ticking) {
        requestAnimationFrame(() => {
          const offset = Math.max(0, heroHeight - window.scrollY);
          setBandOffset(offset);
          ticking = false;
        });
        ticking = true;
      }
    };
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, [heroHeight, prefersReducedMotion]);

  const rgbA = colorA ? hexToRgb(colorA) : null;
  const rgbB = colorB ? hexToRgb(colorB) : null;

  return (
    <div ref={containerRef} className="fixed inset-0 pointer-events-none -z-[1]">
      {/* Layer 1: Charcoal gradient base */}
      <div
        className={`absolute inset-0 ${noCharcoal ? '' : 'fusion-bg-base'}`}
        style={noCharcoal ? { background: '#141414' } : undefined}
      />

      {/* Layer 2: Blurred hero backdrop (atmospheric depth) */}
      {backdropUrl && (
        <div
          className="absolute inset-0"
          style={{
            opacity: bandOffset > 0 ? 0.55 : 0,
            transition: `opacity ${EASE.ambientColor.duration}s ${EASE.ambientColor.ease}`,
          }}
        >
          <img
            src={backdropUrl}
            alt=""
            className="absolute inset-0 w-full fusion-bg-backdrop"
            style={{ height: `${heroHeight || 60}vh` }}
          />
          <div
            className="absolute inset-0"
            style={{
              background: `linear-gradient(to bottom, transparent 0%, transparent 45%, ${noCharcoal ? '#141414' : 'var(--fusion-charcoal-bottom)'} 78%)`,
            }}
          />
        </div>
      )}

      {/* Layer 3: Animated ambient color wash */}
      {(rgbA || rgbB) && (
        <div
          className="absolute inset-x-0 fusion-bg-wash fusion-bg-animate"
          style={{
            height: '62vh',
            top: `${bandOffset}px`,
            opacity: colorA || colorB ? 1 : 0,
            // Set CSS custom properties for the animated gradient
            '--fusion-color-a-r': rgbA?.[0] ?? 0,
            '--fusion-color-a-g': rgbA?.[1] ?? 0,
            '--fusion-color-a-b': rgbA?.[2] ?? 0,
            '--fusion-color-b-r': rgbB?.[0] ?? rgbA?.[0] ?? 0,
            '--fusion-color-b-g': rgbB?.[1] ?? rgbA?.[1] ?? 0,
            '--fusion-color-b-b': rgbB?.[2] ?? rgbA?.[2] ?? 0,
            transition: `opacity ${EASE.ambientColor.duration}s ${EASE.ambientColor.ease}`,
          } as React.CSSProperties}
        />
      )}
    </div>
  );
}
