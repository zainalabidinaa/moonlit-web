import { useCallback, useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import { Sidebar } from '@/components/Sidebar';
import { HomeHero } from '@/components/HomeHero';
import { MediaRow } from '@/components/MediaRow';
import { CollectionRow } from '@/components/CollectionRow';
import { Collection, FeaturedHomeItem, HomeCatalogRow, MetaDetail, MetaPreview } from '@/lib/types';
import { getWatchProgress, getSystemAddon, getCollections } from '@/lib/services/api';
import { fetchCatalog, fetchManifest, fetchMeta } from '@/lib/stremio';
import { buildHomeRows, pickFeaturedItems } from './home-data';
import { Link } from '@tanstack/react-router';

const MAIN_NAMES = ['Popular Movies', 'Popular TV Shows', 'Trending Movies', 'Trending TV Shows'];

export default function HomePage() {
  const { currentProfile } = useAuth();

  // ── Progressive rows state ────────────────────────────────────────────────
  const [rows, setRows] = useState<HomeCatalogRow[]>([]);
  const [discoverRows, setDiscoverRows] = useState<HomeCatalogRow[]>([]);
  const [featuredItems, setFeaturedItems] = useState<FeaturedHomeItem[]>([]);
  const [featuredMetas, setFeaturedMetas] = useState<Record<string, MetaDetail | null>>({});
  const [featuredIndex, setFeaturedIndex] = useState(0);
  const heroTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const heroPausedRef = useRef(false);

  // Hero rotation
  useEffect(() => {
    if (featuredItems.length <= 1) return;
    heroTimerRef.current = setInterval(() => {
      if (!heroPausedRef.current) setFeaturedIndex(prev => (prev + 1) % featuredItems.length);
    }, 6000);
    return () => { if (heroTimerRef.current) clearInterval(heroTimerRef.current); };
  }, [featuredItems.length]);

  // ── Fix A: Parallel initial fetch ─────────────────────────────────────────
  // getWatchProgress + getSystemAddon + getCollections all fire at once
  const { data: initialData, isLoading: initialLoading } = useQuery({
    queryKey: ['home-initial', currentProfile?.id],
    queryFn: async () => {
      const [progress, systemAddon, collections] = await Promise.all([
        getWatchProgress(currentProfile!.id),
        getSystemAddon(),
        getCollections(),
      ]);
      return { progress, systemAddon, collections };
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

  // ── Fix B: Progressive catalog loading ───────────────────────────────────
  // Each catalog gets its own query; rows appear as they resolve
  useEffect(() => {
    if (!manifest?.transportUrl || !manifest.catalogs) return;
    setRows([]);

    const allCatalogs = manifest.catalogs;

    allCatalogs.forEach(catalog => {
      const extras: Record<string, string> = {};
      for (const e of catalog.extra ?? []) {
        if (e.options?.length) extras[e.name] = e.options[0];
      }

      fetchCatalog(manifest.transportUrl!, catalog.type, catalog.id, extras)
        .then(items => {
          if (items.length === 0) return;
          const title = catalog.name || catalog.id;
          const row: HomeCatalogRow = {
            id: `${manifest.id}_${catalog.type}_${catalog.id}`,
            title,
            type: catalog.type,
            catalogId: catalog.id,
            items,
            isMainRow: MAIN_NAMES.some(n => n.toLowerCase() === title.toLowerCase()),
          };
          setRows(prev => {
            // Avoid duplicates (React StrictMode double-fire)
            if (prev.some(r => r.id === row.id)) return prev;
            return [...prev, row];
          });
        })
        .catch(() => {});
    });
  }, [manifest?.id, manifest?.transportUrl]);

  // ── Featured items: derive from rows as they accumulate ──────────────────
  useEffect(() => {
    const next = pickFeaturedItems(rows);
    if (next.length > 0) {
      setFeaturedItems(next);
      setFeaturedIndex(0);
    }
  }, [rows]);

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

  // ── Fix C: Discover rows (uses collections fetched in parallel) ───────────
  useEffect(() => {
    if (!manifest?.transportUrl || !initialData?.collections) return;
    const discoverCol = initialData.collections.find(c => c.name.toLowerCase() === 'discover');
    if (!discoverCol?.folders) return;

    setDiscoverRows([]);
    discoverCol.folders.forEach(folder => {
      if (MAIN_NAMES.some(n => n.toLowerCase() === folder.name.toLowerCase())) return;
      const folderCatalogs = folder.folder_catalogs || [];
      if (folderCatalogs.length === 0) return;

      Promise.allSettled(
        folderCatalogs.map(fc => fetchCatalog(manifest.transportUrl!, fc.media_type, fc.catalog_id))
      ).then(results => {
        const items: MetaPreview[] = [];
        const seen = new Set<string>();
        for (const r of results) {
          if (r.status === 'fulfilled') {
            for (const item of r.value) {
              if (!seen.has(item.id)) { seen.add(item.id); items.push(item); }
            }
          }
        }
        if (items.length === 0) return;
        const row: HomeCatalogRow = {
          id: `discover_${folder.id}`,
          title: folder.name,
          type: folderCatalogs[0]?.media_type || 'movie',
          catalogId: folder.id,
          items: items.slice(0, 30),
          isMainRow: false,
          coverImage: folder.cover_image || undefined,
        };
        setDiscoverRows(prev => {
          if (prev.some(r => r.id === row.id)) return prev;
          return [...prev, row];
        });
      });
    });
  }, [initialData?.collections, manifest?.id, manifest?.transportUrl]);

  // ── Fix D: CW uses poster/name from DB (no fetchMeta needed) ─────────────
  const continueWatching = (initialData?.progress ?? [])
    .filter(e => !e.completed && e.position_seconds > 0)
    .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
    .slice(0, 10);

  const collectionSections: Collection[] = (initialData?.collections ?? [])
    .filter(c => c.name.toLowerCase() !== 'discover')
    .map(c => ({ ...c, folders: (c.folders || []).filter(f => (f.folder_catalogs?.length ?? 0) > 0 || f.cover_image) }))
    .filter(c => (c.folders?.length ?? 0) > 0);

  const mainRows = rows.filter(r => r.isMainRow);
  const hasSystemAddon = !!initialData?.systemAddon?.manifest_url;

  if (initialLoading) {
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
      {featuredItems.length > 0 && (
        <div className="-mt-14"
          onMouseEnter={() => { heroPausedRef.current = true; }}
          onMouseLeave={() => { heroPausedRef.current = false; }}>
          <HomeHero
            featuredItems={featuredItems}
            activeIndex={featuredIndex}
            metas={featuredMetas}
            onIndexChange={setFeaturedIndex}
          />
        </div>
      )}

      <div className="px-6 pb-12">
        {/* Continue Watching — poster/name come from DB, no extra fetches */}
        {continueWatching.length > 0 && (
          <section className="mb-10">
            <h2 className="text-base font-semibold text-white mb-4">Continue Watching</h2>
            <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
              {continueWatching.map(item => {
                const pct = item.duration_seconds > 0
                  ? Math.round((item.position_seconds / item.duration_seconds) * 100)
                  : 0;
                return (
                  <Link key={item.id} to="/browse/$type/$id" params={{ type: item.media_type, id: item.media_id.split(':')[0] }}
                    className="flex-shrink-0 w-48 group cursor-pointer">
                    <div className="relative h-[108px] bg-luna-elevated rounded-xl overflow-hidden mb-2">
                      {item.poster && (
                        <img src={item.poster} alt={item.name || item.media_id}
                          className="absolute inset-0 w-full h-full object-cover" loading="lazy" />
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
                      {item.name || decodeURIComponent(item.media_id.split(':')[0])}
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

        {!hasSystemAddon ? (
          <div className="flex flex-col items-center justify-center py-32 text-luna-muted">
            <p className="text-sm">No system addon configured.</p>
            <p className="text-xs mt-1 opacity-60">Ask your admin to set up an addon in the admin panel.</p>
          </div>
        ) : null}

        {mainRows.map(row => <MediaRow key={row.id} title={row.title} items={row.items} />)}
        {discoverRows.map(row => <MediaRow key={row.id} title={row.title} items={row.items} />)}
        {collectionSections.map(section => <CollectionRow key={section.id} collection={section} />)}
      </div>
    </Sidebar>
  );
}
