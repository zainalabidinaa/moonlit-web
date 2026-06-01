import type { AddonManifest, FeaturedHomeItem, HomeCatalogRow, MetaPreview } from '@/lib/types';

const INITIAL_CATALOG_LIMIT = 4;

export const MAIN_ROW_NAMES = [
  'Popular Movies',
  'Popular TV Shows',
  'Trending Movies',
  'Trending TV Shows',
] as const;

export function selectInitialCatalogs(manifest: AddonManifest): NonNullable<AddonManifest['catalogs']> {
  return [...(manifest.catalogs || [])]
    .map((catalog, index) => ({ catalog, index, score: scoreCatalog(catalog) }))
    .sort((a, b) => {
      if (b.score !== a.score) {
        return b.score - a.score;
      }

      return a.index - b.index;
    })
    .slice(0, INITIAL_CATALOG_LIMIT)
    .map(({ catalog }) => catalog);
}

export function buildHomeRows(
  manifest: AddonManifest,
  catalogItemsById: Record<string, MetaPreview[]>
): HomeCatalogRow[] {
  return (manifest.catalogs || [])
    .map((catalog) => {
      const items =
        catalogItemsById[`${catalog.type}:${catalog.id}`] ||
        catalogItemsById[catalog.id] ||
        [];

      if (items.length === 0) {
        return null;
      }

      const title = catalog.name || catalog.id;
      const isMainRow = MAIN_ROW_NAMES.some(
        n => title.toLowerCase() === n.toLowerCase()
      );

      return {
        id: `${manifest.id}_${catalog.type}_${catalog.id}`,
        title,
        type: catalog.type,
        catalogId: catalog.id,
        items,
        isMainRow,
      } as HomeCatalogRow;
    })
    .filter((row): row is HomeCatalogRow => row !== null);
}

export function pickFeaturedItem(rows: HomeCatalogRow[]): FeaturedHomeItem | null {
  const bestRow = rows.reduce<{ row: HomeCatalogRow; score: number } | null>((best, row) => {
    if (row.items.length === 0) {
      return best;
    }

    const score = scoreRow(row);

    if (!best || score > best.score) {
      return { row, score };
    }

    return best;
  }, null)?.row;

  if (!bestRow) {
    return null;
  }

  return {
    row: bestRow,
    item: bestRow.items[0],
  };
}

export function pickFeaturedItems(rows: HomeCatalogRow[]): FeaturedHomeItem[] {
  const mainRows = rows.filter(r =>
    MAIN_ROW_NAMES.some(n => r.title.toLowerCase() === n.toLowerCase())
  );
  const seen = new Set<string>();
  const candidates: FeaturedHomeItem[] = [];
  for (const row of mainRows) {
    for (const item of row.items) {
      if (!seen.has(item.id)) {
        seen.add(item.id);
        candidates.push({ row, item });
      }
    }
  }
  return candidates
    .sort((a, b) => (b.item.popularity ?? 0) - (a.item.popularity ?? 0))
    .slice(0, 5);
}

function scoreRow(row: HomeCatalogRow): number {
  return scoreCatalogLike(row.title, row.catalogId, row.type);
}

function scoreCatalog(catalog: NonNullable<AddonManifest['catalogs']>[number]): number {
  return scoreCatalogLike(catalog.name || catalog.id, catalog.id, catalog.type);
}

function scoreCatalogLike(title: string, id: string, type: string): number {
  const text = `${title} ${id} ${type}`.toLowerCase();
  let score = 0;

  if (text.includes('featured')) score += 3;
  if (text.includes('popular')) score += 4;
  if (text.includes('trending')) score += 4;
  if (type === 'movie' || type === 'series') score += 2;

  return score;
}
