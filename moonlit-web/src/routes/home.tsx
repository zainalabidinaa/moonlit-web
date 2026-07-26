import { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import { usePlayer } from '@/app/PlayerProvider';
import { HomeHero } from '@/components/HomeHero';
import { FusionBackground } from '@/components/FusionBackground';
import { MediaRow } from '@/components/MediaRow';
import { CollectionRow } from '@/components/CollectionRow';
import { FeaturedHomeItem, MetaDetail, WatchProgressEntry } from '@/lib/types';
import { getWatchProgress, getSystemAddon } from '@/lib/services/api';
import { fetchManifest, fetchMeta } from '@/lib/stremio';
import { TMDB_API_KEY } from '@/lib/supabase';
import { formatContinueWatchingTitle } from '@/lib/player-utils';
import { loadCollections, refreshCollections, fetchLiveOrganizer } from '@/lib/collections/repository';
import { useQueryClient } from '@tanstack/react-query';
import { pickFeaturedItems } from './home-data';
import { motion } from 'framer-motion';
import { SPRING, TILE_HOVER_SCALE } from '@/lib/design/motion';

function formatTime(pos: number, dur: number): string {
  if (dur > 0) { const l = Math.max(0, dur - pos); const m = Math.round(l / 60); if (m <= 0) return 'Almost done'; if (m < 60) return `${m} min left`; return `${Math.floor(m/60)}h ${m%60}m left`; }
  const m = Math.round(pos / 60); return m < 60 ? `${m} min watched` : `${Math.floor(m/60)}h ${m%60}m watched`;
}

export default function HomePage() {
  const { currentProfile, addons } = useAuth();
  const { open: openPlayer } = usePlayer();
  const queryClient = useQueryClient();
  const heroRef = useRef<HTMLDivElement>(null);
  const [heroHeight, setHeroHeight] = useState(0);
  useEffect(() => { if (heroRef.current) setHeroHeight(heroRef.current.getBoundingClientRect().height); }, []);

  const [featuredItems, setFeaturedItems] = useState<FeaturedHomeItem[]>([]);
  const [featuredMetas, setFeaturedMetas] = useState<Record<string, MetaDetail | null>>({});
  const [featuredBackdrops, setFeaturedBackdrops] = useState<Record<string, string>>({});
  const [featuredIndex, setFeaturedIndex] = useState(0);
  const heroTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const heroPausedRef = useRef(false);
  useEffect(() => {
    if (featuredItems.length <= 1) return;
    heroTimerRef.current = setInterval(() => { if (!heroPausedRef.current) setFeaturedIndex(p => (p + 1) % featuredItems.length); }, 60000);
    return () => { if (heroTimerRef.current) clearInterval(heroTimerRef.current); };
  }, [featuredItems.length]);

  const { data: initialData, isLoading: initialLoading } = useQuery({
    queryKey: ['home-initial', currentProfile?.id], enabled: !!currentProfile, staleTime: 5 * 60 * 1000,
    queryFn: async () => { const [p, sa] = await Promise.all([getWatchProgress(currentProfile!.id), getSystemAddon()]); return { progress: p, systemAddon: sa }; },
  });
  const { data: manifest } = useQuery({
    queryKey: ['manifest', initialData?.systemAddon?.manifest_url], enabled: !!initialData?.systemAddon?.manifest_url, staleTime: 5 * 60 * 1000,
    queryFn: () => fetchManifest(initialData!.systemAddon!.manifest_url),
  });
  const { data: collectionRows = [], isLoading: collectionsLoading } = useQuery({
    queryKey: ['home-collections', currentProfile?.id, addons.map(a => a.id).join(',')], enabled: addons.length > 0, staleTime: 5 * 60 * 1000,
    queryFn: async () => addons.length === 0 ? [] : loadCollections(addons, TMDB_API_KEY),
  });
  const ck = ['home-collections', currentProfile?.id, addons.map(a => a.id).join(',')];
  useEffect(() => {
    if (collectionsLoading || addons.length === 0) return; let cancelled = false;
    (async () => { const o = await fetchLiveOrganizer(); if (cancelled || !o) return; const r = await refreshCollections(o, addons, TMDB_API_KEY); if (!cancelled) queryClient.setQueryData(ck, r); })();
    return () => { cancelled = true; };
  }, [collectionsLoading, addons.length]);

  useEffect(() => {
    const rows = collectionRows.filter(r => !r.isGroupTile).map(r => ({ id: r.id, title: r.title, type: r.items[0]?.type || 'movie', catalogId: r.id, items: r.items, isMainRow: r.title ? ['Popular Movies','Popular TV Shows','Trending Movies','Trending TV Shows','Popular Shows','Trending Shows','Latest','Top Rated'].some(n => n.toLowerCase() === r.title.toLowerCase()) : false }));
    const next = pickFeaturedItems(rows); if (next.length > 0) { setFeaturedItems(next); setFeaturedIndex(0); }
  }, [collectionRows]);

  useEffect(() => {
    if (featuredItems.length === 0) return; let cancelled = false;
    Promise.allSettled(featuredItems.map(async fi => {
      if (!fi.item.id.startsWith('tt')) return null;
      const r = await fetch(`https://api.themoviedb.org/3/find/${fi.item.id}?api_key=${TMDB_API_KEY}&external_source=imdb_id`);
      if (!r.ok) return null; const d = await r.json(); const h = (fi.item.type === 'series' ? d.tv_results?.[0] : d.movie_results?.[0]);
      return h?.backdrop_path ? { id: fi.item.id, url: `https://image.tmdb.org/t/p/w1280${h.backdrop_path}` } : null;
    })).then(r => { if (cancelled) return; const m: Record<string,string> = {}; for (const x of r) if (x.status === 'fulfilled' && x.value) m[x.value.id] = x.value.url; setFeaturedBackdrops(m); });
    return () => { cancelled = true; };
  }, [featuredItems]);

  useEffect(() => {
    if (!manifest?.transportUrl || featuredItems.length === 0) return;
    if (!manifest.resources?.some(r => (typeof r === 'string' ? r : r.name) === 'meta')) return;
    const ctrl = new AbortController();
    Promise.allSettled(featuredItems.map(async fi => ({ id: fi.item.id, meta: await fetchMeta(manifest.transportUrl!, fi.item.type, fi.item.id) })))
      .then(r => { if (ctrl.signal.aborted) return; const m: Record<string,MetaDetail|null> = {}; for (const x of r) if (x.status === 'fulfilled') m[x.value.id] = x.value.meta; setFeaturedMetas(m); });
    return () => ctrl.abort();
  }, [featuredItems, manifest?.transportUrl]);

  const cw = (() => {
    const seen = new Set<string>();
    return (initialData?.progress ?? []).filter(e => !e.completed && e.position_seconds > 0).map(e => ({ ...e, media_id: decodeURIComponent(e.media_id) })).sort((a,b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()).filter(e => { const b = e.media_id.split(':')[0]; if (seen.has(b)) return false; seen.add(b); return true; }).slice(0, 10);
  })();
  const cwNeedsMeta = cw.filter(e => (e.media_type === 'series' && e.media_id.includes(':')) || (!e.poster && !e.name));
  const { data: cwMetas } = useQuery({
    queryKey: ['cw-meta', cwNeedsMeta.map(e => e.media_id).join(','), manifest?.transportUrl], enabled: cwNeedsMeta.length > 0 && !!manifest?.transportUrl, staleTime: 60 * 60 * 1000,
    queryFn: async () => {
      const r: Record<string,{name?:string;poster?:string}> = {};
      await Promise.allSettled(cwNeedsMeta.map(async e => {
        const p = e.media_id.split(':'); try {
          if (e.media_type === 'series' && parseInt(p[1]) > 0 && manifest?.transportUrl) { const m = await fetchMeta(manifest.transportUrl, e.media_type, p[0]); if (m) { const v = m.videos?.find(v => v.season === parseInt(p[1]) && v.episode === parseInt(p[2])); r[e.media_id] = { name: m.name, poster: v?.thumbnail ?? m.background ?? m.poster ?? undefined }; } }
          else if (manifest?.transportUrl) { const m = await fetchMeta(manifest.transportUrl, e.media_type, p[0]); if (m) r[e.media_id] = { name: m.name, poster: m.poster ?? m.background ?? undefined }; }
        } catch {}
      }));
      return r;
    },
  });

  function handleCwPlay(item: WatchProgressEntry) {
    const fb = cwMetas?.[item.media_id]; const baseId = item.media_id.split(':')[0];
    const dn = item.name ?? fb?.name ?? baseId;
    const poster = (item.media_type === 'series' && item.media_id.includes(':')) ? (fb?.poster ?? item.poster ?? undefined) : (item.poster ?? fb?.poster ?? undefined);
    openPlayer({ type: item.media_type, id: item.media_id, metadata: { mediaId: item.media_id, mediaType: item.media_type, title: formatContinueWatchingTitle({ mediaId: item.media_id, mediaType: item.media_type, name: dn }), logo: featuredMetas[baseId]?.logo ?? undefined, poster, background: featuredMetas[baseId]?.background ?? featuredBackdrops[baseId] ?? undefined }, startPosition: item.position_seconds > 0 ? item.position_seconds : undefined });
  }

  if (initialLoading) return <div className="flex items-center justify-center min-h-screen"><div className="animate-spin rounded-full h-6 w-6 border-2 border-white/20 border-t-white"/></div>;

  const currentBackdrop = featuredItems.length > 0 ? (() => { const f = featuredItems[featuredIndex] ?? featuredItems[0]; const m = featuredMetas[f.item.id] ?? null; return m?.background || featuredBackdrops[f.item.id] || f.item.banner || null; })() : null;

  return (
    <>
      <FusionBackground backdropUrl={currentBackdrop} heroHeight={heroHeight} />

      {featuredItems.length > 0 && (
        <div ref={heroRef} className="-mt-16 relative" onMouseEnter={() => { heroPausedRef.current = true; }} onMouseLeave={() => { heroPausedRef.current = false; }}>
          <HomeHero featuredItems={featuredItems} activeIndex={featuredIndex} metas={featuredMetas} backdrops={featuredBackdrops} onIndexChange={setFeaturedIndex} />
        </div>
      )}

      <div className="px-6 md:px-10 lg:px-14 pb-16">
        {cw.length > 0 && (
          <section className="pt-28 pb-6">
            <h2 className="section-title mb-4">Continue Watching</h2>
            <div className="flex gap-3 overflow-x-auto py-3 -my-3 scrollbar-hide">
              {cw.map(item => {
                const fb = cwMetas?.[item.media_id];
                const poster = (item.media_type === 'series' && item.media_id.includes(':')) ? (fb?.poster ?? item.poster) : (item.poster ?? fb?.poster);
                const name = item.name ?? fb?.name; const parts = item.media_id.split(':');
                const pct = item.duration_seconds > 0 ? Math.min(100, (item.position_seconds / item.duration_seconds) * 100) : 0;
                return (
                  <motion.button key={item.id} whileHover={{ scale: TILE_HOVER_SCALE }} transition={SPRING.continueWatching}
                    onClick={() => handleCwPlay(item)} className="flex-shrink-0 w-80 cursor-pointer text-left">
                    <div className="relative h-44 bg-moonlit-elevated rounded-ml-card overflow-hidden mb-2 border border-white/5 hover:border-white/[0.14] hover:shadow-ml-card transition-shadow duration-300">
                      {poster ? <img src={poster} alt={name || item.media_id} className="absolute inset-0 w-full h-full object-cover" loading="lazy"/> : <div className="absolute inset-0 flex items-center justify-center"><svg className="w-6 h-6 text-white/10" viewBox="0 0 24 24" fill="currentColor"><path d="M4 4h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z"/></svg></div>}
                      <div className="absolute inset-x-0 bottom-0 h-12 backdrop-blur-[3px] [mask-image:linear-gradient(to_top,black_35%,transparent)]" />
                      <div className="absolute inset-x-0 bottom-0 h-1/2 bg-gradient-to-t from-black/75 via-black/15 to-transparent" />
                      <div className="absolute bottom-0 left-0 right-0 h-[3px] bg-white/20"><div className="h-full bg-white transition-all duration-500" style={{ width: `${pct}%` }}/></div>
                      <div className="absolute inset-x-0 bottom-[5px] flex items-end justify-between gap-2 px-3 pb-2.5"><span className="text-[11px] font-bold text-white drop-shadow-md">{item.media_type === 'series' && parts.length >= 3 ? `S${parts[1]} E${parts[2]}` : ''}</span><span className="text-[11px] font-medium text-white/75 drop-shadow-md whitespace-nowrap">{formatTime(item.position_seconds, item.duration_seconds)}</span></div>
                    </div>
                    <p className="text-[13px] text-white font-medium truncate">{name || item.media_id}</p>
                  </motion.button>
                );
              })}
            </div>
          </section>
        )}

        {!initialData?.systemAddon?.manifest_url ? (
          <div className="flex flex-col items-center justify-center py-32 text-moonlit-muted"><p className="text-sm">No system addon configured.</p><p className="text-xs mt-1 opacity-60">Ask your admin to set up an addon in the admin panel.</p></div>
        ) : null}

        {collectionRows.filter(r => r.isGroupTile || r.items.length > 0).map(row => row.isGroupTile ? (
          <CollectionRow key={row.id} titleLogo={row.titleLogo} collection={{ id: row.id, name: row.title, sort_order: 0, focus_glow_enabled: row.focusGlowEnabled, created_at: '', folders: row.items.map((item, i) => ({ id: item.id, name: item.name, collection_id: row.id, sort_order: i, cover_image: item.poster || '', focus_gif: null, focus_gif_enabled: row.focusGifEnabled, tile_shape: ((item.tileShape ?? row.tileShape)?.toUpperCase() as any) || null, created_at: '' })) }}/>
        ) : (
          <MediaRow key={row.id} title={row.title} titleLogo={row.titleLogo} items={row.items} />
        ))}
      </div>
    </>
  );
}
