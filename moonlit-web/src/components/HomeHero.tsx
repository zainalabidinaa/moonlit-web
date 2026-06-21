import React from 'react';
import { FeaturedHomeItem, MetaDetail } from '@/lib/types';
import { Link } from '@tanstack/react-router';

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

  // Reset logo error state when featured item changes
  // eslint-disable-next-line react-hooks/rules-of-hooks
  React.useEffect(() => { setLogoFailed(false); }, [featured.item.id]);

  const title = meta?.name || featured.item.name;
  const description = meta?.description || featured.item.description || '';
  const bgImage = meta?.background || backdrops?.[featured.item.id] || featured.item.banner || null;
  const logoSrc = logoFailed ? null : meta?.logo;

  // Genre pills
  const genres = (meta?.genres || featured.item.genres || []).slice(0, 3);
  const releaseInfo = meta?.releaseInfo || featured.item.releaseInfo;
  const rating = meta?.imdbRating || featured.item.imdbRating;
  const typeLabel = featured.item.type
    ? featured.item.type.charAt(0).toUpperCase() + featured.item.type.slice(1)
    : null;

  return (
    <section
      className="relative w-full overflow-hidden"
      style={{ height: 'clamp(520px, 74vh, 800px)' }}
    >
      {/* Background image with crossfade */}
      {bgImage ? (
        <img
          key={bgImage}
          src={bgImage}
          alt=""
          fetchPriority="high"
          className="absolute inset-0 w-full h-full object-cover object-[center_18%] animate-fade-in"
        />
      ) : (
        <div className="absolute inset-0 bg-moonlit-elevated" />
      )}

      {/* Gradients */}
      {/* Left heavy gradient for text legibility */}
      <div className="absolute inset-0 bg-gradient-to-r from-black/95 via-black/55 to-black/10 pointer-events-none" />
      {/* Bottom fade into page */}
      <div className="absolute bottom-0 left-0 right-0 h-56 bg-gradient-to-t from-[#080808] via-[#080808]/60 to-transparent pointer-events-none" />
      {/* Top fade — hero goes behind navbar */}
      <div className="absolute top-0 left-0 right-0 h-36 bg-gradient-to-b from-[#080808]/80 to-transparent pointer-events-none" />

      {/* Content — bottom-left anchored */}
      <div className="absolute bottom-0 left-0 right-0 px-8 md:px-14 pb-16">

        {/* Logo or title */}
        {logoSrc ? (
          <img
            src={logoSrc}
            alt={title}
            onError={() => setLogoFailed(true)}
            className="mb-4 object-contain object-left"
            style={{ maxHeight: 100, maxWidth: 380 }}
          />
        ) : (
          <h1 className="text-5xl md:text-6xl lg:text-7xl font-black text-white mb-4 max-w-2xl leading-[1.02] tracking-tight drop-shadow-2xl">
            {title}
          </h1>
        )}

        {/* Metadata pills row */}
        <div className="flex flex-wrap items-center gap-2 mb-4">
          {typeLabel && (
            <span className="text-[11px] font-bold uppercase tracking-wider text-white/50">{typeLabel}</span>
          )}
          {(typeLabel && genres.length > 0) && <span className="text-white/25 text-xs">·</span>}
          {genres.map((g, i) => (
            <React.Fragment key={g}>
              <span className="text-[11px] font-semibold text-white/50">{g}</span>
              {i < genres.length - 1 && <span className="text-white/25 text-xs">·</span>}
            </React.Fragment>
          ))}
          {releaseInfo && (
            <>
              <span className="text-white/25 text-xs">·</span>
              <span className="text-[11px] font-semibold text-white/50">{releaseInfo}</span>
            </>
          )}
          {rating && (
            <>
              <span className="text-white/25 text-xs">·</span>
              <span className="text-[11px] font-bold text-yellow-400/80">★ {rating}</span>
            </>
          )}
        </div>

        {/* Description */}
        {description && (
          <p className="max-w-md text-sm leading-relaxed text-white/55 mb-7 line-clamp-2">
            {description}
          </p>
        )}

        {/* CTA buttons */}
        <div className="flex items-center gap-3">
          <Link
            to="/browse/$type/$id"
            params={{ type: featured.item.type, id: featured.item.id }}
            className="inline-flex items-center gap-2.5 rounded-full bg-white px-7 py-3 text-[13px] font-bold text-black hover:bg-white/90 active:scale-95 transition-all shadow-lg"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-4 h-4">
              <path d="M8 5v14l11-7z" />
            </svg>
            Watch Now
          </Link>
          <Link
            to="/browse/$type/$id"
            params={{ type: featured.item.type, id: featured.item.id }}
            className="inline-flex items-center gap-2 rounded-full bg-white/10 border border-white/15 backdrop-blur-sm px-6 py-3 text-[13px] font-bold text-white hover:bg-white/18 active:scale-95 transition-all"
          >
            More Info
          </Link>
        </div>
      </div>

      {/* Carousel dots — bottom-center */}
      {featuredItems.length > 1 && (
        <div className="absolute bottom-5 left-0 right-0 flex items-center justify-center gap-1.5 pointer-events-none">
          {featuredItems.map((_, i) => (
            <button
              key={i}
              onClick={() => onIndexChange(i)}
              aria-label={`Go to item ${i + 1}`}
              className={[
                'rounded-full transition-all duration-300 pointer-events-auto',
                i === activeIndex
                  ? 'w-6 h-[3px] bg-white'
                  : 'w-[5px] h-[3px] bg-white/30 hover:bg-white/55',
              ].join(' ')}
            />
          ))}
        </div>
      )}
    </section>
  );
}
