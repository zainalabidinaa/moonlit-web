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
  heroHeight?: number;
}

export function FusionBackground({ backdropUrl, heroHeight = 0 }: FusionBackgroundProps) {
  const ambient = useAmbientColors(backdropUrl ?? undefined);
  const [colorA, colorB] = ambient ?? [null, null];
  const [bandOffset, setBandOffset] = useState(0);

  useEffect(() => {
    if (!heroHeight) return;
    let ticking = false;
    const onScroll = () => {
      if (!ticking) {
        requestAnimationFrame(() => {
          setBandOffset(Math.max(0, heroHeight - window.scrollY));
          ticking = false;
        });
        ticking = true;
      }
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, [heroHeight]);

  const rgbA = colorA ? hexToRgb(colorA) : null;
  const rgbB = colorB ? hexToRgb(colorB) : null;

  return (
    <div className="pointer-events-none fixed inset-0 z-0">
      {/* Layer 1: Charcoal gradient base */}
      <div className="fusion-bg" style={{ zIndex: -2 }} />

      {/* Layer 2: Blurred hero backdrop for depth */}
      {backdropUrl && (
        <div className="absolute inset-0" style={{ opacity: bandOffset > 0 ? 0.45 : 0, transition: `opacity ${EASE.ambientColor.duration}s ${EASE.ambientColor.ease}` }}>
          <img src={backdropUrl} alt="" className="absolute inset-0 w-full object-cover" style={{ height: `${heroHeight || 60}vh`, filter: 'blur(30px) saturate(0.28) brightness(0.12)' }} />
          <div className="absolute inset-0" style={{ background: `linear-gradient(to bottom, transparent 0%, transparent 40%, var(--fusion-bot) 78%)` }} />
        </div>
      )}

      {/* Layer 3: Animated ambient color wash */}
      {rgbA && (
        <div
          className="fusion-bg-wash fusion-wash-animate"
          style={{
            top: `${bandOffset}px`,
            height: '62vh',
            opacity: 1,
            '--wash-a-r': rgbA[0], '--wash-a-g': rgbA[1], '--wash-a-b': rgbA[2],
            '--wash-b-r': rgbB?.[0] ?? rgbA[0], '--wash-b-g': rgbB?.[1] ?? rgbA[1], '--wash-b-b': rgbB?.[2] ?? rgbA[2],
          } as React.CSSProperties}
        />
      )}
    </div>
  );
}
