import { useState } from 'react';
import { motion } from 'framer-motion';
import { SPRING } from '@/lib/design/motion';
import { genre as genreColors } from '@/lib/design/oklch';

interface GenreTileProps {
  name: string;
  onClick: () => void;
}

const TILE_WIDTH = 210;
const TILE_HEIGHT = 168;

const TMDB_POSTER_BASE = 'https://image.tmdb.org/t/p/w342';

const GENRE_BACKDROPS: Record<string, string[]> = {};

export default function GenreTile({ name, onClick }: GenreTileProps) {
  const [hovering, setHovering] = useState(false);
  const colors = genreColors(name);

  return (
    <motion.button
      type="button"
      className="relative flex-shrink-0 cursor-pointer overflow-hidden"
      style={{
        width: TILE_WIDTH,
        height: TILE_HEIGHT,
        borderRadius: 16,
        border: '1px solid rgba(255,255,255,0.10)',
      }}
      animate={{ y: hovering ? -4 : 0 }}
      transition={{ duration: 0.3, ease: 'easeOut' }}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      onClick={onClick}
    >
      <div
        className="absolute inset-0"
        style={{
          background: `linear-gradient(to bottom, ${colors.from}, ${colors.to})`,
        }}
      />

      <div
        className="absolute inset-0"
        style={{
          background: `linear-gradient(to bottom, ${colors.from}, ${colors.from.replace(')', ', 0.55)').replace('rgb(', 'rgba(')}, ${colors.to.replace(')', ', 0.85)').replace('rgb(', 'rgba(')})`,
          mixBlendMode: 'multiply',
        }}
      />

      <div
        className="absolute inset-0"
        style={{
          background: `linear-gradient(to bottom, transparent, ${colors.to})`,
        }}
      />

      <div className="absolute bottom-0 left-0 right-0 px-[18px] pb-[14px] flex items-end justify-between">
        <span
          className="text-[24px] leading-tight line-clamp-1"
          style={{
            fontWeight: 500,
            fontFamily: 'Georgia, serif',
            color: colors.ink,
            textShadow: '0 1px 9px rgba(0,0,0,0.4)',
          }}
        >
          {name}
        </span>
        <motion.span
          className="text-[20px]"
          style={{ color: colors.ink, opacity: 0.8, fontFamily: 'Georgia, serif' }}
          animate={{ x: hovering ? 4 : 0 }}
        >
          &#8250;
        </motion.span>
      </div>

      {hovering && (
        <div
          className="absolute inset-0 rounded-[16px] pointer-events-none"
          style={{
            boxShadow: `0 0 50px 6px ${colors.from.replace(')', ', 0.28)').replace('rgb(', 'rgba(')}`,
          }}
        />
      )}
    </motion.button>
  );
}
