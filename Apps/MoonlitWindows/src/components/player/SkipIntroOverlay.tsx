import { useEffect, useState } from 'react';
import { fetchIntroTimestamps } from '@/lib/player/intro-timestamps';

interface SkipIntroOverlayProps {
  position: number;
  duration: number;
  imdbId?: string;
  season?: number;
  episode?: number;
  autoSkip?: boolean;
  fallbackEnabled?: boolean;
  fallbackSeconds?: number;
  onSkip: (targetTime: number) => void;
}

export function SkipIntroOverlay({
  position, duration, imdbId,
  season, episode,
  autoSkip = false,
  fallbackEnabled = true,
  fallbackSeconds = 85,
  onSkip,
}: SkipIntroOverlayProps) {
  const [introRange, setIntroRange] = useState<{ start: number; end: number } | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!imdbId) return;
    setLoading(true);
    fetchIntroTimestamps(imdbId, season, episode)
      .then(data => { setIntroRange(data); setLoading(false); })
      .catch(() => setLoading(false));
  }, [imdbId, season, episode]);

  // Auto-skip
  useEffect(() => {
    if (!autoSkip || !introRange) return;
    if (position >= introRange.start && position < introRange.end) {
      onSkip(introRange.end);
    }
  }, [position, autoSkip, introRange, onSkip]);

  const inIntro = introRange
    ? position >= introRange.start && position < introRange.end
    : false;

  // Fallback skip: show between 15s and 300s when no intro timestamps
  const showFallback = !introRange && fallbackEnabled && position >= 15 && position < 300;

  if (loading) return null;
  if (!inIntro && !showFallback) return null;

  return (
    <button
      onClick={() => {
        if (inIntro && introRange) {
          onSkip(introRange.end);
        } else if (showFallback) {
          onSkip(position + fallbackSeconds);
        }
      }}
      className="absolute bottom-24 right-6 z-40 flex items-center gap-2 rounded-full bg-white/15 backdrop-blur-xl border border-white/20 px-4 py-2.5 text-white text-sm font-semibold hover:bg-white/25 transition-all cursor-pointer"
    >
      Skip {inIntro ? 'Intro' : `+${fallbackSeconds}s`}
    </button>
  );
}
