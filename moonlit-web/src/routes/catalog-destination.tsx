import { useEffect, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';

import { useAuth } from '@/app/AuthProvider';
import { usePlayer } from '@/app/PlayerProvider';
import { FusionBackground } from '@/components/FusionBackground';
import { HomeHero } from '@/components/HomeHero';
import { MediaRow } from '@/components/MediaRow';
import type { CatalogRow } from '@/lib/collections/types';
import { getWatchProgress } from '@/lib/services/api';
import type { FeaturedHomeItem, HomeCatalogRow, MetaPreview, WatchProgressEntry } from '@/lib/types';
import { formatContinueWatchingTitle } from '@/lib/player-utils';
import { useArtworkPreferences, useCatalogRowsData } from './catalog-data';
import { catalogRailVariant } from './rail-variant';
import { useFeaturedEnrichment } from './featured-enrichment';
import type { HeroTransitionSource } from '@/lib/design/motion';

function toHomeRow(row: CatalogRow, mediaType: 'movie' | 'series'): HomeCatalogRow {
  return {
    id: row.id,
    title: row.title,
    type: mediaType,
    catalogId: row.id,
    items: row.items,
  };
}

function continueItem(entry: WatchProgressEntry): MetaPreview {
  const mediaId = entry.media_id;
  const baseId = mediaId.split(':')[0];
  return {
    id: mediaId,
    routeId: baseId,
    type: entry.media_type,
    name: entry.name || baseId,
    banner: entry.poster,
    poster: entry.poster,
  };
}

function timeRemaining(entry: WatchProgressEntry): string {
  if (entry.duration_seconds <= 0) return `${Math.round(entry.position_seconds / 60)} min watched`;
  const minutes = Math.max(0, Math.round((entry.duration_seconds - entry.position_seconds) / 60));
  return minutes <= 0 ? 'Almost done' : `${minutes} min left`;
}

export function CatalogDestination({ mediaType, title }: { mediaType: 'movie' | 'series'; title: string }) {
  const { addons, currentProfile } = useAuth();
  const { open: openPlayer } = usePlayer();
  const { data: rows = [], isLoading, isError } = useCatalogRowsData(addons, currentProfile?.id);
  const artworkPreferences = useArtworkPreferences(currentProfile?.id);
  const [selectedGenre, setSelectedGenre] = useState('All');
  const [featuredIndex, setFeaturedIndex] = useState(0);
  const [heroPaused, setHeroPaused] = useState(false);
  const [heroTransitionSource, setHeroTransitionSource] = useState<HeroTransitionSource>('manual');

  const { data: progress = [] } = useQuery({
    queryKey: ['watch-progress', currentProfile?.id ?? 'guest'],
    queryFn: () => currentProfile ? getWatchProgress(currentProfile.id) : Promise.resolve([]),
    enabled: Boolean(currentProfile),
    staleTime: 2 * 60 * 1000,
  });

  const matchingRows = useMemo(() => rows
    .map(row => ({ ...row, items: row.items.filter(item => item.type === mediaType) }))
    .filter(row => row.items.length > 0), [mediaType, rows]);

  const genres = useMemo(() => Array.from(new Set(
    matchingRows.flatMap(row => row.items.flatMap(item => item.genres ?? [])),
  )).sort().slice(0, 12), [matchingRows]);

  const visibleRows = useMemo(() => selectedGenre === 'All'
    ? matchingRows
    : matchingRows
      .map(row => ({ ...row, items: row.items.filter(item => item.genres?.includes(selectedGenre)) }))
      .filter(row => row.items.length > 0), [matchingRows, selectedGenre]);

  const featuredItems: FeaturedHomeItem[] = useMemo(() => {
    const seen = new Set<string>();
    const output: FeaturedHomeItem[] = [];
    for (const row of matchingRows) {
      const homeRow = toHomeRow(row, mediaType);
      for (const item of row.items) {
        if (seen.has(item.id)) continue;
        seen.add(item.id);
        output.push({ row: homeRow, item });
        if (output.length === 5) return output;
      }
    }
    return output;
  }, [matchingRows, mediaType]);
  const featuredEnrichment = useFeaturedEnrichment(featuredItems, addons);

  useEffect(() => {
    if (heroPaused || featuredItems.length <= 1 || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const interval = window.setInterval(
      () => {
        setHeroTransitionSource('automatic');
        setFeaturedIndex(index => (index + 1) % featuredItems.length);
      },
      60_000,
    );
    return () => window.clearInterval(interval);
  }, [featuredItems.length, heroPaused]);

  const activeFeaturedIndex = featuredIndex < featuredItems.length ? featuredIndex : 0;

  const continueEntries = useMemo(() => {
    const seenBaseIds = new Set<string>();
    return progress
      .filter(entry => entry.media_type === mediaType && !entry.completed && entry.position_seconds > 0)
      .map(entry => ({ ...entry, media_id: decodeURIComponent(entry.media_id) }))
      .sort((left, right) => Date.parse(right.updated_at) - Date.parse(left.updated_at))
      .filter(entry => {
        const baseId = entry.media_id.split(':')[0];
        if (seenBaseIds.has(baseId)) return false;
        seenBaseIds.add(baseId);
        return true;
      });
  }, [mediaType, progress]);
  const continueItems = continueEntries.map(continueItem);
  const progressById = Object.fromEntries(continueEntries.map(entry => {
    const parts = entry.media_id.split(':');
    return [entry.media_id, {
      fraction: entry.duration_seconds > 0 ? entry.position_seconds / entry.duration_seconds : 0,
      label: timeRemaining(entry),
      episodeLabel: entry.media_type === 'series' && parts.length >= 3 ? `S${parts[1]} E${parts[2]}` : undefined,
    }];
  }));
  const activeFeature = featuredItems[activeFeaturedIndex];
  const activeFeatureId = activeFeature?.item.id;
  const currentBackdrop = activeFeature?.item.banner
    || (activeFeatureId ? featuredEnrichment.metas[activeFeatureId]?.background : undefined)
    || (activeFeatureId ? featuredEnrichment.backdrops[activeFeatureId] : undefined);

  return (
    <div className="catalog-destination min-h-[calc(100vh-56px)] pb-16">
      <FusionBackground backdropUrl={currentBackdrop} heroHeight={560} />

      {featuredItems.length > 0 ? (
        <HomeHero
          featuredItems={featuredItems}
          activeIndex={activeFeaturedIndex}
          metas={featuredEnrichment.metas}
          backdrops={featuredEnrichment.backdrops}
          awards={featuredEnrichment.awards}
          transitionSource={heroTransitionSource}
          onIndexChange={(index, source = 'manual') => {
            setHeroTransitionSource(source);
            setFeaturedIndex(index);
          }}
          isPaused={heroPaused}
          onPauseChange={setHeroPaused}
        />
      ) : (
        <header className="px-4 pb-10 pt-20 sm:px-6 md:px-14">
          <p className="type-label mb-2 text-moonlit-text-tertiary">Browse</p>
          <h1 className="type-title-lg text-white">{title}</h1>
        </header>
      )}

      <div className="relative mx-auto max-w-[1600px] px-4 sm:px-6 md:px-14">
        <div className="mb-9 flex flex-wrap items-center gap-3">
          <h2 className="text-xl font-bold text-white">Browse {title}</h2>
          <div
            role="group"
            aria-label={`Filter ${title} by genre`}
            className="flex max-w-full gap-2 overflow-x-auto py-2 scrollbar-hide"
          >
            {['All', ...genres].map(genre => (
              <button
                key={genre}
                type="button"
                aria-pressed={selectedGenre === genre}
                onClick={() => setSelectedGenre(genre)}
                className={`category-pill min-h-11 whitespace-nowrap ${selectedGenre === genre ? 'category-pill-active' : 'category-pill-idle'}`}
              >
                {genre}
              </button>
            ))}
          </div>
        </div>

        {isLoading && rows.length === 0 && (
          <div role="status" className="flex min-h-48 items-center gap-3 text-sm text-moonlit-text-secondary">
            <span className="h-5 w-5 animate-spin-arc rounded-full border-2 border-white/15 border-t-white" />
            Loading {title.toLowerCase()}…
          </div>
        )}
        {isError && rows.length > 0 && (
          <p role="alert" className="glass-panel mb-8 rounded-ml-ctl px-4 py-3 text-sm text-moonlit-text-secondary">
            Some {mediaType} rows could not be refreshed. Showing the artwork already on this device.
          </p>
        )}
        {isError && rows.length === 0 && (
          <div role="alert" className="surface-card max-w-xl p-6">
            <h2 className="type-title-sm text-white">{title} could not be loaded</h2>
            <p className="mt-2 text-sm text-moonlit-text-secondary">Check the enabled catalog addons and try again.</p>
          </div>
        )}

        {continueItems.length > 0 && (
          <MediaRow
            title="Continue Watching"
            items={continueItems}
            variant="continue"
            artworkPreferences={artworkPreferences}
            progressById={progressById}
            badges={{ rating: false }}
            onItemActivate={item => {
              const entry = continueEntries.find(candidate => candidate.media_id === item.id);
              if (!entry) return;
              openPlayer({
                type: entry.media_type,
                id: entry.media_id,
                metadata: {
                  mediaId: entry.media_id,
                  mediaType: entry.media_type,
                  title: formatContinueWatchingTitle({
                    mediaId: entry.media_id,
                    mediaType: entry.media_type,
                    name: entry.name || entry.media_id.split(':')[0],
                  }),
                  poster: entry.poster,
                },
                startPosition: entry.position_seconds,
              });
            }}
          />
        )}

        {!isLoading && !isError && matchingRows.length === 0 && (
          <div className="surface-card max-w-xl p-6">
            <h2 className="type-title-sm text-white">No {title.toLowerCase()} available</h2>
            <p className="mt-2 text-sm text-moonlit-text-secondary">Install or enable a catalog addon to populate this page.</p>
          </div>
        )}

        {visibleRows.map(row => (
          <MediaRow
            key={row.id}
            title={row.title}
            titleLogo={row.titleLogo}
            items={row.items}
            variant={catalogRailVariant(row)}
            artworkPreferences={artworkPreferences}
          />
        ))}
      </div>
    </div>
  );
}
