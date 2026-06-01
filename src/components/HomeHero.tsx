'use client';

import React from 'react';
import { FeaturedHomeItem, MetaDetail } from '@/lib/types';
import Link from 'next/link';

interface HomeHeroProps {
  featuredItems: FeaturedHomeItem[];
  activeIndex: number;
  metas: Record<string, MetaDetail | null>;
  onIndexChange: (i: number) => void;
}

export function HomeHero({ featuredItems, activeIndex, metas, onIndexChange }: HomeHeroProps) {
  if (featuredItems.length === 0) return null;

  const featured = featuredItems[activeIndex] ?? featuredItems[0];
  const meta = metas[featured.item.id] ?? null;

  const title = meta?.name || featured.item.name;
  const description = meta?.description || featured.item.description || '';
  const bgImage = meta?.background || featured.item.banner || featured.item.poster || null;

  const metaParts: string[] = [];
  if (featured.item.type) {
    metaParts.push(featured.item.type.charAt(0).toUpperCase() + featured.item.type.slice(1));
  }
  const genres = meta?.genres || featured.item.genres;
  if (genres?.length) {
    metaParts.push(...genres.slice(0, 2));
  }
  const release = meta?.releaseInfo || featured.item.releaseInfo;
  if (release) metaParts.push(release);
  const rating = meta?.imdbRating || featured.item.imdbRating;
  if (rating) metaParts.push(`★ ${rating}`);

  const logoSrc = meta?.logo;

  return (
    <section
      className="relative w-full overflow-hidden"
      style={{ height: 'clamp(420px, 60vh, 680px)' }}
    >
      {bgImage ? (
        <img
          src={bgImage}
          alt=""
          fetchPriority="high"
          className="absolute inset-0 w-full h-full object-cover object-[center_20%]"
        />
      ) : (
        <div className="absolute inset-0 bg-luna-elevated" />
      )}

      {/* Top fade — blurs image into page bg, hides navbar overlap */}
      <div
        className="absolute top-0 left-0 right-0 h-32 bg-gradient-to-b from-[#080808] to-transparent"
        style={{ pointerEvents: 'none' }}
      />
      {/* Left-to-right gradient */}
      <div
        className="absolute inset-0 bg-gradient-to-r from-black/90 via-black/50 to-transparent"
        style={{ pointerEvents: 'none' }}
      />
      {/* Bottom fade into page bg */}
      <div
        className="absolute bottom-0 left-0 right-0 h-40 bg-gradient-to-t from-[#080808] via-transparent to-transparent"
        style={{ pointerEvents: 'none' }}
      />

      {/* Content anchored to bottom-left */}
      <div className="absolute bottom-0 left-0 right-0 p-8 md:p-12 pb-14">
        {/* Row source label */}
        <p className="text-xs font-bold uppercase tracking-widest text-luna-accent mb-3">
          {featured.row.title}
        </p>

        {/* Logo or title */}
        {logoSrc ? (
          <img
            src={logoSrc}
            alt={title}
            className="h-14 sm:h-20 object-contain object-left mb-4"
          />
        ) : (
          <h1 className="text-4xl md:text-5xl lg:text-6xl font-black text-white mb-3 max-w-2xl leading-[1.05] tracking-tight">
            {title}
          </h1>
        )}

        {/* Meta line */}
        {metaParts.length > 0 && (
          <p className="text-sm text-white/60 mb-4">
            {metaParts.join(' · ')}
          </p>
        )}

        {/* Description */}
        {description && (
          <p className="max-w-lg text-sm leading-relaxed text-white/60 mb-6 line-clamp-2">
            {description}
          </p>
        )}

        {/* Buttons row */}
        <div className="flex items-center gap-3">
          <Link
            href={`/browse/${featured.item.type}/${featured.item.id}`}
            className="inline-flex items-center gap-2 rounded-full bg-white px-6 py-3 text-sm font-bold text-black hover:bg-white/90 transition-colors"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="currentColor"
              className="w-4 h-4"
            >
              <path d="M8 5v14l11-7z" />
            </svg>
            Watch Now
          </Link>
          <Link
            href={`/browse/${featured.item.type}/${featured.item.id}`}
            className="inline-flex items-center gap-2 rounded-full bg-white/10 border border-white/15 backdrop-blur-sm px-6 py-3 text-sm font-bold text-white hover:bg-white/20 transition-colors"
          >
            + My List
          </Link>
        </div>
      </div>

      {/* Rotation dots */}
      {featuredItems.length > 1 && (
        <div className="absolute bottom-5 right-8 flex items-center gap-1.5">
          {featuredItems.map((_, i) => (
            <button
              key={i}
              onClick={() => onIndexChange(i)}
              aria-label={`Go to item ${i + 1}`}
              className={[
                'rounded-full transition-all duration-300',
                i === activeIndex
                  ? 'w-6 h-[3px] bg-white'
                  : 'w-1.5 h-[3px] bg-white/30 hover:bg-white/50',
              ].join(' ')}
            />
          ))}
        </div>
      )}
    </section>
  );
}
