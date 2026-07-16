import React, { useEffect, useState } from 'react';
import { FeaturedHomeItem, MetaDetail } from '@/lib/types';
import { Link } from '@tanstack/react-router';
import { motion } from 'framer-motion';
import { useAmbientColors } from '@/lib/design/artwork-color';
import { EASE, SPRING } from '@/lib/design/motion';

interface HomeHeroProps {
  featuredItems: FeaturedHomeItem[];
  activeIndex: number;
  metas: Record<string, MetaDetail | null>;
  backdrops?: Record<string, string>;
  onIndexChange: (i: number) => void;
}

export function HomeHero({ featuredItems, activeIndex, metas, backdrops, onIndexChange }: HomeHeroProps) {
  const [logoFailed, setLogoFailed] = React.useState(false);
  const [scrollY, setScrollY] = useState(0);
  const prefersReducedMotion = typeof window !== 'undefined'
    && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  useEffect(() => {
    if (prefersReducedMotion) return;

    let ticking = false;
    const handleScroll = () => {
      if (!ticking) {
        requestAnimationFrame(() => {
          setScrollY(window.scrollY);
          ticking = false;
        });
        ticking = true;
      }
    };
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, [prefersReducedMotion]);

  if (featuredItems.length === 0) return null;

  const featured = featuredItems[activeIndex] ?? featuredItems[0];
  const meta = metas[featured.item.id] ?? null;

  // Reset logo error state when featured item changes
  // eslint-disable-next-line react-hooks/rules-of-hooks
  React.useEffect(() => { setLogoFailed(false); }, [featured.item.id]);

  const title = meta?.name || featured.item.name;
  const description = meta?.description || featured.item.description || '';
  const bgImage = meta?.background || backdrops?.[featured.item.id] || featured.item.banner || null;
  const logoSrc = logoFailed ? null : meta?.logo;

  // Genre label (first genre, Mac style)
  const genres = (meta?.genres || featured.item.genres || []);
  const genreLabel = genres[0] || null;
  const releaseInfo = meta?.releaseInfo || featured.item.releaseInfo;
  const rating = meta?.imdbRating || featured.item.imdbRating;
  const typeLabel = featured.item.type
    ? featured.item.type.charAt(0).toUpperCase() + featured.item.type.slice(1)
    : null;

  // Ambient colors from backdrop
  const ambient = useAmbientColors(bgImage ?? undefined);
  const [colorA, colorB] = ambient ?? [null, null];

  // Parallax transforms
  const heroHeight = typeof window !== 'undefined'
    ? Math.min(800, Math.max(520, window.innerHeight * 0.74))
    : 600;
  const parallaxBgY = prefersReducedMotion ? 0 : scrollY * 0.4;
  const parallaxContentY = prefersReducedMotion ? 0 : scrollY * 0.15;
  const heroOpacity = Math.max(0, Math.min(1, 1 - scrollY / (heroHeight * 0.7)));

  return (
    <div className="relative w-full overflow-hidden" style={{ height: heroHeight }}>
      {/* Ambient radial gradients behind content */}
      {(colorA || colorB) && (
        <div
          className="absolute inset-0 pointer-events-none"
          style={{ transition: `opacity ${EASE.ambientColor.duration}s ${EASE.ambientColor.ease}` }}
        >
          {colorA && (
            <div
              className="absolute inset-0"
              style={{
                background: `radial-gradient(ellipse at top, ${colorA}26, transparent 65%)`,
                transition: `background ${EASE.ambientColor.duration}s ${EASE.ambientColor.ease}`,
              }}
            />
          )}
          {colorB && (
            <div
              className="absolute inset-0"
              style={{
                background: `radial-gradient(ellipse at right, ${colorB}1f, transparent 65%)`,
                transition: `background ${EASE.ambientColor.duration}s ${EASE.ambientColor.ease}`,
              }}
            />
          )}
        </div>
      )}

      {/* Background image with parallax, crossfade, and fade mask */}
      {bgImage ? (
        <img
          key={bgImage}
          src={bgImage}
          alt=""
          fetchPriority="high"
          className="absolute inset-0 w-full h-full object-cover object-[center_18%] animate-fade-in"
          style={{
            transform: `translateY(${parallaxBgY}px) scale(1.08)`,
            height: `calc(100% + 80px)`,
            maskImage: 'linear-gradient(to bottom, rgba(0,0,0,0.92), rgba(0,0,0,0.88) 30%, rgba(0,0,0,0.35) 75%, transparent)',
            WebkitMaskImage: 'linear-gradient(to bottom, rgba(0,0,0,0.92), rgba(0,0,0,0.88) 30%, rgba(0,0,0,0.35) 75%, transparent)',
          }}
        />
      ) : (
        <div className="absolute inset-0 bg-moonlit-elevated" />
      )}

      {/* Left heavy gradient for text legibility */}
      <div className="absolute inset-0 bg-gradient-to-r from-black/95 via-black/55 to-transparent pointer-events-none" />
      {/* Top fade — hero goes behind navbar */}
      <div className="absolute top-0 left-0 right-0 h-36 bg-gradient-to-b from-[#080808]/80 to-transparent pointer-events-none" />

      {/* Content — bottom-left anchored, parallax */}
      <div
        className="absolute bottom-0 left-0 right-0 px-8 md:px-14 pb-16"
        style={{ transform: `translateY(${parallaxContentY}px)`, opacity: heroOpacity }}
      >
        {/* Genre label */}
        {genreLabel && (
          <p className="text-[12px] font-bold tracking-[2px] text-white mb-3 uppercase">{genreLabel}</p>
        )}

        {/* Logo or title */}
        {logoSrc ? (
          <img
            src={logoSrc}
            alt={title}
            onError={() => setLogoFailed(true)}
            className="mb-4 object-contain object-left"
            style={{ maxHeight: 120, maxWidth: 330, filter: 'drop-shadow(0 3px 8px rgba(0,0,0,0.55))' }}
          />
        ) : (
          <h1 className="text-[46px] font-black text-white mb-4 max-w-2xl leading-[1.02] tracking-tight drop-shadow-2xl">
            {title}
          </h1>
        )}

        {/* Metadata pills row */}
        <div className="flex flex-wrap items-center gap-1.5 mb-4">
          {typeLabel && (
            <span className="text-[11px] font-bold uppercase tracking-wider text-white/50">{typeLabel}</span>
          )}
          {(typeLabel && genres.length > 1) && <span className="text-white/25 text-xs">·</span>}
          {genres.slice(1).map((g, i) => (
            <React.Fragment key={g}>
              <span className="text-[11px] font-semibold text-white/50">{g}</span>
              {i < genres.slice(1).length - 1 && <span className="text-white/25 text-xs">·</span>}
            </React.Fragment>
          ))}
          {releaseInfo && (
            <>
              {(typeLabel || genres.length > 1) && <span className="text-white/25 text-xs">·</span>}
              <span className="text-[11px] font-semibold text-white/50">{releaseInfo}</span>
            </>
          )}
          {rating && (
            <span className="rating-badge">★ {rating}</span>
          )}
        </div>

        {/* Description */}
        {description && (
          <p className="max-w-[480px] text-[14px] leading-relaxed text-white/75 mb-7 line-clamp-2">
            {description}
          </p>
        )}

        {/* CTA buttons */}
        <div className="flex items-center gap-3">
          <Link
            to="/browse/$type/$id"
            params={{ type: featured.item.type, id: featured.item.id }}
            className="btn-primary inline-flex items-center gap-2.5 !rounded-full text-[15px] !px-7 !py-3"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-4 h-4">
              <path d="M8 5v14l11-7z" />
            </svg>
            Watch Now
          </Link>
          <Link
            to="/browse/$type/$id"
            params={{ type: featured.item.type, id: featured.item.id }}
            className="btn-secondary inline-flex items-center gap-2 !rounded-full text-[15px] !px-6 !py-3"
          >
            More Info
          </Link>
        </div>
      </div>

      {/* Carousel dots — bottom-center */}
      {featuredItems.length > 1 && (
        <div className="absolute bottom-5 left-0 right-0 flex items-center justify-center gap-1.5 pointer-events-none">
          {featuredItems.map((_, i) => {
            const active = i === activeIndex;
            return (
              <motion.button
                key={i}
                onClick={() => onIndexChange(i)}
                layout
                aria-label={`Go to item ${i + 1}`}
                className="rounded-full pointer-events-auto"
                style={{
                  height: 5,
                  width: active ? 28 : 8,
                  backgroundColor: active ? '#FFFFFF' : 'rgba(255,255,255,0.40)',
                }}
                transition={SPRING.nav}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
