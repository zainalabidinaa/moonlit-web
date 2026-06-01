'use client';

import { useState } from 'react';
import Link from 'next/link';
import { Folder } from '@/lib/types';

interface FolderTileProps {
  folder: Folder;
  showGlow?: boolean;
}

export function FolderTile({ folder, showGlow = false }: FolderTileProps) {
  const [imgSrc, setImgSrc] = useState(folder.cover_image || '');
  const [glowing, setGlowing] = useState(false);

  const isLandscape = folder.tile_shape === 'LANDSCAPE';
  const width = isLandscape ? 220 : 140;
  const aspectRatio = isLandscape ? '16/9' : '2/3';

  const canSwapGif = folder.focus_gif_enabled && folder.focus_gif;

  function handleEnter() {
    if (canSwapGif) setImgSrc(folder.focus_gif!);
    if (showGlow) setGlowing(true);
  }

  function handleLeave() {
    if (canSwapGif) setImgSrc(folder.cover_image || '');
    if (showGlow) setGlowing(false);
  }

  return (
    <Link
      href={`/collections/${folder.id}`}
      className="flex-shrink-0 group cursor-pointer"
      style={{ width: `${width}px` }}
    >
      <div
        className="relative overflow-hidden rounded-xl mb-2 transition-all duration-300"
        style={{
          aspectRatio,
          boxShadow: glowing ? '0 0 28px 4px rgba(192,132,252,0.45)' : 'none',
        }}
        onMouseEnter={handleEnter}
        onMouseLeave={handleLeave}
      >
        {imgSrc ? (
          <img
            src={imgSrc}
            alt={folder.name}
            loading="lazy"
            className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
          />
        ) : (
          <div className="w-full h-full bg-luna-elevated flex items-center justify-center">
            <span className="text-xs font-bold text-white/40 text-center px-2">{folder.name}</span>
          </div>
        )}
        {/* Hover overlay */}
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/25 transition-colors duration-300 flex items-center justify-center">
          <div className="w-10 h-10 rounded-full bg-white/20 backdrop-blur-sm opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-center justify-center">
            <svg viewBox="0 0 24 24" fill="white" className="w-4 h-4 ml-0.5">
              <polygon points="6,4 20,12 6,20" />
            </svg>
          </div>
        </div>
      </div>
      <p className="text-sm font-semibold text-white/80 truncate group-hover:text-white transition-colors duration-200">
        {folder.name}
      </p>
    </Link>
  );
}
