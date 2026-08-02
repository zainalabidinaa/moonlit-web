import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import { usePlayer } from '@/app/PlayerProvider';
import { HomeHero } from '@/components/HomeHero';
import { FusionBackground } from '@/components/FusionBackground';
import { MediaRow } from '@/components/MediaRow';
import { CollectionRow } from '@/components/CollectionRow';
import { FeaturedHomeItem, WatchProgressEntry } from '@/lib/types';
import { getWatchProgress, getSystemAddon } from '@/lib/services/api';
import { fetchManifest, fetchMeta } from '@/lib/stremio';
import { TMDB_API_KEY } from '@/lib/supabase';
import { formatContinueWatchingTitle } from '@/lib/player-utils';
import { pickFeaturedItems } from './home-data';
import { useArtworkPreferences, useCatalogRowsData } from './catalog-data';
import { catalogRailVariant } from './rail-variant';
import { useFeaturedEnrichment } from './featured-enrichment';
import type { HeroTransitionSource } from '@/lib/design/motion';

function formatTimeRemaining(positionSec: number, durationSec: number): string {
  if (durationSec > 0) {
    const leftSec = Math.max(0, durationSec - positionSec);
    const leftMin = Math.round(leftSec / 60);
    if (leftMin <= 0) return 'Almost done';
    if (leftMin < 60) return `${leftMin} min left`;
    const h = Math.floor(leftMin / 60);
    const m = leftMin % 60;
    return m > 0 ? `${h}h ${m}m left` : `${h}h left`;
  }
  const watchedMin = Math.round(positionSec / 60);
  if (watchedMin < 60) return `${watchedMin} min watched`;
  const h = Math.floor(watchedMin / 60);
  const m = watchedMin % 60;
  return m > 0 ? `${h}h ${m}m watched` : `${h}h watched`;
}

