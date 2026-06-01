'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '../AuthProvider';
import { useRouter } from 'next/navigation';
import { Sidebar } from '@/components/Sidebar';
import { MediaRow } from '@/components/MediaRow';
import { FeaturedHomeItem, HomeCatalogRow, MetaDetail, WatchProgressEntry } from '@/lib/types';
import { getWatchProgress, getSystemAddon } from '@/lib/services/api';
import { fetchCatalog, fetchManifest, fetchMeta } from '@/lib/stremio';
import { buildHomeRows, pickFeaturedItem } from './home-data';
import Link from 'next/link';

export default function HomePage() {
  const { currentProfile, user, isLoading } = useAuth();
  const router = useRouter();
  const [rows, setRows] = useState<HomeCatalogRow[]>([]);
  const [featured, setFeatured] = useState<FeaturedHomeItem | null>(null);
  const [featuredMeta, setFeaturedMeta] = useState<MetaDetail | null>(null);
  const [hasSystemAddon, setHasSystemAddon] = useState(true);
  const [continueWatching, setContinueWatching] = useState<WatchProgressEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    if (!currentProfile) { router.replace('/profiles'); return; }
    loadData();
  }, [currentProfile, isLoading, user, router]);

  async function loadData() {
    setLoading(true);
    try {
      const [progress, systemAddon] = await Promise.all([
        getWatchProgress(currentProfile!.id),
        getSystemAddon(),
      ]);

      setContinueWatching(
        progress
          .filter((entry) => !entry.completed && entry.position_seconds > 0)
          .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
      );

      if (!systemAddon?.manifest_url) {
        setHasSystemAddon(false);
        setRows([]);
        setFeatured(null);
        setFeaturedMeta(null);
        return;
      }

      setHasSystemAddon(true);

      const manifest = await fetchManifest(systemAddon.manifest_url);
      if (!manifest.transportUrl) {
        setRows([]);
        setFeatured(null);
        setFeaturedMeta(null);
        return;
      }

      const allCatalogs = manifest.catalogs || [];
      const catalogResults = await Promise.allSettled(
        allCatalogs.map(async (catalog) => {
          const extras: Record<string, string> = {};
          if (catalog.extra) {
            for (const e of catalog.extra) {
              if (e.options && e.options.length > 0) {
                extras[e.name] = e.options[0];
              }
            }
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
        if (result.status !== 'fulfilled') {
          continue;
        }

        catalogItemsById[result.value.key] = result.value.items;
        if (!(result.value.fallbackKey in catalogItemsById)) {
          catalogItemsById[result.value.fallbackKey] = result.value.items;
        }
      }

      const nextRows = buildHomeRows(manifest, catalogItemsById);
      const nextFeatured = pickFeaturedItem(nextRows);

      setRows(nextRows);
      setFeatured(nextFeatured);

      const canFetchMeta = manifest.resources?.some((resource) =>
        (typeof resource === 'string' ? resource : resource.name) === 'meta'
      );

      if (nextFeatured && canFetchMeta) {
        setFeaturedMeta(await fetchMeta(manifest.transportUrl, nextFeatured.item.type, nextFeatured.item.id));
      } else {
        setFeaturedMeta(null);
      }
    } catch {
      setRows([]);
      setFeatured(null);
      setFeaturedMeta(null);
    } finally {
      setLoading(false);
    }
  }

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
      <div className="px-6 pt-24 pb-12">
        {featured && (
          <section className="mb-10 rounded-3xl border border-white/10 bg-luna-elevated/70 p-6">
            <p className="text-xs uppercase tracking-[0.2em] text-luna-muted mb-3">Featured</p>
            <div className="flex flex-col gap-6 md:flex-row md:items-center">
              {featured.item.poster && (
                <img
                  src={featured.item.poster}
                  alt={featured.item.name}
                  className="h-56 w-40 rounded-2xl object-cover bg-luna-bg"
                />
              )}
              <div className="max-w-2xl">
                <h1 className="text-3xl font-bold text-white">{featuredMeta?.name || featured.item.name}</h1>
                <p className="mt-2 text-sm text-luna-muted">
                  From {featured.row.title}
                  {featuredMeta?.imdbRating ? ` • IMDb ${featuredMeta.imdbRating}` : ''}
                  {featuredMeta?.runtime ? ` • ${featuredMeta.runtime}` : ''}
                </p>
                {(featuredMeta?.description || featured.item.description) && (
                  <p className="mt-4 max-w-xl text-sm leading-6 text-luna-muted/90">
                    {featuredMeta?.description || featured.item.description}
                  </p>
                )}
                <div className="mt-5">
                  <Link
                    href={`/browse/${featured.item.type}/${featured.item.id}`}
                    className="inline-flex items-center rounded-full bg-white px-5 py-2.5 text-sm font-semibold text-black transition-colors hover:bg-white/90"
                  >
                    Open title
                  </Link>
                </div>
              </div>
            </div>
          </section>
        )}

        {/* Continue Watching */}
        {continueWatching.length > 0 && (
          <section className="mb-10">
            <h2 className="text-base font-semibold text-white mb-4">Continue Watching</h2>
            <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
              {continueWatching.slice(0, 10).map((item) => {
                const pct = item.duration_seconds > 0
                  ? (item.position_seconds / item.duration_seconds) * 100
                  : 0;
                return (
                  <Link
                    key={item.media_id}
                    href={`/browse/${item.media_type}/${item.media_id}`}
                    className="flex-shrink-0 w-48 group cursor-pointer"
                  >
                    <div className="relative h-28 bg-luna-elevated rounded-xl overflow-hidden mb-2">
                      <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-white/10">
                        <div className="h-full bg-luna-accent transition-all" style={{ width: `${pct}%` }} />
                      </div>
                      <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity duration-200 flex items-center justify-center">
                        <div className="w-10 h-10 rounded-full bg-white/20 backdrop-blur-sm flex items-center justify-center">
                          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 ml-0.5">
                            <path fillRule="evenodd" d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.348c1.295.712 1.295 2.573 0 3.285L7.28 19.991c-1.25.687-2.779-.217-2.779-1.643V5.653z" clipRule="evenodd" />
                          </svg>
                        </div>
                      </div>
                    </div>
                    <p className="text-xs text-luna-muted truncate">{item.media_id}</p>
                    <p className="text-xs text-luna-muted/60 mt-0.5">{Math.round(pct)}% watched</p>
                  </Link>
                );
              })}
            </div>
          </section>
        )}

        {hasSystemAddon ? (
          rows.length > 0 ? (
            rows.map((row, i) => (
              <MediaRow key={row.id} title={row.title} items={row.items} defaultCollapsed={i < 4} />
            ))
          ) : (
            <div className="flex flex-col items-center justify-center py-32 text-luna-muted">
              <p className="text-sm">No home catalogs available yet.</p>
              <p className="text-xs mt-1 opacity-60">The configured addon did not return any initial rows.</p>
            </div>
          )
        ) : (
          <div className="flex flex-col items-center justify-center py-32 text-luna-muted">
            <p className="text-sm">No system addon configured.</p>
            <p className="text-xs mt-1 opacity-60">Ask your admin to set up an addon in the admin panel.</p>
          </div>
        )}

      </div>
    </Sidebar>
  );
}
