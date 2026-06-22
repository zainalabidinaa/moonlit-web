import {
  OrganizedCollections, DBCollection, DBFolder,
  DBFolderCatalog, DBFolderSource,
  CatalogRow, MetaPreview,
  CollectionDisplayPreferences, AddonManifest, AddonCatalog,
} from './types';
import { fetchCatalog, fetchTMDBCollection } from './fetcher';
import { CollectionDisplayPreferencesStore } from './preferences';

interface BuilderOptions {
  organized: OrganizedCollections;
  prefs: CollectionDisplayPreferences;
  addons: AddonManifest[];
  tmdbApiKey?: string;
}

export async function buildCollectionRows(options: BuilderOptions): Promise<CatalogRow[]> {
  const { organized, prefs, addons, tmdbApiKey } = options;
  const rows: CatalogRow[] = [];

  // Sort collections: pinToTop first, then sortOrder
  const sortedCollections = [...organized.collections].sort((a, b) => {
    if (a.pinToTop && !b.pinToTop) return -1;
    if (!a.pinToTop && b.pinToTop) return 1;
    return a.sortOrder - b.sortOrder;
  });

  for (const collection of sortedCollections) {
    // Skip disabled collections
    if (!CollectionDisplayPreferencesStore.isCollectionEnabled(prefs, collection.id)) continue;

    const collectionFolders = organized.folders
      .filter(f => f.collectionId === collection.id && !CollectionDisplayPreferencesStore.isFolderHidden(prefs, f.id))
      .sort((a, b) => a.sortOrder - b.sortOrder);

    if (collectionFolders.length === 0) continue;

    const isExpanded = CollectionDisplayPreferencesStore.isCollectionExpanded(prefs, collection.id);
    const shouldGroup = collectionFolders.length > 1 && !isExpanded;

    if (shouldGroup) {
      // Group tile row — folder cover images as tiles
      const tileItems: MetaPreview[] = collectionFolders.map(f => ({
        id: f.id,
        type: 'folder',
        name: f.name,
        poster: f.coverImage,
      }));
      rows.push({
        id: `collection-group-${collection.id}`,
        title: collection.name,
        items: tileItems,
        page: 0,
        hasMore: false,
        tileShape: 'landscape',
        focusGlowEnabled: collection.focusGlowEnabled,
        viewMode: collection.viewMode,
        showAllTab: collection.showAllTab,
        pinToTop: collection.pinToTop,
        backdropImage: collection.backdropImage,
        isGroupTile: true,
        folderId: collectionFolders[0].id,
        collectionId: collection.id,
      });
    } else {
      // Expanded or single-folder: fetch content
      for (const folder of collectionFolders) {
        const folderCatalogs = organized.folderCatalogs.filter(c => c.folderId === folder.id);
        const folderSources = organized.folderSources.filter(s => s.folderId === folder.id);

        let allItems: MetaPreview[] = [];

        // Fetch addon catalog sources
        for (const cat of folderCatalogs) {
          const addon = addons.find(a =>
            a.transportUrl && a.catalogs?.some(ac => ac.id === cat.catalogId || ac.type === cat.catalogId)
          );
          const baseURL = addon?.transportUrl;
          if (!baseURL) continue;

          const mediaTypes = cat.mediaType === 'all' ? ['movie', 'series'] : [cat.mediaType || 'movie'];
          for (const mt of mediaTypes) {
            const items = await fetchCatalog({
              baseURL,
              type: mt,
              id: cat.catalogId,
              extras: cat.extras,
            });
            allItems = deduplicateItems([...allItems, ...items]);
          }
        }

        // Fetch raw sources (TMDB collections, Trakt lists, etc.)
        for (const src of folderSources) {
          const items = await resolveRawSource(src, addons, tmdbApiKey);
          allItems = deduplicateItems([...allItems, ...items]);
        }

        rows.push({
          id: `folder-${folder.id}`,
          title: folder.hideTitle ? '' : folder.name,
          items: allItems,
          page: 0,
          hasMore: false,
          tileShape: folder.tileShape || 'poster',
          coverImage: folder.coverImage,
          focusGif: folder.focusGif,
          focusGifEnabled: folder.focusGifEnabled,
          titleLogo: folder.titleLogo,
          heroBackdrop: folder.heroBackdrop,
          heroVideoUrl: folder.heroVideoUrl,
          hideTitle: folder.hideTitle,
          collectionId: collection.id,
        });
      }
    }
  }

  // Supplement with addon manifest catalogs not already covered
  const supplemented = supplementWithAddonCatalogs(rows, organized, addons);
  return supplemented;
}

async function resolveRawSource(
  source: DBFolderSource,
  addons: AddonManifest[],
  tmdbApiKey?: string,
): Promise<MetaPreview[]> {
  const { provider, tmdbId, mediaType, tmdbSourceType } = source;

  if (!tmdbId) return [];

  // TMDB collection — direct API
  if (provider === 'tmdb' && tmdbSourceType === 'collection' && tmdbApiKey) {
    return fetchTMDBCollection(tmdbId, tmdbApiKey);
  }

  // Build catalog ID for addon-based raw sources
  let catalogId = '';
  switch (provider) {
    case 'trakt': catalogId = `trakt.list.${tmdbId}`; break;
    case 'tmdb':
      catalogId = tmdbSourceType === 'discover' ? `tmdb.discover.${mediaType}.${tmdbId}` : `tmdb.${tmdbId}`;
      break;
    case 'mdblist': catalogId = `mdblist.${tmdbId}`; break;
    case 'tvdb': catalogId = `tvdb.discover.${mediaType}.${tmdbId}`; break;
    case 'streaming': catalogId = `streaming.${tmdbId}`; break;
    default: return [];
  }

  const mt = mediaType || 'movie';
  // Find an addon that supports catalog resources
  const addon = addons.find(a => a.transportUrl && a.resources?.some(r =>
    (typeof r === 'string' ? r : r.name) === 'catalog'
  ));

  if (!addon?.transportUrl) return [];

  return fetchCatalog({
    baseURL: addon.transportUrl,
    type: mt,
    id: catalogId,
  });
}

function deduplicateItems(items: MetaPreview[]): MetaPreview[] {
  const seen = new Set<string>();
  const result: MetaPreview[] = [];
  for (const item of items) {
    const key = item.id;
    if (!seen.has(key)) {
      seen.add(key);
      result.push(item);
    }
  }
  return result;
}

function supplementWithAddonCatalogs(
  existingRows: CatalogRow[],
  organized: OrganizedCollections,
  addons: AddonManifest[],
): CatalogRow[] {
  // Get IDs already covered by collection rows
  const coveredCatalogIds = new Set<string>();
  for (const cat of organized.folderCatalogs) {
    coveredCatalogIds.add(cat.catalogId);
  }
  for (const src of organized.folderSources) {
    const catId = `${src.provider}.${src.tmdbId}`;
    coveredCatalogIds.add(catId);
  }

  const result = [...existingRows];

  for (const addon of addons) {
    if (!addon.transportUrl || !addon.catalogs) continue;
    for (const catalog of addon.catalogs) {
      if (coveredCatalogIds.has(catalog.id)) continue;
      // Add as a supplementary row — won't show content immediately
      // but marks it for lazy loading
      result.push({
        id: `${addon.id}-${catalog.type}-${catalog.id}`,
        title: catalog.name,
        items: [],
        addonName: addon.name,
        page: 0,
        hasMore: true,
      });
    }
  }

  return result;
}
