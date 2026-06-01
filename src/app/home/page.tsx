'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAuth } from '../AuthProvider';
import { useRouter } from 'next/navigation';
import { Sidebar } from '@/components/Sidebar';
import { HomeHero } from '@/components/HomeHero';
import { MediaRow } from '@/components/MediaRow';
import { CollectionRow } from '@/components/CollectionRow';
import { Collection, FeaturedHomeItem, HomeCatalogRow, MetaDetail, MetaPreview, WatchProgressEntry } from '@/lib/types';
import { getWatchProgress, getSystemAddon, getCollections } from '@/lib/services/api';
import { fetchCatalog, fetchManifest, fetchMeta } from '@/lib/stremio';
import { buildHomeRows, pickFeaturedItems } from './home-data';
import Link from 'next/link';

interface ContinueWatchingItem extends WatchProgressEntry {
  poster?: string;
  resolvedName?: string;
}

export default function HomePage() {
  const { currentProfile, user, isLoading } = useAuth();
  const router = useRouter();

  const [rows, setRows] = useState<HomeCatalogRow[]>([]);
  const [featuredItems, setFeaturedItems] = useState<FeaturedHomeItem[]>([]);
  const [featuredMetas, setFeaturedMetas] = useState<Record<string, MetaDetail | null>>({});
  const [featuredIndex, setFeaturedIndex] = useState(0);
  const [continueWatching, setContinueWatching] = useState<ContinueWatchingItem[]>([]);
  const [hasSystemAddon, setHasSystemAddon] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [discoverRows, setDiscoverRows] = useState<HomeCatalogRow[]>([]);
  const [collectionSections, setCollectionSections] = useState<Collection[]>([]);

  const heroTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const heroPausedRef = useRef(false);

  // Hero rotation timer
  useEffect(() => {
    if (featuredItems.length <= 1) return;

    heroTimerRef.current = setInterval(() => {
      if (!heroPausedRef.current) {
        setFeaturedIndex((prev) => (prev + 1) % featuredItems.length);
      }
    }, 6000);

    return () => {
      if (heroTimerRef.current) {
        clearInterval(heroTimerRef.current);
        heroTimerRef.current = null;
      }
    };
  }, [featuredItems.length]);

  const loadData = useCallback(async () => {
    if (!currentProfile) return;
    setLoading(true);
    setError(null);
    try {
      const [progress, systemAddon] = await Promise.all([
        getWatchProgress(currentProfile.id),
        getSystemAddon(),
      ]);

      const filteredProgress = progress
        .filter((entry) => !entry.completed && entry.position_seconds > 0)
        .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());

      if (!systemAddon?.manifest_url) {
        setHasSystemAddon(false);
        setRows([]);
        setFeaturedItems([]);
        setFeaturedMetas({});
        setContinueWatching(filteredProgress.slice(0, 10).map((e) => ({ ...e })));
        return;
      }

      setHasSystemAddon(true);

      const manifest = await fetchManifest(systemAddon.manifest_url);
      if (!manifest.transportUrl) {
        setRows([]);
        setFeaturedItems([]);
        setFeaturedMetas({});
        setContinueWatching(filteredProgress.slice(0, 10).map((e) => ({ ...e })));
        return;
      }

      // Fetch CW meta (poster + name) in parallel
      const cw = filteredProgress.slice(0, 10);
      const cwWithMeta: ContinueWatchingItem[] = await Promise.all(
        cw.map(async (entry) => {
          try {
            const baseId = entry.media_id.split(':')[0]; // strips :season:episode suffix for TV shows
            const meta = await fetchMeta(manifest.transportUrl!, entry.media_type, baseId);
            return {
              ...entry,
              resolvedName: meta?.name,
              poster: meta?.poster ?? meta?.background ?? undefined,
            };
          } catch {
            return { ...entry };
          }
        })
      );
      setContinueWatching(cwWithMeta);

      // Fetch ALL catalog rows (not just top 4) so folder rows are populated
      const allCatalogs = manifest.catalogs || [];
      const catalogResults = await Promise.allSettled(
        allCatalogs.map(async (catalog) => {
          const extras: Record<string, string> = {};
          for (const e of catalog.extra ?? []) {
            if (e.options?.length) extras[e.name] = e.options[0];
          }
          return {
            key: `${catalog.type}:${catalog.id}`,
            fallbackKey: catalog.id,
            items: await fetchCatalog(manifest.transportUrl!, catalog.type, catalog.id, extras),
          };
        })
      );

      const catalogItemsById: Record<string, HomeCatalogRow['items']> = {};
      for (const result of catalogResults) {
        if (result.status !== 'fulfilled') continue;
        catalogItemsById[result.value.key] = result.value.items;
        if (!(result.value.fallbackKey in catalogItemsById)) {
          catalogItemsById[result.value.fallbackKey] = result.value.items;
        }
      }

      const nextRows = buildHomeRows(manifest, catalogItemsById);
      const nextFeaturedItems = pickFeaturedItems(nextRows);

      setRows(nextRows);
      setFeaturedItems(nextFeaturedItems);
      setFeaturedIndex(0);

      // Load Supabase collections for organized display
      try {
        const collections = await getCollections();

        // Discover collection → extra MediaRows
        const discoverCol = collections.find(c => c.name.toLowerCase() === 'discover');
        if (discoverCol?.folders && manifest.transportUrl) {
          const discoverResults: HomeCatalogRow[] = [];
          await Promise.allSettled(
            (discoverCol.folders || []).map(async (folder) => {
              // Skip folders that match main row names (already shown)
              const MAIN_NAMES = ['Popular Movies', 'Popular TV Shows', 'Trending Movies', 'Trending TV Shows'];
              if (MAIN_NAMES.some(n => n.toLowerCase() === folder.name.toLowerCase())) return;

              const folderCatalogs = folder.folder_catalogs || [];
              if (folderCatalogs.length === 0) return;

              const items: MetaPreview[] = [];
              await Promise.allSettled(
                folderCatalogs.map(async (fc) => {
                  try {
                    const results = await fetchCatalog(manifest.transportUrl!, fc.media_type, fc.catalog_id);
                    items.push(...results);
                  } catch {}
                })
              );

              if (items.length > 0) {
                discoverResults.push({
                  id: `discover_${folder.id}`,
                  title: folder.name,
                  type: folderCatalogs[0]?.media_type || 'movie',
                  catalogId: folder.id,
                  items: items.slice(0, 30),
                  isMainRow: false,
                  coverImage: folder.cover_image || undefined,
                });
              }
            })
          );
          setDiscoverRows(discoverResults);
        }

        // Other collections → folder tile sections
        const otherCollections = collections
          .filter(c => c.name.toLowerCase() !== 'discover')
          .map(c => ({
            ...c,
            folders: (c.folders || []).filter((f) => (f.folder_catalogs?.length ?? 0) > 0 || f.cover_image),
          }))
          .filter(c => (c.folders?.length ?? 0) > 0);
        setCollectionSections(otherCollections);
      } catch (e) {
        console.error('Failed to load collections:', e);
      }

      // Prefetch meta for all 5 featured items in parallel
      const canFetchMeta = manifest.resources?.some(
        r => (typeof r === 'string' ? r : r.name) === 'meta'
      );
      if (canFetchMeta && nextFeaturedItems.length > 0) {
        const metaResults = await Promise.allSettled(
          nextFeaturedItems.map(async (fi) => {
            const meta = await fetchMeta(manifest.transportUrl!, fi.item.type, fi.item.id);
            return { id: fi.item.id, meta };
          })
        );

        const metas: Record<string, MetaDetail | null> = {};
        for (const r of metaResults) {
          if (r.status === 'fulfilled') {
            metas[r.value.id] = r.value.meta;
          }
        }
        setFeaturedMetas(metas);
      }
    } catch (e) {
      console.error('Failed to load home data:', e);
      setError('Failed to load content. Please try again later.');
      setRows([]);
      setFeaturedItems([]);
      setFeaturedMetas({});
    } finally {
      setLoading(false);
    }
  }, [currentProfile]);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    if (!currentProfile) { router.replace('/profiles'); return; }
    loadData();
  }, [currentProfile, isLoading, user, loadData]);

  const mainRows = rows.filter((r) => r.isMainRow);

  if (loading) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" />
        </div>
      </Sidebar>
    );
  }

  return (
    <Sidebar>
      {/* Hero — pull up behind navbar with -mt-14 to eliminate the black line */}
      {featuredItems.length > 0 && (
        <div
          className="-mt-14"
          onMouseEnter={() => { heroPausedRef.current = true; }}
          onMouseLeave={() => { heroPausedRef.current = false; }}
        >
          <HomeHero
            featuredItems={featuredItems}
            activeIndex={featuredIndex}
            metas={featuredMetas}
            onIndexChange={setFeaturedIndex}
          />
        </div>
      )}

      <div className="px-6 pb-12">
        {/* Continue Watching */}
        {continueWatching.length > 0 && (
          <section className="mb-10">
            <h2 className="text-base font-semibold text-white mb-4">Continue Watching</h2>
            <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
              {continueWatching.map((item) => {
                const pct = item.duration_seconds > 0
                  ? Math.round((item.position_seconds / item.duration_seconds) * 100)
                  : 0;
                return (
                  <Link
                    key={item.id}
                    href={`/browse/${item.media_type}/${item.media_id}`}
                    className="flex-shrink-0 w-48 group cursor-pointer"
                  >
                    <div className="relative h-[108px] bg-luna-elevated rounded-xl overflow-hidden mb-2">
                      {item.poster && (
                        <img
                          src={item.poster}
                          alt={item.resolvedName || item.media_id}
                          className="absolute inset-0 w-full h-full object-cover"
                          loading="lazy"
                        />
                      )}
                      <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                        <div className="w-10 h-10 rounded-full bg-white/20 backdrop-blur-sm flex items-center justify-center">
                          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 ml-0.5">
                            <path fillRule="evenodd" d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.348c1.295.712 1.295 2.573 0 3.285L7.28 19.991c-1.25.687-2.779-.217-2.779-1.643V5.653z" clipRule="evenodd" />
                          </svg>
                        </div>
                      </div>
                      <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-white/10">
                        <div className="h-full bg-luna-accent" style={{ width: `${pct}%` }} />
                      </div>
                    </div>
                    <p className="text-xs text-white font-medium truncate">
                      {item.resolvedName || decodeURIComponent(item.media_id.split(':')[0])}
                    </p>
                    <p className="text-xs text-luna-muted mt-0.5">
                      {item.media_type === 'series' && (() => {
                        const parts = item.media_id.split(':');
                        return parts.length >= 3 ? `S${parts[1]} E${parts[2]} · ` : '';
                      })()}{pct}% watched
                    </p>
                  </Link>
                );
              })}
            </div>
          </section>
        )}

        {/* Error / no addon states */}
        {!hasSystemAddon ? (
          <div className="flex flex-col items-center justify-center py-32 text-luna-muted">
            <p className="text-sm">No system addon configured.</p>
            <p className="text-xs mt-1 opacity-60">Ask your admin to set up an addon in the admin panel.</p>
          </div>
        ) : error ? (
          <div className="flex flex-col items-center justify-center py-32 text-luna-muted">
            <p className="text-sm">Something went wrong.</p>
            <p className="text-xs mt-1 opacity-60">{error}</p>
          </div>
        ) : rows.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-32 text-luna-muted">
            <p className="text-sm">No home catalogs available yet.</p>
            <p className="text-xs mt-1 opacity-60">The configured addon did not return any initial rows.</p>
          </div>
        ) : null}

        {/* Main 4 rows as MediaRow */}
        {mainRows.map((row) => (
          <MediaRow key={row.id} title={row.title} items={row.items} />
        ))}

        {/* Discover extra rows */}
        {discoverRows.map(row => (
          <MediaRow key={row.id} title={row.title} items={row.items} />
        ))}

        {/* Collection sections — Franchises, Streaming, Decades, etc. */}
        {collectionSections.map(section => (
          <CollectionRow key={section.id} collection={section} />
        ))}
      </div>
    </Sidebar>
  );
}
