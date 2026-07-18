import type { MetaPreview, CatalogRow } from '@/lib/types';
import PosterCard from './PosterCard';
import RatingBadge from './RatingBadge';
import { useTileHalo } from '@/lib/design/artwork-color';
import { motion } from 'framer-motion';
import { SPRING, TILE_HOVER_SCALE } from '@/lib/design/motion';
import { useState } from 'react';

interface MediaCardProps {
  item: MetaPreview;
  row?: CatalogRow;
  width?: number;
  height?: number;
  cornerRadius?: number;
  onClick?: () => void;
  onLibraryToggle?: () => void;
}

function isFolder(item: MetaPreview): boolean {
  return item.id.startsWith('folder_');
}

function folderArtURL(item: MetaPreview, _row?: CatalogRow): string | undefined {
  return item.poster;
}

export default function MediaCard({
  item,
  row,
  width,
  height,
  cornerRadius,
  onClick,
  onLibraryToggle,
}: MediaCardProps) {
  if (isFolder(item)) {
    return (
      <FolderCard
        item={item}
        row={row}
        width={width}
        height={height}
        onClick={onClick}
      />
    );
  }
  return (
    <PosterCard
      item={item}
      width={width ?? 154}
      height={height ?? 231}
      onClick={onClick}
      onLibraryToggle={onLibraryToggle}
    />
  );
}

function FolderCard({
  item,
  row,
  width = 160,
  height = 240,
  onClick,
}: {
  item: MetaPreview;
  row?: CatalogRow;
  width?: number;
  height?: number;
  onClick?: () => void;
}) {
  const [hovering, setHovering] = useState(false);
  const artworkUrl = folderArtURL(item, row);
  const haloColor = useTileHalo(artworkUrl);

  return (
    <div className="media-card flex flex-col gap-1" style={{ width }}>
      <motion.div
        className="media-card-inner"
        style={{ width, height, borderRadius: 16 }}
        animate={{ scale: hovering ? TILE_HOVER_SCALE : 1 }}
        transition={SPRING.tileHover}
        onMouseEnter={() => setHovering(true)}
        onMouseLeave={() => setHovering(false)}
        onClick={onClick}
      >
        {artworkUrl ? (
          <img src={artworkUrl} alt={item.name} className="w-full h-full object-cover bg-moonlit-elevated" />
        ) : (
          <div className="w-full h-full bg-moonlit-elevated" />
        )}
        <div className="absolute bottom-0 left-0 right-0 h-1/2 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />

        <div
          className="absolute inset-0 rounded-[16px] pointer-events-none transition-opacity duration-300"
          style={{ opacity: hovering ? 1 : 0 }}
        >
          {haloColor && (
            <>
              <div
                className="absolute rounded-[16px]"
                style={{ inset: -22, background: haloColor, filter: 'blur(30px)', opacity: 0.66 }}
              />
              <div
                className="absolute rounded-[16px]"
                style={{ inset: -46, background: haloColor, filter: 'blur(60px)', opacity: 0.30 }}
              />
            </>
          )}
        </div>

        <div
          className="absolute inset-0 rounded-[16px] border pointer-events-none transition-colors duration-300"
          style={{
            borderColor: hovering ? 'rgba(255,255,255,0.14)' : 'rgba(255,255,255,0.05)',
            borderWidth: 0.75,
          }}
        />
      </motion.div>

      <p className="text-[12px] text-white leading-tight" style={{ width }}>
        <span className="line-clamp-1 block">{item.name}</span>
      </p>
    </div>
  );
}

export function LandscapeCard({
  item,
  width = 240,
  height = 135,
  onClick,
}: {
  item: MetaPreview;
  width?: number;
  height?: number;
  onClick?: () => void;
}) {
  const [hovering, setHovering] = useState(false);
  const artworkUrl = item.banner ?? item.poster;
  const haloColor = useTileHalo(artworkUrl);

  return (
    <div className="media-card" style={{ width }}>
      <motion.div
        className="media-card-inner rounded-ml-lg"
        style={{ width, height }}
        animate={{ scale: hovering ? TILE_HOVER_SCALE : 1 }}
        transition={SPRING.tileHover}
        onMouseEnter={() => setHovering(true)}
        onMouseLeave={() => setHovering(false)}
        onClick={onClick}
      >
        {artworkUrl ? (
          <img src={artworkUrl} alt={item.name} className="w-full h-full object-cover bg-moonlit-elevated" />
        ) : (
          <div className="w-full h-full bg-moonlit-elevated" />
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/10 to-transparent" />

        <p className="absolute bottom-[7px] left-[9px] text-[12px] text-white leading-tight line-clamp-1 max-w-[80%]">
          {item.name}
        </p>

        {item.imdbRating && (
          <div className="absolute top-[6px] right-[6px]">
            <RatingBadge rating={item.imdbRating} compact />
          </div>
        )}

        <div
          className="absolute inset-0 rounded-ml-lg pointer-events-none transition-opacity duration-300"
          style={{ opacity: hovering ? 1 : 0 }}
        >
          {haloColor && (
            <>
              <div
                className="absolute rounded-ml-lg"
                style={{ inset: -22, background: haloColor, filter: 'blur(30px)', opacity: 0.66 }}
              />
              <div
                className="absolute rounded-ml-lg"
                style={{ inset: -46, background: haloColor, filter: 'blur(60px)', opacity: 0.30 }}
              />
            </>
          )}
        </div>

        <div
          className="absolute inset-0 rounded-ml-lg border pointer-events-none transition-colors duration-300"
          style={{
            borderColor: hovering ? 'rgba(255,255,255,0.14)' : 'rgba(255,255,255,0.05)',
            borderWidth: 0.75,
          }}
        />
      </motion.div>
    </div>
  );
}
