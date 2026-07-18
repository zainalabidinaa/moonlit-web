import { useState } from 'react';
import { motion } from 'framer-motion';
import { Bookmark } from 'lucide-react';
import { SPRING, TILE_HOVER_SCALE } from '@/lib/design/motion';
import { useTileHalo } from '@/lib/design/artwork-color';
import type { MetaPreview } from '@/lib/types';

interface PosterCardProps {
  item: MetaPreview;
  width?: number;
  height?: number;
  onClick?: () => void;
  onLibraryToggle?: () => void;
}

export default function PosterCard({
  item,
  width = 154,
  height = 231,
  onClick,
  onLibraryToggle,
}: PosterCardProps) {
  const [hovering, setHovering] = useState(false);
  const posterUrl = item.poster;
  const haloColor = useTileHalo(posterUrl);

  return (
    <div className="media-card flex flex-col gap-[7px]" style={{ width }}>
      <motion.div
        className="media-card-inner"
        style={{ width, height, borderRadius: 'var(--radius-ml-card, 14px)' }}
        animate={{ scale: hovering ? TILE_HOVER_SCALE : 1 }}
        transition={SPRING.tileHover}
        onMouseEnter={() => setHovering(true)}
        onMouseLeave={() => setHovering(false)}
        onClick={onClick}
      >
        {posterUrl ? (
          <img
            src={posterUrl}
            alt={item.name}
            className="w-full h-full object-cover bg-moonlit-elevated"
          />
        ) : (
          <div className="w-full h-full bg-moonlit-elevated flex items-center justify-center">
            <span className="text-[12px] font-semibold text-white/45 text-center px-2 line-clamp-2">
              {item.name}
            </span>
          </div>
        )}

        <div
          className="absolute inset-0 rounded-ml-card pointer-events-none transition-opacity duration-300"
          style={{ opacity: hovering ? 1 : 0 }}
        >
          {haloColor && (
            <>
              <div
                className="absolute rounded-ml-card"
                style={{
                  inset: -22,
                  background: haloColor,
                  filter: 'blur(30px)',
                  opacity: 0.66,
                }}
              />
              <div
                className="absolute rounded-ml-card"
                style={{
                  inset: -46,
                  background: haloColor,
                  filter: 'blur(60px)',
                  opacity: 0.30,
                }}
              />
            </>
          )}
          <div
            className="absolute inset-0 rounded-ml-card"
            style={{
              background: hovering
                ? 'rgba(0,0,0,0.40)'
                : 'transparent',
              transition: 'background 0.3s',
            }}
          />
        </div>

        <div
          className="absolute inset-0 rounded-ml-card border pointer-events-none transition-colors duration-300"
          style={{
            borderColor: hovering
              ? 'rgba(255,255,255,0.14)'
              : 'rgba(255,255,255,0.05)',
            borderWidth: 0.75,
          }}
        />

        {onLibraryToggle && (
          <button
            type="button"
            className="absolute top-[7px] right-[7px] w-7 h-7 glass-dark-capsule flex items-center justify-center transition-opacity duration-200"
            style={{ opacity: hovering ? 1 : 0 }}
            onClick={(e) => {
              e.stopPropagation();
              onLibraryToggle();
            }}
            aria-label="Toggle library"
          >
            <Bookmark size={13} className="text-white/85" />
          </button>
        )}
      </motion.div>

      <p
        className="text-[13px] font-medium text-white/85 leading-snug transition-colors duration-200"
        style={{ width }}
      >
        <span
          className="line-clamp-2 block"
          style={{ color: hovering ? '#fff' : 'rgba(255,255,255,0.85)' }}
        >
          {item.name}
        </span>
      </p>
    </div>
  );
}
