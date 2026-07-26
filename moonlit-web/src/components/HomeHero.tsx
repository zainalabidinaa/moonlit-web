import React, { useEffect, useState } from 'react';
import { FeaturedHomeItem, MetaDetail } from '@/lib/types';
import { Link } from '@tanstack/react-router';
import { EASE } from '@/lib/design/motion';

interface HomeHeroProps {
  featuredItems: FeaturedHomeItem[];
  activeIndex: number;
  metas: Record<string, MetaDetail | null>;
  backdrops?: Record<string, string>;
  onIndexChange: (i: number) => void;
}

export function HomeHero({ featuredItems, activeIndex, metas, backdrops, onIndexChange }: HomeHeroProps) {
  const [logoFailed, setLogoFailed] = React.useState(false);

  if (featuredItems.length === 0) return null;

  const featured = featuredItems[activeIndex] ?? featuredItems[0];
  const meta = metas[featured.item.id] ?? null;

  React.useEffect(() => { setLogoFailed(false); }, [featured.item.id]);

  const title = meta?.name || featured.item.name;
  const description = meta?.description || featured.item.description || '';
  const bgImage = meta?.background || backdrops?.[featured.item.id] || featured.item.banner || null;
  const logoSrc = logoFailed ? null : meta?.logo;

  const genres = (meta?.genres || featured.item.genres || []);
  const genreLabel = genres[0] || null;
  const releaseInfo = meta?.releaseInfo || featured.item.releaseInfo;
  const rating = meta?.imdbRating || featured.item.imdbRating;

  return (
    <div className="relative w-full overflow-hidden" style={{ height: 'min(85vh, 700px)' }}>
      {/* Hero backdrop image */}
      {bgImage ? (
        <img
          key={bgImage}
          src={bgImage}
          alt=""
          fetchPriority="high"
          className="absolute inset-0 w-full h-full object-cover object-[center_18%] animate-fade-in"
          style={{
            maskImage: 'linear-gradient(to bottom, black 0%, black 45%, transparent 100%)',
            WebkitMaskImage: 'linear-gradient(to bottom, black 0%, black 45%, transparent 100%)',
          }}
        />
      ) : (
        <div className="absolute inset-0 bg-[#1f1f1f]" />
      )}

      {/* Left vignette for text legibility */}
      <div className="absolute inset-0 bg-gradient-to-r from-[#141414]/95 via-[#141414]/40 to-transparent pointer-events-none" />
      {/* Bottom fade to page */}
      <div className="absolute inset-0 bg-gradient-to-t from-[#141414] via-transparent to-transparent pointer-events-none" />

      {/* Content */}
      <div className="absolute bottom-0 left-0 right-0 px-8 md:px-14 pb-20">
        {genreLabel && (
          <p className="text-[12px] font-bold tracking-[2px] text-white mb-3 uppercase">{genreLabel}</p>
        )}

        {logoSrc ? (
          <img
            src={logoSrc}
            alt={title}
            onError={() => setLogoFailed(true)}
            className="mb-4 object-contain object-left"
            style={{ maxHeight: 120, maxWidth: 380, filter: 'drop-shadow(0 3px 8px rgba(0,0,0,0.55))' }}
          />
        ) : (
          <h1 className="text-[42px] md:text-[52px] font-black text-white mb-4 max-w-2xl leading-[1.02] tracking-tight drop-shadow-2xl">
            {title}
          </h1>
        )}

        <div className="flex flex-wrap items-center gap-1.5 mb-4">
          {genres.length > 0 && (
            <>
              {genres.slice(0, 3).map((g, i) => (
                <React.Fragment key={g}>
                  <span className="text-[11px] font-semibold text-white/50">{g}</span>
                  {i < Math.min(genres.length, 3) - 1 && <span className="text-white/25 text-xs">·</span>}
                </React.Fragment>
              ))}
              {releaseInfo && <span className="text-white/25 text-xs">·</span>}
            </>
          )}
          {releaseInfo && (
            <span className="text-[11px] font-semibold text-white/50">{releaseInfo}</span>
          )}
          {rating && (
            <span className="rating-badge">★ {rating}</span>
          )}
        </div>

        {description && (
          <p className="max-w-[520px] text-[14px] leading-relaxed text-white/75 mb-7 line-clamp-3">
            {description}
          </p>
        )}

        <div className="flex items-center gap-3">
          <Link
            to="/browse/$type/$id"
            params={{ type: featured.item.type, id: featured.item.id }}
            className="btn-primary inline-flex items-center gap-2.5 !rounded text-[15px] !px-7 !py-3"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-4 h-4">
              <path d="M8 5v14l11-7z" />
            </svg>
            Play
          </Link>
          <Link
            to="/browse/$type/$id"
            params={{ type: featured.item.type, id: featured.item.id }}
            className="btn-secondary inline-flex items-center gap-2 !rounded text-[15px] !px-6 !py-3"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="w-5 h-5">
              <circle cx="12" cy="12" r="10" />
              <path d="M12 16v-4M12 8h.01" strokeLinecap="round" />
            </svg>
            More Info
          </Link>
        </div>
      </div>

      {/* Carousel dots */}
      {featuredItems.length > 1 && (
        <div className="absolute bottom-6 left-0 right-0 flex items-center justify-center gap-1.5">
          {featuredItems.map((_, i) => {
            const active = i === activeIndex;
            return (
              <button
                key={i}
                onClick={() => onIndexChange(i)}
                aria-label={`Go to item ${i + 1}`}
                className="rounded-full transition-all duration-300"
                style={{
                  height: 4,
                  width: active ? 24 : 8,
                  backgroundColor: active ? '#e50914' : 'rgba(255,255,255,0.40)',
                }}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
