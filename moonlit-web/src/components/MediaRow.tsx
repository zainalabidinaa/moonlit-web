import {
  useEffect,
  useId,
  useRef,
  useState,
  type CSSProperties,
  type MouseEvent,
} from 'react';
import { Link } from '@tanstack/react-router';

import { useTileHalo } from '@/lib/design/artwork-color';
import {
  DEFAULT_ARTWORK_PREFERENCES,
  type ArtworkPreferences,
} from '@/lib/preferences/profile-preferences';
import type { MetaPreview } from '@/lib/types';

export type MediaRailVariant =
  | 'standard'
  | 'cinematic'
  | 'banner'
  | 'stack'
  | 'carousel'
  | 'top10'
  | 'continue';

export interface MediaBadgeVisibility {
  trend?: boolean;
  quality?: boolean;
  genre?: boolean;
  rating?: boolean;
  age?: boolean;
}

export interface MediaProgress {
  fraction: number;
  label?: string;
  episodeLabel?: string;
}

interface MediaCardProps {
  item: MetaPreview;
  index?: number;
  variant?: MediaRailVariant;
  artworkPreferences?: ArtworkPreferences;
  badges?: MediaBadgeVisibility;
  progress?: MediaProgress;
  onActivate?: (item: MetaPreview) => void;
  onRemove?: (item: MetaPreview) => void;
  removeFromLabel?: string;
}

const posterWidth = 154;
const posterHeight = 231;

function rounded(value: number): number {
  return Number(value.toFixed(1));
}

function cardGeometry(variant: MediaRailVariant, scale: number, index: number) {
  if (variant === 'standard' || variant === 'top10') {
    return { width: rounded(posterWidth * scale), height: rounded(posterHeight * scale), shape: 'poster' };
  }
  if (variant === 'cinematic') return { width: rounded(360 * scale), height: rounded(203 * scale), shape: 'landscape' };
  if (variant === 'carousel') {
    const width = index === 0 ? 420 : 320;
    return { width: rounded(width * scale), height: rounded((width / 16) * 9 * scale), shape: 'landscape' };
  }
  if (variant === 'stack') return { width: rounded(270 * scale), height: rounded(152 * scale), shape: 'landscape' };
  return { width: rounded(320 * scale), height: rounded(180 * scale), shape: 'landscape' };
}

function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

