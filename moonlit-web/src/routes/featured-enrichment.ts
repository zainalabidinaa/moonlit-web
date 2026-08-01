import { useQuery } from '@tanstack/react-query';

import { fetchMeta } from '@/lib/stremio';
import { TMDB_API_KEY } from '@/lib/supabase';
import type { AddonManifest, FeaturedHomeItem, MetaDetail } from '@/lib/types';

export interface FeaturedEnrichment {
  metas: Record<string, MetaDetail | null>;
  backdrops: Record<string, string>;
  awards: Record<string, string>;
}

const emptyEnrichment: FeaturedEnrichment = { metas: {}, backdrops: {}, awards: {} };

function supportsMeta(addon: AddonManifest): boolean {
  return Boolean(addon.transportUrl && addon.resources?.some(resource =>
    (typeof resource === 'string' ? resource : resource.name) === 'meta'));
}

async function loadFirstMeta(
  item: FeaturedHomeItem,
  addons: AddonManifest[],
): Promise<MetaDetail | null> {
  for (const addon of addons.filter(supportsMeta)) {
    const meta = await fetchMeta(addon.transportUrl!, item.item.type, item.item.id);
    if (meta) return meta;
  }
  return null;
}

async function loadTmdbBackdrop(item: FeaturedHomeItem, meta: MetaDetail | null): Promise<string | null> {
  const tmdbType = item.item.type === 'series' ? 'tv' : 'movie';
  if (meta?.tmdbId) {
    const response = await fetch(
      `https://api.themoviedb.org/3/${tmdbType}/${meta.tmdbId}?api_key=${TMDB_API_KEY}`,
    );
    if (!response.ok) return null;
    const payload = await response.json();
    return payload.backdrop_path ? `https://image.tmdb.org/t/p/w1280${payload.backdrop_path}` : null;
  }
  if (!item.item.id.startsWith('tt')) return null;
  const response = await fetch(
    `https://api.themoviedb.org/3/find/${item.item.id}?api_key=${TMDB_API_KEY}&external_source=imdb_id`,
  );
  if (!response.ok) return null;
  const payload = await response.json();
  const hit = tmdbType === 'tv' ? payload.tv_results?.[0] : payload.movie_results?.[0];
  return hit?.backdrop_path ? `https://image.tmdb.org/t/p/w1280${hit.backdrop_path}` : null;
}

export async function loadFeaturedEnrichment(
  featuredItems: FeaturedHomeItem[],
  addons: AddonManifest[],
): Promise<FeaturedEnrichment> {
  const settled = await Promise.allSettled(featuredItems.map(async featured => {
    const meta = await loadFirstMeta(featured, addons);
    const backdrop = featured.item.banner || meta?.background || await loadTmdbBackdrop(featured, meta);
    const awards = meta?.awards?.filter(Boolean).join(' · ') || featured.item.awards;
    return { id: featured.item.id, meta, backdrop, awards };
  }));

  const result: FeaturedEnrichment = { metas: {}, backdrops: {}, awards: {} };
  for (const entry of settled) {
    if (entry.status !== 'fulfilled') continue;
    result.metas[entry.value.id] = entry.value.meta;
    if (entry.value.backdrop) result.backdrops[entry.value.id] = entry.value.backdrop;
    if (entry.value.awards) result.awards[entry.value.id] = entry.value.awards;
  }
  return result;
}

export function useFeaturedEnrichment(featuredItems: FeaturedHomeItem[], addons: AddonManifest[]): FeaturedEnrichment {
  const featuredKey = featuredItems.map(featured => `${featured.item.type}:${featured.item.id}`).join(',');
  const addonKey = addons.map(addon => addon.id).join(',');
  const { data = emptyEnrichment } = useQuery({
    queryKey: ['featured-enrichment', featuredKey, addonKey],
    queryFn: () => loadFeaturedEnrichment(featuredItems, addons),
    enabled: featuredItems.length > 0,
    staleTime: 60 * 60 * 1000,
  });
  return data;
}
