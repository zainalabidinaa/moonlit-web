import { useState, useRef, useCallback } from 'react';
import { motion } from 'framer-motion';
import { SPRING, TILE_HOVER_SCALE } from '@/lib/design/motion';
import { useTileHalo } from '@/lib/design/artwork-color';
import type { MetaPreview, CatalogRow } from '@/lib/types';

type TileShape = 'poster' | 'landscape' | 'filmCollection';

interface FolderTileProps {
  row: CatalogRow;
  width?: number;
  height?: number;
  onClick?: () => void;
}

export default function FolderTile({ row, width, height, onClick }: FolderTileProps) {
  const shape: TileShape =
    row.tileShape === 'landscape' ? 'landscape' : 'poster';

  const w = width ?? (shape === 'landscape' ? 220 : 140);
  const h = height ?? (shape === 'landscape' ? 124 : 210);

  const artworkUrl = row.coverImage ?? row.items[0]?.poster;
  const haloColor = useTileHalo(artworkUrl);
  const [hovering, setHovering] = useState(false);
  const [showGif, setShowGif] = useState(false);
  const gifTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const gifUrl =
    row.focusGifEnabled && row.focusGif ? row.focusGif : undefined;

  const handleEnter = useCallback(() => {
    setHovering(true);
    if (gifUrl) {
      gifTimer.current = setTimeout(() => setShowGif(true), 500);
    }
  }, [gifUrl]);

  const handleLeave = useCallback(() => {
    setHovering(false);
    setShowGif(false);
    if (gifTimer.current != null) { clearTimeout(gifTimer.current); gifTimer.current = undefined; }
  }, []);

  return (
    <div className="media-card" style={{ width: w }}>
      <motion.div
        className="media-card-inner"
        style={{
          width: w,
          height: h,
          borderRadius: 16,
        }}
        animate={{ scale: hovering ? TILE_HOVER_SCALE : 1 }}
        transition={SPRING.tileHover}
        onMouseEnter={handleEnter}
        onMouseLeave={handleLeave}
        onClick={onClick}
      >
        {artworkUrl ? (
          <img
            src={artworkUrl}
            alt={row.title}
            className="w-full h-full object-cover bg-moonlit-elevated"
          />
        ) : (
          <div className="w-full h-full bg-moonlit-elevated" />
        )}

        {gifUrl && (
          <img
            src={gifUrl}
            alt=""
            className="absolute inset-0 w-full h-full object-cover transition-opacity duration-500"
            style={{ opacity: showGif ? 1 : 0 }}
            data-focus-gif
          />
        )}

        <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-transparent" />

        <p className="absolute bottom-[8px] left-[8px] text-[10px] font-bold text-white line-clamp-2 max-w-[90%]">
          {row.title}
        </p>

        <div
          className="absolute inset-0 rounded-[16px] pointer-events-none transition-opacity duration-300"
          style={{ opacity: hovering ? 1 : 0 }}
        >
          {haloColor && (
            <>
              <div
                className="absolute rounded-[16px]"
                style={{
                  inset: -22,
                  background: haloColor,
                  filter: 'blur(30px)',
                  opacity: 0.66,
                }}
              />
              <div
                className="absolute rounded-[16px]"
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
          className="absolute inset-0 rounded-[16px] border pointer-events-none transition-colors duration-300"
          style={{
            borderColor: row.focusGlowEnabled && hovering
              ? 'rgba(255,255,255,0.48)'
              : hovering
                ? 'rgba(255,255,255,0.14)'
                : 'rgba(255,255,255,0.05)',
            borderWidth: row.focusGlowEnabled && hovering ? 1.5 : 0.75,
          }}
        />
      </motion.div>
    </div>
  );
}
