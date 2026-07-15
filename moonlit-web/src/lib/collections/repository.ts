import { OrganizedCollections, CatalogRow, AddonManifest } from './types';
export type { CatalogRow };
import { parseOrganizerJSON } from './parser';
import { mergeOrganizedCollections } from './merge';
import { buildCollectionRows } from './builder';
import { CollectionDisplayPreferencesStore } from './preferences';

const BUNDLED_JSON_PATH = '/home-organizer.json';
const CACHE_KEY = 'moonlit.organizedCollections';

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
        title: catalog.name!,
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
