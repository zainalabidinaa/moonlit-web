import React, { useEffect, useState } from 'react';
import { FeaturedHomeItem, MetaDetail } from '@/lib/types';
import { Link } from '@tanstack/react-router';
import { EASE } from '@/lib/design/motion';
import { useAmbientColors } from '@/lib/design/artwork-color';

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
  const prefersReducedMotion = typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  useEffect(() => {
    if (prefersReducedMotion) return;
    let ticking = false;
    const onScroll = () => {
      if (!ticking) { requestAnimationFrame(() => { setScrollY(window.scrollY); ticking = false; }); ticking = true; }
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, [prefersReducedMotion]);

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
  const ambient = useAmbientColors(bgImage ?? undefined);

  const heroHeight = typeof window !== 'undefined' ? Math.min(800, Math.max(520, window.innerHeight * 0.72)) : 600;
  const parallaxBgY = prefersReducedMotion ? 0 : scrollY * 0.4;
  const parallaxContentY = prefersReducedMotion ? 0 : scrollY * 0.15;
  const heroOpacity = Math.max(0, Math.min(1, 1 - scrollY / (heroHeight * 0.7)));

  return (
    <div className="relative w-full overflow-hidden" style={{ height: heroHeight }}>
      {/* Ambient color washes over the hero area */}
      {ambient && (
        <div className="absolute inset-0 pointer-events-none" style={{ opacity: 0.35, transition: `opacity ${EASE.ambientColor.duration}s ${EASE.ambientColor.ease}` }}>
          <div className="absolute inset-0" style={{ background: `radial-gradient(ellipse at top, ${ambient[0]}40, transparent 65%)`, transition: `background ${EASE.ambientColor.duration}s ${EASE.ambientColor.ease}` }} />
          <div className="absolute inset-0" style={{ background: `radial-gradient(ellipse at right, ${ambient[1]}30, transparent 65%)`, transition: `background ${EASE.ambientColor.duration}s ${EASE.ambientColor.ease}` }} />
        </div>
      )}

      {bgImage ? (
        <img key={bgImage} src={bgImage} alt="" fetchPriority="high"
          className="absolute inset-0 w-full animate-fade-in"
          style={{
            transform: `translateY(${parallaxBgY}px) scale(1.05)`,
            height: 'calc(100% + 60px)',
            objectFit: 'cover', objectPosition: 'center 18%',
            maskImage: 'linear-gradient(to bottom, black 40%, transparent 100%)',
            WebkitMaskImage: 'linear-gradient(to bottom, black 40%, transparent 100%)',
          }}
        />
      ) : (
        <div className="absolute inset-0 bg-moonlit-elevated" />
      )}

      <div className="absolute inset-0 bg-gradient-to-r from-[#0D0D0D]/95 via-[#0D0D0D]/45 to-transparent pointer-events-none" />
      <div className="absolute top-0 left-0 right-0 h-40 bg-gradient-to-b from-[#0D0D0D]/80 to-transparent pointer-events-none" />

      <div className="absolute bottom-0 left-0 right-0 px-8 md:px-14 pb-14" style={{ transform: `translateY(${parallaxContentY}px)`, opacity: heroOpacity }}>
        {genreLabel && <p className="text-[12px] font-bold tracking-[3px] text-white mb-3 uppercase">{genreLabel}</p>}

        {logoSrc ? (
          <img src={logoSrc} alt={title} onError={() => setLogoFailed(true)}
            className="mb-4 object-contain object-left" style={{ maxHeight: 120, maxWidth: 350, filter: 'drop-shadow(0 3px 8px rgba(0,0,0,0.55))' }} />
        ) : (
          <h1 className="text-[44px] font-black text-white mb-4 max-w-2xl leading-[1.02] tracking-tight drop-shadow-2xl">{title}</h1>
        )}

        <div className="flex flex-wrap items-center gap-1.5 mb-4">
          {genres.slice(0, 3).map((g, i) => (
            <React.Fragment key={g}>
              <span className="text-[11px] font-semibold text-white/50">{g}</span>
              {i < Math.min(genres.length, 3) - 1 && <span className="text-white/25 text-xs">·</span>}
            </React.Fragment>
          ))}
          {releaseInfo && <><span className="text-white/25 text-xs">·</span><span className="text-[11px] font-semibold text-white/50">{releaseInfo}</span></>}
          {rating && <span className="rating-badge">★ {rating}</span>}
        </div>

        {description && <p className="max-w-[460px] text-[14px] leading-relaxed text-white/75 mb-7 line-clamp-3">{description}</p>}

        <div className="flex items-center gap-3">
          <Link to="/browse/$type/$id" params={{ type: featured.item.type, id: featured.item.id }} className="btn-primary">
            <svg viewBox="0 0 24 24" fill="currentColor" className="w-4 h-4"><path d="M8 5v14l11-7z" /></svg> Watch Now
          </Link>
          <Link to="/browse/$type/$id" params={{ type: featured.item.type, id: featured.item.id }} className="btn-secondary">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="w-5 h-5"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01" strokeLinecap="round"/></svg> More Info
          </Link>
        </div>
      </div>

      {featuredItems.length > 1 && (
        <div className="absolute bottom-5 left-0 right-0 flex items-center justify-center gap-1.5">
          {featuredItems.map((_, i) => (
            <button key={i} onClick={() => onIndexChange(i)} aria-label={`Item ${i + 1}`}
              className="rounded-full transition-all duration-300"
              style={{ height: 5, width: i === activeIndex ? 28 : 8, backgroundColor: i === activeIndex ? '#FFFFFF' : 'rgba(255,255,255,0.40)' }} />
          ))}
        </div>
      )}
    </div>
  );
}
