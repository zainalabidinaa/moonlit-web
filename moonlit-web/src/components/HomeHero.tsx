import React from 'react';
import { FeaturedHomeItem, MetaDetail } from '@/lib/types';
import { Link } from '@tanstack/react-router';

interface HomeHeroProps {
  featuredItems: FeaturedHomeItem[];
  activeIndex: number;
  metas: Record<string, MetaDetail | null>;
  backdrops?: Record<string, string>;
  awards?: Record<string, string>;
  onIndexChange: (i: number) => void;
  isPaused?: boolean;
  onPauseChange?: (paused: boolean) => void;
}

export function HomeHero({
  featuredItems,
  activeIndex,
  metas,
  backdrops,
  awards = {},
  onIndexChange,
  isPaused = false,
  onPauseChange,
}: HomeHeroProps) {
  const [failedLogoSrc, setFailedLogoSrc] = React.useState<string | null>(null);
  const featured = featuredItems[activeIndex] ?? featuredItems[0];

  if (!featured) return null;
  const meta = metas[featured.item.id] ?? null;

  const title = meta?.name || featured.item.name;
  const description = meta?.description || featured.item.description || '';
  // Addon landscape artwork wins. Enriched metadata and the independently
  // resolved TMDB community backdrop are fallbacks, in that order.
  const bgImage = featured.item.banner || meta?.background || backdrops?.[featured.item.id] || null;
  const logoSrc = [meta?.logo, featured.item.logo].find(source => source && source !== failedLogoSrc) ?? null;
  const awardSummary = awards[featured.item.id] || featured.item.awards;

  const genres = (meta?.genres || featured.item.genres || []);
  const genreLabel = genres[0] || null;
  const releaseInfo = meta?.releaseInfo || featured.item.releaseInfo;
  const rating = meta?.imdbRating || featured.item.imdbRating;

  return (
    <section
      aria-label={`Featured: ${title}`}
      className="home-hero relative w-full overflow-hidden"
      style={{ '--hero-desktop-height': '560px' } as React.CSSProperties}
    >
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
          <>
            <h1 className="sr-only">{title}</h1>
            <img
              src={logoSrc}
              alt={title}
              onError={() => setFailedLogoSrc(logoSrc)}
              className="mb-4 max-h-[120px] max-w-[min(380px,78vw)] object-contain object-left drop-shadow-2xl"
            />
          </>
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
          {awardSummary && (
            <span className="text-[11px] font-semibold text-white/65">{awardSummary}</span>
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
            className="btn-primary inline-flex min-h-11 items-center gap-2.5 !rounded-full text-[15px] !px-6 !py-3"
          >
            {featured.item.type === 'series' ? 'Go to Series' : 'Go to Movie'}
            <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3" className="h-4 w-4">
              <path d="m9 5 7 7-7 7" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </Link>
        </div>
      </div>

      {/* Carousel dots */}
      {featuredItems.length > 1 && (
        <>
          <button
            type="button"
            aria-label="Previous featured title"
            onClick={() => onIndexChange((activeIndex - 1 + featuredItems.length) % featuredItems.length)}
            className="hero-arrow hero-arrow-previous"
          >
            <span aria-hidden="true">‹</span>
          </button>
          <button
            type="button"
            aria-label="Next featured title"
            onClick={() => onIndexChange((activeIndex + 1) % featuredItems.length)}
            className="hero-arrow hero-arrow-next"
          >
            <span aria-hidden="true">›</span>
          </button>
          <div className="absolute bottom-1 left-0 right-0 flex items-center justify-center gap-0.5" aria-label="Featured titles">
            {featuredItems.map((_, i) => {
              const active = i === activeIndex;
              return (
                <button
                  key={i}
                  type="button"
                  onClick={() => onIndexChange(i)}
                  aria-label={`Go to item ${i + 1}`}
                  aria-pressed={active}
                  className="hero-page-button flex h-11 w-11 items-center justify-center rounded-full"
                >
                  <span
                    aria-hidden="true"
                    className="block h-[5px] rounded-full bg-white transition-[width,opacity]"
                    style={{ width: active ? 28 : 8, opacity: active ? 1 : 0.42 }}
                  />
                </button>
              );
            })}
            {onPauseChange && (
              <button
                type="button"
                aria-label={`${isPaused ? 'Resume' : 'Pause'} featured titles`}
                aria-pressed={isPaused}
                onClick={() => onPauseChange(!isPaused)}
                className="hero-page-button flex h-11 w-11 items-center justify-center rounded-full text-sm font-bold text-white/75"
              >
                <span aria-hidden="true">{isPaused ? '▶' : 'Ⅱ'}</span>
              </button>
            )}
          </div>
        </>
      )}
    </section>
  );
}
