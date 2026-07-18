import { OrganizedCollections, CatalogRow, AddonManifest, MetaPreview } from './types';
export type { CatalogRow };
import { parseOrganizerJSON } from './parser';
import { mergeOrganizedCollections } from './merge';
import { buildCollectionRows } from './builder';
import { fetchCatalog } from './fetcher';
import { CollectionDisplayPreferencesStore } from './preferences';
import { fetchCatalog as stremioFetchCatalog } from '@/lib/stremio';

const BUNDLED_JSON_PATH = '/home-organizer.json';
const CACHE_KEY = 'moonlit.organizedCollections';
export const ORGANIZER_FUNCTION_URL = 'https://hvfsntdyowapjxobtyli.supabase.co/functions/v1/home-organizer';

export async function fetchLiveOrganizer(): Promise<OrganizedCollections | null> {
  try {
    const res = await fetch(ORGANIZER_FUNCTION_URL);
    if (!res.ok) return null;
    const json = await res.json();
    return parseOrganizerJSON(json);
  } catch {
    return null;
  }
}

let currentOrganized: OrganizedCollections | null = null;
let cachedRows: CatalogRow[] | null = null;

export async function loadCollections(
  addons: AddonManifest[],
  tmdbApiKey?: string,
): Promise<CatalogRow[]> {
  const prefs = CollectionDisplayPreferencesStore.load();

  // 1. Load bundled JSON
  let base: OrganizedCollections | null = null;
  try {
    const res = await fetch(BUNDLED_JSON_PATH);
    if (res.ok) {
      const json = await res.json();
      base = parseOrganizerJSON(json);
    }
  } catch {
    // Ignore missing or malformed bundled organizer data.
  }

  // 2. Check IndexedDB for cached remote snapshot
  let cachedRemote: OrganizedCollections | null = null;
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (raw) cachedRemote = parseOrganizerJSON(JSON.parse(raw));
  } catch {
    // Ignore missing or malformed cached organizer data.
  }

  // 3. Merge
  let merged: OrganizedCollections;
  if (base && cachedRemote) {
    merged = mergeOrganizedCollections(base, cachedRemote);
  } else if (base) {
    merged = base;
  } else if (cachedRemote) {
    merged = cachedRemote;
  } else {
    // No collections data — fall back to addon catalogs
    return buildFallbackRows(addons);
  }

  currentOrganized = merged;

  // 4. Build rows
  const rows = await buildCollectionRows({
    organized: merged,
    prefs,
    addons,
    tmdbApiKey,
  });

  cachedRows = rows;
  return rows;
}

export async function refreshCollections(
  organized: OrganizedCollections,
  addons: AddonManifest[],
  tmdbApiKey?: string,
): Promise<CatalogRow[]> {
  // Merge new remote data with current
  if (currentOrganized) {
    currentOrganized = mergeOrganizedCollections(currentOrganized, organized);
  } else {
    currentOrganized = organized;
  }

  // Cache to localStorage
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(currentOrganized));
  } catch {
    // Ignore cache write failures.
  }

  const prefs = CollectionDisplayPreferencesStore.load();
  const rows = await buildCollectionRows({
    organized: currentOrganized,
    prefs,
    addons,
    tmdbApiKey,
  });

  cachedRows = rows;
  return rows;
}

function buildFallbackRows(
  addons: AddonManifest[],
): CatalogRow[] {
  const rows: CatalogRow[] = [];
  const seenRowIds = new Set<string>();
  for (const addon of addons) {
    if (!addon.transportUrl || !addon.catalogs) continue;
    for (const catalog of addon.catalogs) {
      const rowId = `${addon.id}-${catalog.type}-${catalog.id}`;
      if (seenRowIds.has(rowId)) continue;
      seenRowIds.add(rowId);
      rows.push({
        id: rowId,
        title: catalog.name ?? catalog.id,
        items: [],
        addonName: addon.name,
        page: 0,
        hasMore: true,
      });
    }
  }
  return rows;
}

export function getCurrentOrganized(): OrganizedCollections | null {
  return currentOrganized;
}

export function getCachedRows(): CatalogRow[] | null {
  return cachedRows;
}

export interface ResolvedFolder {
  id: string;
  name: string;
  collectionId: string;
  coverImage?: string;
  titleLogo?: string;
  heroBackdrop?: string;
  heroVideoUrl?: string;
  hideTitle?: boolean;
  tileShape?: string;
  focusGif?: string;
  focusGifEnabled?: boolean;
  catalogs: import('./types').DBFolderCatalog[];
  sources: import('./types').DBFolderSource[];
}

export function resolveFolderFromOrganizer(folderId: string): ResolvedFolder | null {
  if (!currentOrganized) return null;

  const folder = currentOrganized.folders.find(f => f.id === folderId);
  if (!folder) return null;

  const catalogs = currentOrganized.folderCatalogs.filter(c => c.folderId === folder.id);
  const sources = currentOrganized.folderSources.filter(s => s.folderId === folder.id);

  return {
    id: folder.id,
    name: folder.name,
    collectionId: folder.collectionId,
    coverImage: folder.coverImage,
    titleLogo: folder.titleLogo,
    heroBackdrop: folder.heroBackdrop,
    heroVideoUrl: folder.heroVideoUrl,
    hideTitle: folder.hideTitle,
    tileShape: folder.tileShape,
    focusGif: folder.focusGif,
    focusGifEnabled: folder.focusGifEnabled,
    catalogs,
    sources,
  };
}

export async function loadFolderItems(folderId: string): Promise<{ items: MetaPreview[] }> {
  if (cachedRows) {
    const row = cachedRows.find(r => r.id === folderId || r.folderId === folderId || r.collectionId === folderId);
    if (row && row.items.length > 0) {
      return { items: row.items };
    }
  }

  if (currentOrganized) {
    const folder = currentOrganized.folders.find(f => f.id === folderId);
    if (folder) {
      const folderCatalogs = currentOrganized.folderCatalogs.filter(c => c.folderId === folder.id);
      const allItems: MetaPreview[] = [];
      for (const cat of folderCatalogs) {
        try {
          const loadedItems = loadAddonsFromLocalStorage();
          const addon = loadedItems.find((a: AddonManifest) =>
            a.transportUrl && a.catalogs?.some(ac => ac.id === cat.catalogId || ac.type === cat.catalogId)
          );
          if (addon?.transportUrl) {
            const items = await fetchCatalog({
              baseURL: addon.transportUrl,
              type: cat.mediaType || 'movie',
              id: cat.catalogId,
            });
            allItems.push(...items);
          }
        } catch {}
      }
      if (allItems.length > 0) {
        return { items: allItems };
      }
    }
  }

  const loadedAddons = loadAddonsFromLocalStorage();
  for (const addon of loadedAddons) {
    if (!addon.transportUrl || !addon.catalogs) continue;
    for (const catalog of addon.catalogs) {
      if (catalog.id === folderId) {
        try {
          const items = await stremioFetchCatalog(addon.transportUrl, catalog.type || 'movie', catalog.id);
          if (items.length > 0) return { items };
        } catch {}
      }
    }
    try {
      const items = await stremioFetchCatalog(addon.transportUrl, 'movie', folderId);
      if (items.length > 0) return { items };
    } catch {}
  }

  return { items: [] };
}

function loadAddonsFromLocalStorage(): AddonManifest[] {
  try {
    const raw = localStorage.getItem('moonlit.addons');
    if (!raw) return [];
    const data = JSON.parse(raw);
    return data.map((a: any) => a.manifest).filter(Boolean);
  } catch {
    return [];
  }
}
