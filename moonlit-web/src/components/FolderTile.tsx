import { useState } from 'react';
import { Link } from '@tanstack/react-router';
import { motion } from 'framer-motion';
import { Folder } from '@/lib/types';
import { useTileHalo } from '@/lib/design/artwork-color';
import { SPRING, TILE_HOVER_SCALE } from '@/lib/design/motion';

interface FolderTileProps {
  folder: Folder;
  showGlow?: boolean;
}

export function FolderTile({ folder }: FolderTileProps) {
  const [imgSrc, setImgSrc] = useState(folder.cover_image || '');
  const [hovered, setHovered] = useState(false);

  const isLandscape = (folder.tile_shape || '').toUpperCase() === 'LANDSCAPE';
  const width = isLandscape ? 300 : 176;
  const aspectRatio = isLandscape ? '16/9' : '2/3';

  const canSwapGif = folder.focus_gif_enabled && folder.focus_gif;

  const posterUrl = imgSrc || folder.cover_image || undefined;
  const haloColor = useTileHalo(hovered ? posterUrl : undefined);

  function handleEnter() {
    if (canSwapGif) setImgSrc(folder.focus_gif!);
    setHovered(true);
  }

  function handleLeave() {
    if (canSwapGif) setImgSrc(folder.cover_image || '');
    setHovered(false);
  }

  return (
    <motion.div
      whileHover={{ scale: TILE_HOVER_SCALE }}
      transition={SPRING.tileHover}
      className="flex-shrink-0 cursor-pointer"
      style={{ width: `${width}px` }}
    >
      <Link
        to="/collections/$folderId"
        params={{ folderId: folder.id }}
        className="block"
      >
        <div
          className="relative overflow-hidden mb-2 transition-shadow duration-300"
          onMouseEnter={handleEnter}
          onMouseLeave={handleLeave}
          style={{ aspectRatio, borderRadius: isLandscape ? '18px' : '14px' }}
        >
          {/* Artwork halo glow — two layers, opacity transitions on hover */}
          {haloColor && (
            <div
              className="absolute pointer-events-none"
              style={{
                inset: -22,
                borderRadius: isLandscape ? 30 : 26,
                background: haloColor,
                filter: 'blur(30px)',
                opacity: hovered ? 0.66 : 0,
                transition: 'opacity 0.3s ease-out',
              }}
            />
          )}
          {haloColor && (
            <div
              className="absolute pointer-events-none"
              style={{
                inset: -46,
                borderRadius: isLandscape ? 54 : 50,
                background: haloColor,
                filter: 'blur(60px)',
                opacity: hovered ? 0.30 : 0,
                transition: 'opacity 0.3s ease-out',
              }}
            />
          )}

          {/* Card surface */}
          <div
            className="relative w-full h-full bg-moonlit-elevated overflow-hidden border border-white/5 hover:border-white/[0.14] hover:shadow-ml-lift transition-all duration-300"
            style={{ borderRadius: isLandscape ? '18px' : '14px' }}
          >
            {imgSrc ? (
              <img
                src={imgSrc}
                alt={folder.name}
                loading="lazy"
                className="w-full h-full object-cover"
              />
            ) : (
              <div className="w-full h-full flex items-center justify-center">
                <span className="text-xs font-bold text-white/40 text-center px-2">{folder.name}</span>
              </div>
            )}
          </div>
        </div>
        <p className="text-sm font-semibold text-white/80 truncate hover:text-white transition-colors duration-200">
          {folder.name}
        </p>
      </Link>
    </motion.div>
  );
}
