import { OrganizedCollections, CatalogRow, CollectionDisplayPreferences, AddonManifest } from './types';
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
  } catch {}

  // 2. Check IndexedDB for cached remote snapshot
  let cachedRemote: OrganizedCollections | null = null;
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (raw) cachedRemote = parseOrganizerJSON(JSON.parse(raw));
  } catch {}

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
    return buildFallbackRows(addons, prefs);
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
  } catch {}

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
  prefs: CollectionDisplayPreferences,
): CatalogRow[] {
  const rows: CatalogRow[] = [];
  for (const addon of addons) {
    if (!addon.transportUrl || !addon.catalogs) continue;
    for (const catalog of addon.catalogs) {
      rows.push({
        id: `${addon.id}-${catalog.type}-${catalog.id}`,
        title: catalog.name,
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