export function MediaCard({
  item,
  index = 0,
  variant = 'standard',
  artworkPreferences = DEFAULT_ARTWORK_PREFERENCES,
  badges = { rating: true },
  progress,
  onActivate,
  onRemove,
  removeFromLabel = 'watchlist',
}: MediaCardProps) {
  const [failedArtworkKey, setFailedArtworkKey] = useState<string | null>(null);
  const [previewItemId, setPreviewItemId] = useState<string | null>(null);
  const previewTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const geometry = cardGeometry(variant, artworkPreferences.posterScale, index);
  const isLandscape = geometry.shape === 'landscape';
  const artwork = (isLandscape ? item.banner || item.poster : item.poster || item.banner) ?? undefined;
  const artworkKey = `${item.id}|${artwork ?? ''}`;
  const imageFailed = failedArtworkKey === artworkKey;
  const showPreview = previewItemId === item.id;
  const halo = useTileHalo(artworkPreferences.artworkHaloEnabled ? artwork : undefined);
  const previewAvailable = Boolean(
    artworkPreferences.hoverPreviewEnabled && item.previewVideo && !prefersReducedMotion(),
  );

  useEffect(() => () => {
    if (previewTimer.current) clearTimeout(previewTimer.current);
  }, []);

  function handleEnter() {
    if (!previewAvailable) return;
    previewTimer.current = setTimeout(
      () => setPreviewItemId(item.id),
      artworkPreferences.hoverPreviewDelaySeconds * 1000,
    );
  }

  function handleLeave() {
    if (previewTimer.current) clearTimeout(previewTimer.current);
    previewTimer.current = null;
    setPreviewItemId(null);
  }

  const style = {
    '--media-card-width': `${geometry.width}px`,
    '--media-card-height': `${geometry.height}px`,
    '--media-card-radius': `${artworkPreferences.posterRadius}px`,
    '--media-card-halo': halo ?? 'transparent',
  } as CSSProperties;

  const className = `media-card-link group ${artworkPreferences.artworkHaloEnabled ? 'artwork-halo' : ''}`;
  const content = (
    <>
      <span className="media-card-art">
        {artwork && !imageFailed ? (
          <img
            src={artwork}
            alt=""
            loading="lazy"
            onError={() => setFailedArtworkKey(artworkKey)}
          />
        ) : (
          <span className="media-card-placeholder">{item.name}</span>
        )}
        {showPreview && item.previewVideo && (
          <video
            aria-label={`Preview ${item.name}`}
            src={item.previewVideo}
            autoPlay
            muted
            loop
            playsInline
            preload="metadata"
          />
        )}
        <span className="media-card-badges">
          {badges.trend && <span className="media-badge media-badge-trend">#{index + 1}</span>}
          {badges.quality && item.quality && <span className="media-badge">{item.quality}</span>}
          {badges.genre && item.genres?.[0] && <span className="media-badge">{item.genres[0]}</span>}
          {badges.rating && item.imdbRating && <span className="media-badge media-badge-rating">★ {item.imdbRating}</span>}
          {badges.age && item.ageRating && <span className="media-badge">{item.ageRating}</span>}
        </span>
        {variant === 'top10' && <span className="media-top-rank">{index + 1}</span>}
        {progress && (
          <>
            <span className="media-progress-copy">
              <span>{progress.episodeLabel}</span>
              <span>{progress.label}</span>
            </span>
            <span
              role="progressbar"
              aria-label={`${item.name} progress`}
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={Math.round(Math.max(0, Math.min(1, progress.fraction)) * 100)}
              className="media-progress-track"
            >
              <span style={{ width: `${Math.max(0, Math.min(1, progress.fraction)) * 100}%` }} />
            </span>
          </>
        )}
      </span>
      <span className="media-card-title">{item.name}</span>
      {item.releaseInfo && <span className="media-card-subtitle">{item.releaseInfo}</span>}
    </>
  );

  return (
    <article className={`media-card-shell media-card-${variant}`} style={style}>
      {onActivate ? (
        <button
          type="button"
          data-media-card={geometry.shape}
          className={className}
          style={style}
          onClick={() => onActivate(item)}
          onMouseEnter={handleEnter}
          onMouseLeave={handleLeave}
        >
          {content}
        </button>
      ) : (
        <Link
          to="/browse/$type/$id"
          params={{ type: item.type, id: item.id }}
          data-media-card={geometry.shape}
          className={className}
          style={style}
          onMouseEnter={handleEnter}
          onMouseLeave={handleLeave}
        >
          {content}
        </Link>
      )}
      {onRemove && (
        <button
          type="button"
          className="media-card-remove"
          aria-label={`Remove ${item.name} from ${removeFromLabel}`}
          onClick={(event: MouseEvent<HTMLButtonElement>) => {
            event.preventDefault();
            onRemove(item);
          }}
        >
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="m7 7 10 10M17 7 7 17" strokeLinecap="round" />
          </svg>
        </button>
      )}
    </article>
  );
}

interface MediaRowProps {
  title: string;
  items: MetaPreview[];
  viewAllHref?: string;
  titleLogo?: string;
  variant?: MediaRailVariant;
  artworkPreferences?: ArtworkPreferences;
  badges?: MediaBadgeVisibility;
  progressById?: Record<string, MediaProgress>;
  onItemActivate?: (item: MetaPreview) => void;
  onRemove?: (item: MetaPreview) => void;
  removeFromLabel?: string;
}

export function MediaRow({
  title,
  items,
  viewAllHref,
  titleLogo,
  variant = 'standard',
  artworkPreferences,
  badges,
  progressById = {},
  onItemActivate,
  onRemove,
  removeFromLabel,
}: MediaRowProps) {
  const reactId = useId();
  const headingId = `media-row-${reactId.replace(/:/g, '')}`;

  return (
    <section
      aria-labelledby={headingId}
      data-rail-variant={variant}
      className={`media-rail media-rail-${variant}`}
    >
      <div className="media-rail-heading">
        {titleLogo ? (
          <h2 id={headingId}>
            <img src={titleLogo} alt={title} className="h-6 object-contain object-left" />
          </h2>
        ) : (
          <h2 id={headingId}>{title}</h2>
        )}
        {viewAllHref && (
          <Link to={viewAllHref as never} className="media-rail-explore">
            See all <span aria-hidden="true">→</span>
          </Link>
        )}
      </div>
      {items.length > 0 ? (
        <div className="media-rail-track scrollbar-hide">
          {items.slice(0, variant === 'top10' ? 10 : undefined).map((item, index) => (
            <MediaCard
              key={`${item.type}-${item.id}`}
              item={item}
              index={index}
              variant={variant}
              artworkPreferences={artworkPreferences}
              badges={badges}
              progress={progressById[item.id]}
              onActivate={onItemActivate}
              onRemove={onRemove}
              removeFromLabel={removeFromLabel}
            />
          ))}
        </div>
      ) : (
        <p role="status" className="py-5 text-[13px] text-white/45">Loading {title.toLowerCase()}…</p>
      )}
    </section>
  );
}
