import { useState, useEffect, useCallback, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ChevronLeft, ChevronRight, Play, Info } from 'lucide-react';
import { SPRING, EASE } from '@/lib/design/motion';
import { useAmbientColors } from '@/lib/design/artwork-color';
import RatingBadge from './RatingBadge';
import type { MetaPreview } from '@/lib/types';

interface HomeHeroProps {
  items: MetaPreview[];
  onPlay: (item: MetaPreview) => void;
  onDetail: (item: MetaPreview) => void;
  onGenreClick?: (genre: string) => void;
}

const HERO_HEIGHT = 560;

export default function HomeHero({ items, onPlay, onDetail }: HomeHeroProps) {
  const [currentIndex, setCurrentIndex] = useState(0);
  const autoTimer = useRef<ReturnType<typeof setInterval> | undefined>(undefined);

  const currentItem = items[currentIndex];
  const ambient = useAmbientColors(
    currentItem?.background ?? currentItem?.poster
  );

  const prev = useCallback(() => {
    if (items.length <= 1) return;
    setCurrentIndex((i) => (i - 1 + items.length) % items.length);
  }, [items.length]);

  const next = useCallback(() => {
    if (items.length <= 1) return;
    setCurrentIndex((i) => (i + 1) % items.length);
  }, [items.length]);

  useEffect(() => {
    if (items.length <= 1) return;
    autoTimer.current = setInterval(next, 60000);
    return () => {
      if (autoTimer.current != null) { clearInterval(autoTimer.current); autoTimer.current = undefined; }
    };
  }, [items.length, next]);

  const visiblePages = (() => {
    const count = items.length;
    const maxVisible = 9;
    const start =
      count <= maxVisible
        ? 0
        : Math.min(
            Math.max(currentIndex - Math.floor(maxVisible / 2), 0),
            count - maxVisible
          );
    const end = Math.min(start + maxVisible, count);
    return Array.from({ length: count }, (_, i) => i).slice(start, end);
  })();

  if (!currentItem) return null;

  const logoUrl = currentItem.logo;
  const genre = currentItem.genres?.[0];
  const genresFirstTwo = currentItem.genres?.slice(0, 2).join(', ');

  return (
    <div
      className="relative overflow-hidden bg-moonlit-bg"
      style={{ height: HERO_HEIGHT }}
    >
      <div className="absolute inset-0">
        {ambient && (
          <>
            <div
              className="absolute inset-0"
              style={{
                background: `radial-gradient(ellipse at 50% 0%, ${ambient[0]} 0%, ${ambient[0]}22 40%, transparent 90%)`,
                opacity: 0.65,
              }}
            />
            <div
              className="absolute inset-0"
              style={{
                background: `radial-gradient(ellipse at 75% 10%, ${ambient[1]} 0%, transparent 55%)`,
                opacity: 0.40,
              }}
            />
          </>
        )}
      </div>

      <AnimatePresence mode="wait">
        <motion.div
          key={currentItem.id}
          className="absolute inset-0"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={EASE.heroCrossfade}
        >
          {(currentItem.background ?? currentItem.poster) ? (
            <img
              src={currentItem.background ?? currentItem.poster}
              alt=""
              className="w-full h-full object-cover object-top"
              style={{
                maskImage:
                  'linear-gradient(to bottom, rgba(0,0,0,0.92) 0%, rgba(0,0,0,0.88) 30%, rgba(0,0,0,0.35) 75%, transparent 100%)',
                WebkitMaskImage:
                  'linear-gradient(to bottom, rgba(0,0,0,0.92) 0%, rgba(0,0,0,0.88) 30%, rgba(0,0,0,0.35) 75%, transparent 100%)',
              }}
            />
          ) : (
            <div
              className="w-full h-full bg-moonlit-elevated"
              style={{
                maskImage:
                  'linear-gradient(to bottom, rgba(0,0,0,0.92) 0%, rgba(0,0,0,0.88) 30%, rgba(0,0,0,0.35) 75%, transparent 100%)',
                WebkitMaskImage:
                  'linear-gradient(to bottom, rgba(0,0,0,0.92) 0%, rgba(0,0,0,0.88) 30%, rgba(0,0,0,0.35) 75%, transparent 100%)',
              }}
            />
          )}
        </motion.div>
      </AnimatePresence>

      <div className="absolute bottom-0 left-0 right-0 px-[42px]" style={{ paddingBottom: 58 }}>
        <AnimatePresence mode="wait">
          <motion.div
            key={currentItem.id}
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            transition={EASE.heroCrossfade}
          >
            <div className="flex flex-col gap-2 max-w-[580px]">
              {genre && (
                <span className="text-[12px] font-bold tracking-[2px] uppercase text-white mb-1">
                  {genre}
                </span>
              )}

              {logoUrl ? (
                <img
                  src={logoUrl}
                  alt={currentItem.name}
                  className="object-contain"
                  style={{
                    maxWidth: 330,
                    maxHeight: 120,
                    filter: 'drop-shadow(0 3px 8px rgba(0,0,0,0.55))',
                  }}
                />
              ) : (
                <h1
                  className="text-[46px] font-black text-white leading-tight tracking-tight"
                  style={{ textShadow: '0 3px 8px rgba(0,0,0,0.55)' }}
                >
                  {currentItem.name}
                </h1>
              )}

              <div className="flex items-center gap-[9px] text-[13px]">
                {currentItem.imdbRating && (
                  <RatingBadge rating={currentItem.imdbRating} />
                )}
                {currentItem.releaseInfo && (
                  <span className="text-white/60 font-medium">
                    {currentItem.releaseInfo}
                  </span>
                )}
                {genresFirstTwo && (
                  <span className="text-white/60 font-medium">
                    {genresFirstTwo}
                  </span>
                )}
              </div>

              {currentItem.description && (
                <p className="text-[14px] text-white/75 leading-snug max-w-[480px] line-clamp-2 mt-1 mb-1">
                  {currentItem.description}
                </p>
              )}

              <div className="flex gap-3 mt-1">
                <button
                  type="button"
                  className="btn-primary text-[15px] font-bold flex items-center gap-2"
                  onClick={() => onPlay(currentItem)}
                >
                  <Play size={16} className="fill-black" /> Watch Now
                </button>
                <button
                  type="button"
                  className="btn-secondary text-[14px] font-semibold flex items-center gap-2"
                  onClick={() => onDetail(currentItem)}
                >
                  <Info size={16} /> More Info
                </button>
              </div>
            </div>
          </motion.div>
        </AnimatePresence>
      </div>

      {items.length > 1 && (
        <>
          <div className="absolute bottom-[22px] left-1/2 -translate-x-1/2 flex gap-[7px]">
            {visiblePages.map((i) => (
              <motion.div
                key={i}
                className="rounded-full"
                animate={{
                  width: i === currentIndex ? 28 : 8,
                  height: 5,
                  backgroundColor:
                    i === currentIndex
                      ? 'rgba(255,255,255,1)'
                      : 'rgba(255,255,255,0.42)',
                }}
                transition={SPRING.heroAuto}
              />
            ))}
          </div>

          <div className="absolute top-1/2 -translate-y-1/2 left-[16px] right-[16px] flex justify-between pointer-events-none">
            <button
              type="button"
              className="w-8 h-8 glass-dark-capsule flex items-center justify-center opacity-55 hover:opacity-100 transition-opacity pointer-events-auto"
              onClick={prev}
              aria-label="Previous"
            >
              <ChevronLeft size={13} className="text-white" />
            </button>
            <button
              type="button"
              className="w-8 h-8 glass-dark-capsule flex items-center justify-center opacity-55 hover:opacity-100 transition-opacity pointer-events-auto"
              onClick={next}
              aria-label="Next"
            >
              <ChevronRight size={13} className="text-white" />
            </button>
          </div>
        </>
      )}

      <div className="absolute bottom-[64px] right-[42px] pointer-events-none">
        <AwardPlaceholder />
      </div>
    </div>
  );
}

function AwardPlaceholder() {
  return <div className="w-[100px] h-[50px]" />;
}