export default function HomePage() {
  const { currentProfile, addons } = useAuth();
  const { open: openPlayer } = usePlayer();
  const artworkPreferences = useArtworkPreferences(currentProfile?.id);

  // ── Progressive rows state ────────────────────────────────────────────────
  const [featuredIndex, setFeaturedIndex] = useState(0);
  const [heroPaused, setHeroPaused] = useState(false);
  const [heroTransitionSource, setHeroTransitionSource] = useState<HeroTransitionSource>('manual');
  const heroTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const heroPausedRef = useRef(false);

  // ── Initial data: CW progress + system addon ────────────────────────────
  const { data: initialData, isLoading: initialLoading } = useQuery({
    queryKey: ['home-initial', currentProfile?.id],
    queryFn: async () => {
      const [progress, systemAddon] = await Promise.all([
        getWatchProgress(currentProfile!.id),
        getSystemAddon(),
      ]);
      return { progress, systemAddon };
    },
    enabled: !!currentProfile,
    staleTime: 5 * 60 * 1000,
  });

  const { data: manifest } = useQuery({
    queryKey: ['manifest', initialData?.systemAddon?.manifest_url],
    queryFn: () => fetchManifest(initialData!.systemAddon!.manifest_url),
    enabled: !!initialData?.systemAddon?.manifest_url,
    staleTime: 5 * 60 * 1000,
  });

  // Home, Movies, and Series share this one organizer/catalog pipeline and
  // React Query cache. Each destination only projects the loaded rows.
  const { data: collectionRows = [] } = useCatalogRowsData(addons, currentProfile?.id);

  const featuredItems: FeaturedHomeItem[] = useMemo(() => {
    const homeCatalogRows = collectionRows
      .filter(r => !r.isGroupTile)
      .map(r => ({
        id: r.id,
        title: r.title,
        type: r.items[0]?.type || 'movie',
        catalogId: r.id,
        items: r.items,
        isMainRow: r.title ? [
          'Popular Movies','Popular TV Shows','Trending Movies','Trending TV Shows',
          'Popular Shows','Trending Shows','Latest','Top Rated',
        ].some(n => n.toLowerCase() === r.title.toLowerCase()) : false,
      }));
    return pickFeaturedItems(homeCatalogRows);
  }, [collectionRows]);
  const {
    metas: featuredMetas,
    backdrops: featuredBackdrops,
    awards: featuredAwards,
  } = useFeaturedEnrichment(featuredItems, addons);

  useEffect(() => {
    if (
      featuredItems.length <= 1
      || window.matchMedia('(prefers-reduced-motion: reduce)').matches
    ) return;
    heroTimerRef.current = setInterval(() => {
      if (!heroPausedRef.current && document.visibilityState !== 'hidden') {
        setHeroTransitionSource('automatic');
        setFeaturedIndex(prev => (prev + 1) % featuredItems.length);
      }
    }, 60000);
    return () => { if (heroTimerRef.current) clearInterval(heroTimerRef.current); };
  }, [featuredItems.length]);

  const continueWatching = (() => {
    const seenBase = new Set<string>();
    return (initialData?.progress ?? [])
      .filter(e => !e.completed && e.position_seconds > 0)
      .map(e => ({ ...e, media_id: decodeURIComponent(e.media_id) }))
      .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
      .filter(e => {
        const base = e.media_id.split(':')[0];
        if (seenBase.has(base)) return false;
        seenBase.add(base);
        return true;
      })
      .slice(0, 10);
  })();

  const cwNeedsMeta = continueWatching.filter(e =>
    (e.media_type === 'series' && e.media_id.includes(':')) || (!e.poster && !e.name)
  );
  const { data: cwMetas } = useQuery({
    queryKey: ['cw-meta', cwNeedsMeta.map(e => e.media_id).join(','), manifest?.transportUrl],
    queryFn: async () => {
      const results: Record<string, { name?: string; poster?: string }> = {};
      await Promise.allSettled(
        cwNeedsMeta.map(async entry => {
          const parts = entry.media_id.split(':');
          const baseId = parts[0];
          const season = parts[1] ? parseInt(parts[1], 10) : undefined;
          const episode = parts[2] ? parseInt(parts[2], 10) : undefined;
          try {
            if (entry.media_type === 'series' && season !== undefined && episode !== undefined) {
              if (season > 0) {
                const findRes = await fetch(
                  `https://api.themoviedb.org/3/find/${baseId}?api_key=${TMDB_API_KEY}&external_source=imdb_id`
                );
                if (findRes.ok) {
                  const findData = await findRes.json();
                  const hit = findData.tv_results?.[0];
                  if (hit?.id) {
                    const epRes = await fetch(
                      `https://api.themoviedb.org/3/tv/${hit.id}/season/${season}/episode/${episode}?api_key=${TMDB_API_KEY}`
                    );
                    if (epRes.ok) {
                      const epData = await epRes.json();
                      results[entry.media_id] = {
                        name: hit.name,
                        poster: epData.still_path
                          ? `https://image.tmdb.org/t/p/w780${epData.still_path}`
                          : undefined,
                      };
                      return;
                    }
                  }
                }
              }
              if (manifest?.transportUrl) {
                const meta = await fetchMeta(manifest.transportUrl, entry.media_type, baseId);
                if (meta) {
                  const video = meta.videos?.find(v => v.season === season && v.episode === episode);
                  results[entry.media_id] = {
                    name: meta.name,
                    poster: video?.thumbnail ?? meta.background ?? meta.poster ?? undefined,
                  };
                }
              }
            } else if (manifest?.transportUrl) {
              const meta = await fetchMeta(manifest.transportUrl, entry.media_type, baseId);
              if (meta) results[entry.media_id] = { name: meta.name, poster: meta.poster ?? meta.background ?? undefined };
            }
          } catch { /* Continue Watching metadata is optional enrichment. */ }
        })
      );
      return results;
    },
    enabled: cwNeedsMeta.length > 0 && !!manifest?.transportUrl,
    staleTime: 60 * 60 * 1000,
  });

  function handleCwPlay(item: WatchProgressEntry) {
    const fallback = cwMetas?.[item.media_id];
    const baseId = item.media_id.split(':')[0];
    const displayName = item.name ?? fallback?.name ?? baseId;
    const watchTitle = formatContinueWatchingTitle({ mediaId: item.media_id, mediaType: item.media_type, name: displayName });
    const poster = (item.media_type === 'series' && item.media_id.includes(':'))
      ? (fallback?.poster ?? item.poster ?? undefined)
      : (item.poster ?? fallback?.poster ?? undefined);
    const featuredMeta = featuredMetas[baseId];
    const logo = featuredMeta?.logo ?? undefined;
    const background = featuredMeta?.background ?? featuredBackdrops[baseId] ?? undefined;
    openPlayer({
      type: item.media_type,
      id: item.media_id,
      metadata: {
        mediaId: item.media_id,
        mediaType: item.media_type,
        title: watchTitle,
        logo,
        poster,
        background,
      },
      startPosition: item.position_seconds > 0 ? item.position_seconds : undefined,
    });
  }

  const hasSystemAddon = !!initialData?.systemAddon?.manifest_url;

  if (initialLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-6 w-6 border-2 border-[#e50914] border-t-transparent" />
      </div>
    );
  }

  const activeFeaturedIndex = featuredIndex < featuredItems.length ? featuredIndex : 0;
  const currentBackdrop =
    featuredItems.length > 0
      ? (() => {
          const f = featuredItems[activeFeaturedIndex];
          const m = featuredMetas[f.item.id] ?? null;
          return f.item.banner || m?.background || featuredBackdrops[f.item.id] || null;
        })()
      : null;

  return (
    <>
      <FusionBackground backdropUrl={currentBackdrop} heroHeight={560} />

      {featuredItems.length > 0 && (
        <div
          className="relative"
          onMouseEnter={() => { heroPausedRef.current = true; }}
          onMouseLeave={() => { heroPausedRef.current = heroPaused; }}
        >
          <HomeHero
            featuredItems={featuredItems}
            activeIndex={activeFeaturedIndex}
            metas={featuredMetas}
            backdrops={featuredBackdrops}
            awards={featuredAwards}
            transitionSource={heroTransitionSource}
            onIndexChange={(index, source = 'manual') => {
              setHeroTransitionSource(source);
              setFeaturedIndex(index);
            }}
            isPaused={heroPaused}
            onPauseChange={paused => {
              heroPausedRef.current = paused;
              setHeroPaused(paused);
            }}
          />
        </div>
      )}

      <div className="px-8 md:px-14 pb-16">
        {continueWatching.length > 0 && (
          <MediaRow
            title="Continue Watching"
            variant="continue"
            artworkPreferences={artworkPreferences}
            badges={{ rating: false }}
            items={continueWatching.map(item => {
              const fallback = cwMetas?.[item.media_id];
              const poster = item.media_type === 'series' && item.media_id.includes(':')
                ? fallback?.poster ?? item.poster
                : item.poster ?? fallback?.poster;
              return {
                id: item.media_id,
                type: item.media_type,
                name: item.name ?? fallback?.name ?? item.media_id,
                banner: poster,
                poster,
              };
            })}
            progressById={Object.fromEntries(continueWatching.map(item => {
              const parts = item.media_id.split(':');
              return [item.media_id, {
                fraction: item.duration_seconds > 0 ? item.position_seconds / item.duration_seconds : 0,
                label: formatTimeRemaining(item.position_seconds, item.duration_seconds),
                episodeLabel: item.media_type === 'series' && parts.length >= 3 ? `S${parts[1]} E${parts[2]}` : undefined,
              }];
            }))}
            onItemActivate={preview => {
              const entry = continueWatching.find(item => item.media_id === preview.id);
              if (entry) handleCwPlay(entry);
            }}
          />
        )}

        {!hasSystemAddon ? (
          <div className="flex flex-col items-center justify-center py-32 text-moonlit-muted">
            <p className="text-sm">No system addon configured.</p>
            <p className="text-xs mt-1 opacity-60">Ask your admin to set up an addon in the admin panel.</p>
          </div>
        ) : null}

        {collectionRows
          .filter(row => row.isGroupTile || row.items.length > 0)
          .map(row => row.isGroupTile ? (
            <CollectionRow
              key={row.id}
              titleLogo={row.titleLogo}
              collection={{
                id: row.id,
                name: row.title,
                sort_order: 0,
                focus_glow_enabled: row.focusGlowEnabled,
                created_at: '',
                folders: row.items.map((item, i) => ({
                  id: item.id,
                  name: item.name,
                  collection_id: row.id,
                  sort_order: i,
                  cover_image: item.poster || '',
                  focus_gif: null,
                  focus_gif_enabled: row.focusGifEnabled,
                  tile_shape: ((item.tileShape ?? row.tileShape)?.toUpperCase() as 'LANDSCAPE' | 'PORTRAIT' | null) || null,
                  created_at: '',
                })),
              }}
            />
          ) : (
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
    </>
  );
}
