import { useState } from 'react';
import { motion } from 'framer-motion';
import { MoreHorizontal } from 'lucide-react';
import { SPRING } from '@/lib/design/motion';
import { useTileHalo } from '@/lib/design/artwork-color';
import type { ContinueWatchingItem } from '@/lib/types';

interface ContinueWatchingCardProps {
  item: ContinueWatchingItem;
  onClick: () => void;
  onMarkWatched: () => void;
  onRemove: () => void;
  width?: number;
  height?: number;
}

export default function ContinueWatchingCard({
  item,
  onClick,
  onMarkWatched,
  onRemove,
  width = 240,
  height = 135,
}: ContinueWatchingCardProps) {
  const [hovering, setHovering] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const imageUrl = item.background ?? item.poster;
  const haloColor = useTileHalo(imageUrl);

  const episodeLabel =
    item.seasonNumber != null && item.episodeNumber != null
      ? `S${item.seasonNumber} E${item.episodeNumber}`
      : null;

  const minutesRemaining = (() => {
    if (!item.durationMs || item.progressFraction >= 1) return null;
    const remaining = item.durationMs * (1 - item.progressFraction);
    const mins = Math.round(remaining / 60000);
    return mins > 0 ? mins : null;
  })();

  const progressPct = Math.min(100, Math.round(item.progressFraction * 100));

  return (
    <div className="flex flex-col gap-[7px]" style={{ width }}>
      <motion.div
        className="relative cursor-pointer"
        style={{ width, height, borderRadius: 12 }}
        animate={{ scale: hovering ? 1.025 : 1 }}
        transition={SPRING.continueWatching}
        onMouseEnter={() => setHovering(true)}
        onMouseLeave={() => {
          setHovering(false);
          setMenuOpen(false);
        }}
        onClick={onClick}
      >
        {imageUrl ? (
          <img
            src={imageUrl}
            alt={item.name}
            className="w-full h-full object-cover bg-moonlit-elevated"
            style={{ borderRadius: 12 }}
          />
        ) : (
          <div
            className="w-full h-full bg-moonlit-elevated flex items-center justify-center"
            style={{ borderRadius: 12 }}
          >
            <span className="text-white/15 text-lg">▶</span>
          </div>
        )}

        <div
          className="absolute bottom-0 left-0 right-0 h-[40px]"
          style={{
            background: 'linear-gradient(to top, rgba(0,0,0,0.55), transparent)',
            borderBottomLeftRadius: 12,
            borderBottomRightRadius: 12,
          }}
        />

        <div className="absolute bottom-[9px] left-[10px] right-[10px] flex items-center justify-between">
          {episodeLabel && (
            <span className="text-[10px] font-semibold text-white">
              {episodeLabel}
            </span>
          )}
          {minutesRemaining != null && (
            <span className="text-[10px] font-medium text-white/70 ml-auto">
              {minutesRemaining}m left
            </span>
          )}
        </div>

        {hovering && (
          <div className="absolute top-[6px] right-[6px]">
            <button
              type="button"
              className="w-7 h-7 glass-dark-capsule flex items-center justify-center"
              onClick={(e) => {
                e.stopPropagation();
                setMenuOpen((v) => !v);
              }}
              aria-label="More actions"
            >
              <MoreHorizontal size={14} className="text-white/80" />
            </button>
            {menuOpen && (
              <div
                className="absolute right-0 top-full mt-1 w-52 rounded-ml-ctl bg-player-elevated border border-player-edge shadow-ml-panel py-1 z-50"
                onClick={(e) => e.stopPropagation()}
              >
                <button
                  type="button"
                  className="w-full text-left px-3 py-2 text-[13px] text-player-ink hover:bg-white/10"
                  onClick={() => {
                    setMenuOpen(false);
                    onMarkWatched();
                  }}
                >
                  Mark as Watched
                </button>
                <button
                  type="button"
                  className="w-full text-left px-3 py-2 text-[13px] text-player-ink hover:bg-white/10"
                  onClick={() => {
                    setMenuOpen(false);
                    onRemove();
                  }}
                >
                  Remove from Continue Watching
                </button>
              </div>
            )}
          </div>
        )}

        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-white/20 rounded-full overflow-hidden" style={{ marginBottom: -1 }}>
          <div
            className="h-full bg-white rounded-full"
            style={{ width: `${progressPct}%` }}
          />
        </div>

        <div
          className="absolute inset-0 rounded-[12px] pointer-events-none transition-opacity duration-300"
          style={{ opacity: hovering ? 1 : 0 }}
        >
          {haloColor && (
            <>
              <div
                className="absolute rounded-[12px]"
                style={{
                  inset: -22,
                  background: haloColor,
                  filter: 'blur(30px)',
                  opacity: 0.66,
                }}
              />
              <div
                className="absolute rounded-[12px]"
                style={{
                  inset: -46,
                  background: haloColor,
                  filter: 'blur(60px)',
                  opacity: 0.30,
                }}
              />
            </>
          )}
        </div>

        <div
          className="absolute inset-0 rounded-[12px] border pointer-events-none transition-colors duration-300"
          style={{
            borderColor: hovering
              ? 'rgba(255,255,255,0.18)'
              : 'rgba(255,255,255,0.06)',
            borderWidth: 1,
          }}
        />
      </motion.div>

      <p className="text-[13px] font-medium text-white line-clamp-1" style={{ width }}>
        {item.name}
      </p>
    </div>
  );
}
