import { useCallback, useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import { usePlayer } from '@/app/PlayerProvider';
import { Sidebar } from '@/components/Sidebar';
import { HomeHero } from '@/components/HomeHero';
import { CinematicBackground } from '@/components/CinematicBackground';
import { MediaRow } from '@/components/MediaRow';
import { CollectionRow } from '@/components/CollectionRow';
import { FeaturedHomeItem, MetaDetail, WatchProgressEntry } from '@/lib/types';
import { getWatchProgress, getSystemAddon } from '@/lib/services/api';
import { fetchManifest, fetchMeta } from '@/lib/stremio';
import { TMDB_API_KEY } from '@/lib/supabase';
import { formatContinueWatchingTitle } from '@/lib/player-utils';
import { loadCollections, refreshCollections, fetchLiveOrganizer, CatalogRow } from '@/lib/collections/repository';
import { useQueryClient } from '@tanstack/react-query';
import { pickFeaturedItems } from './home-data';
import { motion } from 'framer-motion';
import { SPRING, TILE_HOVER_SCALE } from '@/lib/design/motion';

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
  const queryClient = useQueryClient();

  // ── Progressive rows state ────────────────────────────────────────────────
  const [featuredItems, setFeaturedItems] = useState<FeaturedHomeItem[]>([]);
  const [featuredMetas, setFeaturedMetas] = useState<Record<string, MetaDetail | null>>({});
  const [featuredBackdrops, setFeaturedBackdrops] = useState<Record<string, string>>({});
  const [featuredIndex, setFeaturedIndex] = useState(0);
  const heroTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const heroPausedRef = useRef(false);

  // Hero rotation
  useEffect(() => {
    if (featuredItems.length <= 1) return;
    heroTimerRef.current = setInterval(() => {
      if (!heroPausedRef.current) setFeaturedIndex(prev => (prev + 1) % featuredItems.length);
    }, 60000);
    return () => { if (heroTimerRef.current) clearInterval(heroTimerRef.current); };
  }, [featuredItems.length]);

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

  // ── Manifest ──────────────────────────────────────────────────────────────
  const { data: manifest } = useQuery({
    queryKey: ['manifest', initialData?.systemAddon?.manifest_url],
    queryFn: () => fetchManifest(initialData!.systemAddon!.manifest_url),
    enabled: !!initialData?.systemAddon?.manifest_url,
    staleTime: 5 * 60 * 1000,
  });

  // ── Collection engine: load all rows from collections + addons ──────────
  const { data: collectionRows = [], isLoading: collectionsLoading } = useQuery({
    queryKey: ['home-collections', currentProfile?.id, addons.map(a => a.id).join(',')],
    queryFn: async () => {
      if (addons.length === 0) return [];
      return loadCollections(addons, TMDB_API_KEY);
    },
    enabled: addons.length > 0,
    staleTime: 5 * 60 * 1000,
  });

  // ── Background live refresh from edge function ────────────────────────────
  // Fires once after the initial collections load so the app always reflects
  // the latest state from Supabase without requiring a redeploy.
  const collectionsQueryKey = ['home-collections', currentProfile?.id, addons.map(a => a.id).join(',')];
  useEffect(() => {
    if (collectionsLoading || addons.length === 0) return;
    let cancelled = false;
    (async () => {
      const organized = await fetchLiveOrganizer();
      if (cancelled || !organized) return;
      const rows = await refreshCollections(organized, addons, TMDB_API_KEY);
      if (cancelled) return;
      queryClient.setQueryData(collectionsQueryKey, rows);
    })();
    return () => { cancelled = true; };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [collectionsLoading, addons.length]);

  // ── Featured items: derive from the content rows (group-tile rows excluded).
  // Depend on the stable `collectionRows` reference (from react-query), NOT a
  // freshly-filtered array — otherwise this effect re-runs every render and
  // setFeaturedItems triggers an infinite render/refetch loop. ──
  useEffect(() => {
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
    const next = pickFeaturedItems(homeCatalogRows);
    if (next.length > 0) {
      setFeaturedItems(next);
      setFeaturedIndex(0);
    }
  }, [collectionRows]);

  // ── Featured TMDB backdrop prefetch — fast path before addon meta arrives ──
  useEffect(() => {
    if (featuredItems.length === 0) return;
    let cancelled = false;
    Promise.allSettled(
      featuredItems.map(async fi => {
        if (!fi.item.id.startsWith('tt')) return null;
        const type = fi.item.type === 'series' ? 'tv' : 'movie';
        const res = await fetch(
          `https://api.themoviedb.org/3/find/${fi.item.id}?api_key=${TMDB_API_KEY}&external_source=imdb_id`
        );
        if (!res.ok) return null;
        const data = await res.json();
        const hit = type === 'tv' ? data.tv_results?.[0] : data.movie_results?.[0];
        if (!hit?.backdrop_path) return null;
        return { id: fi.item.id, url: `https://image.tmdb.org/t/p/w1280${hit.backdrop_path}` };
      })
    ).then(results => {
      if (cancelled) return;
      const map: Record<string, string> = {};
      for (const r of results) {
        if (r.status === 'fulfilled' && r.value) map[r.value.id] = r.value.url;
      }
      setFeaturedBackdrops(map);
    });
    return () => { cancelled = true; };
  }, [featuredItems]);

  // ── Featured meta prefetch ────────────────────────────────────────────────
  useEffect(() => {
    if (!manifest?.transportUrl || featuredItems.length === 0) return;
    const canFetchMeta = manifest.resources?.some(r => (typeof r === 'string' ? r : r.name) === 'meta');
    if (!canFetchMeta) return;

    const controller = new AbortController();
    Promise.allSettled(
      featuredItems.map(async fi => {
        const meta = await fetchMeta(manifest.transportUrl!, fi.item.type, fi.item.id);
        return { id: fi.item.id, meta };
      })
    ).then(results => {
      if (controller.signal.aborted) return;
      const metas: Record<string, MetaDetail | null> = {};
      for (const r of results) {
        if (r.status === 'fulfilled') metas[r.value.id] = r.value.meta;
      }
      setFeaturedMetas(metas);
    });
    return () => controller.abort();
  }, [featuredItems, manifest?.transportUrl]);

  // ── CW: base list — normalize encoded IDs, deduplicate by base show ID ──
  const continueWatching = (() => {
    const seenBase = new Set<string>();
    return (initialData?.progress ?? [])
      .filter(e => !e.completed && e.position_seconds > 0)
      // Normalize URL-encoded colons (%3A) so splitting always works
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

  // ── CW: fetch name + episode stills for all series; poster/name for movies missing it ──
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
              // Look up TMDB ID via IMDb ID, then fetch episode still
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
              // Fallback to stremio meta + video thumbnail
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
          } catch {}
        })
      );
      return results;
    },
    enabled: cwNeedsMeta.length > 0 && !!manifest?.transportUrl,
    staleTime: 60 * 60 * 1000,
  });

  // ── CW: click → open player overlay immediately ──
  function handleCwPlay(item: WatchProgressEntry) {
    const fallback = cwMetas?.[item.media_id];
    const baseId = item.media_id.split(':')[0];
    const displayName = item.name ?? fallback?.name ?? baseId;
    const watchTitle = formatContinueWatchingTitle({ mediaId: item.media_id, mediaType: item.media_type, name: displayName });
    // Series: prefer episode still (landscape) as poster; movies use portrait poster
    const poster = (item.media_type === 'series' && item.media_id.includes(':'))
      ? (fallback?.poster ?? item.poster ?? undefined)
      : (item.poster ?? fallback?.poster ?? undefined);
    // Logo + background: available when item is also in the featured carousel
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
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-moonlit-accent border-t-transparent" />
        </div>
      </Sidebar>
    );
  }

  return (
    <Sidebar>
      <CinematicBackground
        backdropUrl={
          (() => {
            if (featuredItems.length === 0) return null;
            const f = featuredItems[featuredIndex] ?? featuredItems[0];
            const m = featuredMetas[f.item.id] ?? null;
            return m?.background || featuredBackdrops[f.item.id] || f.item.banner || null;
          })()
        }
      />
      {featuredItems.length > 0 && (
        <div className="-mt-16"
          onMouseEnter={() => { heroPausedRef.current = true; }}
          onMouseLeave={() => { heroPausedRef.current = false; }}>
          <HomeHero
            featuredItems={featuredItems}
            activeIndex={featuredIndex}
            metas={featuredMetas}
            backdrops={featuredBackdrops}
            onIndexChange={setFeaturedIndex}
          />
        </div>
      )}

      <div className="px-6 pb-12">
        {/* Continue Watching */}
        {continueWatching.length > 0 && (
          <section className="mb-10">
            <div className="flex items-baseline justify-between mb-4 pr-1">
              <h2 className="text-[21px] font-bold text-white">Continue Watching</h2>
            </div>
            <div className="flex gap-3 overflow-x-auto py-3 -my-3 scrollbar-hide">
              {continueWatching.map(item => {
                const fallback = cwMetas?.[item.media_id];
                const poster = (item.media_type === 'series' && item.media_id.includes(':'))
                  ? (fallback?.poster ?? item.poster)
                  : (item.poster ?? fallback?.poster);
                const name = item.name ?? fallback?.name;
                const parts = item.media_id.split(':');
                const progressPct = item.duration_seconds > 0
                  ? Math.min(100, (item.position_seconds / item.duration_seconds) * 100)
                  : 0;
                return (
                  <motion.button
                    key={item.id}
                    whileHover={{ scale: TILE_HOVER_SCALE }}
                    transition={SPRING.continueWatching}
                    onClick={() => handleCwPlay(item)}
                    className="flex-shrink-0 w-80 cursor-pointer text-left"
                  >
                    <div className="relative h-44 bg-moonlit-elevated rounded-ml-lg overflow-hidden mb-2 border border-white/5 hover:border-white/[0.14] hover:shadow-ml-lift transition-all duration-300">
                      {poster ? (
                        <img src={poster} alt={name || item.media_id}
                          className="absolute inset-0 w-full h-full object-cover" loading="lazy" />
                      ) : (
                        <div className="absolute inset-0 flex items-center justify-center">
                          <svg className="w-6 h-6 text-white/15" viewBox="0 0 24 24" fill="currentColor">
                            <path d="M4 4h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z"/>
                          </svg>
                        </div>
                      )}
                      {/* Frosted scrim + metadata overlay (matches iOS ContinueWatchingCard) */}
                      <div className="absolute inset-x-0 bottom-0 h-12 backdrop-blur-[3px] [mask-image:linear-gradient(to_top,black_35%,transparent)]" />
                      <div className="absolute inset-x-0 bottom-0 h-1/2 bg-gradient-to-t from-black/75 via-black/15 to-transparent" />
                      {/* White progress bar */}
                      <div className="absolute bottom-0 left-0 right-0 h-[3px] bg-white/20">
                        <div className="h-full bg-white transition-all duration-500" style={{ width: `${progressPct}%` }} />
                      </div>
                      <div className="absolute inset-x-0 bottom-[5px] flex items-end justify-between gap-2 px-3 pb-2.5">
                        <span className="text-[11px] font-bold text-white drop-shadow-md">
                          {item.media_type === 'series' && parts.length >= 3 ? `S${parts[1]} E${parts[2]}` : ''}
                        </span>
                        <span className="text-[11px] font-medium text-white/75 drop-shadow-md whitespace-nowrap">
                          {formatTimeRemaining(item.position_seconds, item.duration_seconds)}
                        </span>
                      </div>
                    </div>
                    <p className="text-[13px] text-white font-medium truncate">{name || item.media_id}</p>
                  </motion.button>
                );
              })}
            </div>
          </section>
        )}

        {!hasSystemAddon ? (
          <div className="flex flex-col items-center justify-center py-32 text-moonlit-muted">
            <p className="text-sm">No system addon configured.</p>
            <p className="text-xs mt-1 opacity-60">Ask your admin to set up an addon in the admin panel.</p>
          </div>
        ) : null}

        {/* Render every collection row in its original (iOS) order — group-tile
            rows as CollectionRow, content rows as MediaRow. Empty content rows
            (e.g. unfetched supplementary addon catalogs) are dropped. */}
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
            <MediaRow key={row.id} title={row.title} titleLogo={row.titleLogo} items={row.items} />
          ))}
      </div>
    </Sidebar>
  );
}
