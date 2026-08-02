import type { AddonManifest } from '@/lib/types';
import { deduplicateItems } from './builder';
import { fetchCatalog } from './fetcher';
import type { BrowseRail, LoadedBrowseRail } from './genre-catalog';

/**
 * Resolves an organizer-driven BrowseRail's synthesized catalog ids
 * ("tmdb.discover.movie.new-movies.<hash>", "trakt.list.<id>", etc.) into real
 * items via whichever addon serves catalogs. Mirrors
 * CatalogRepository.swift's fetchFolderItems, scoped to a single page — genre
 * hub rails are a discovery surface, not Home, so exhaustive pagination isn't
 * the priority the way it is for Home rows.
 */
export async function resolveBrowseRail(
  rail: BrowseRail,
  addons: AddonManifest[],
): Promise<LoadedBrowseRail | null> {
  const fallbackURL = addons.find(a =>
    a.transportUrl && (a.transportUrl.includes('aiometadata') || a.id.includes('aio')),
  )?.transportUrl ?? addons.find(a => a.transportUrl)?.transportUrl;
  if (!fallbackURL) return null;

  const results = await Promise.all(rail.catalogs.map(async catalog => {
    const baseURL = addons.find(a => a.catalogs?.some(ac => ac.id === catalog.catalogId))?.transportUrl ?? fallbackURL;
    const mediaTypes = catalog.mediaType === 'all' ? ['movie', 'series'] : [catalog.mediaType || 'movie'];
    const perType = await Promise.all(mediaTypes.map(type => fetchCatalog({ baseURL, type, id: catalog.catalogId })));
    return perType.flat();
  }));

  const items = deduplicateItems(results.flat());
  if (items.length === 0) return null;
  return { id: rail.id, title: rail.title, items };
}

export async function resolveBrowseRails(
  rails: BrowseRail[],
  addons: AddonManifest[],
): Promise<LoadedBrowseRail[]> {
  const resolved = await Promise.all(rails.map(rail => resolveBrowseRail(rail, addons)));
  return resolved.filter((rail): rail is LoadedBrowseRail => rail !== null);
}
