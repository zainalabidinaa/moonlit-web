import { OrganizedCollections, DBCollection, DBFolder, DBFolderCatalog, DBFolderSource } from './types';

function totalSourceCount(
  folderId: string,
  folderCatalogs: DBFolderCatalog[],
  folderSources: DBFolderSource[],
): number {
  const catalogs = folderCatalogs.filter(c => c.folderId === folderId).length;
  const sources = folderSources.filter(s => s.folderId === folderId).length;
  return catalogs + sources;
}

export function mergeOrganizedCollections(
  base: OrganizedCollections,
  overlay: OrganizedCollections,
): OrganizedCollections {
  // Build name index for overlay collections
  const overlayByName = new Map<string, typeof overlay>();
  for (const oc of overlay.collections) {
    overlayByName.set(oc.name, overlay);
  }

  const mergedCollections: DBCollection[] = [];
  const mergedFolders: DBFolder[] = [];
  const mergedCatalogs: DBFolderCatalog[] = [];
  const mergedSources: DBFolderSource[] = [];

  // Process base collections in order
  for (const bc of base.collections) {
    const overlayMatch = overlayByName.get(bc.name);
    if (overlayMatch) {
      // Score comparison
      const baseFolders = base.folders.filter(f => f.collectionId === bc.id);
      const overlayColl = overlayMatch.collections.find(c => c.name === bc.name)!;
      const overlayFolders = overlayMatch.folders.filter(f => f.collectionId === overlayColl.id);

      const baseScore = baseFolders.length * 1000 +
        baseFolders.reduce((s, f) => s + totalSourceCount(f.id, base.folderCatalogs, base.folderSources), 0);
      const overlayScore = overlayFolders.length * 1000 +
        overlayFolders.reduce((s, f) => s + totalSourceCount(f.id, overlayMatch.folderCatalogs, overlayMatch.folderSources), 0);

      if (overlayScore >= baseScore) {
        // Use overlay for this collection
        pushCollectionSubtree(overlayColl, overlayFolders, overlayMatch, mergedCollections, mergedFolders, mergedCatalogs, mergedSources);
      } else {
        // Keep base
        pushCollectionSubtree(bc, baseFolders, base, mergedCollections, mergedFolders, mergedCatalogs, mergedSources);
      }
      overlayByName.delete(bc.name);
    } else {
      // No overlay match — keep base
      const baseFolders = base.folders.filter(f => f.collectionId === bc.id);
      pushCollectionSubtree(bc, baseFolders, base, mergedCollections, mergedFolders, mergedCatalogs, mergedSources);
    }
  }

  // Append remaining overlay-only collections
  for (const oc of overlay.collections) {
    if (overlayByName.has(oc.name)) {
      const overlayFolders = overlay.folders.filter(f => f.collectionId === oc.id);
      pushCollectionSubtree(oc, overlayFolders, overlay, mergedCollections, mergedFolders, mergedCatalogs, mergedSources);
    }
  }

  // Re-sort: pinToTop first, then sortOrder
  mergedCollections.sort((a, b) => {
    if (a.pinToTop && !b.pinToTop) return -1;
    if (!a.pinToTop && b.pinToTop) return 1;
    return a.sortOrder - b.sortOrder;
  });

  return {
    collections: mergedCollections,
    folders: mergedFolders,
    folderCatalogs: mergedCatalogs,
    folderSources: mergedSources,
  };
}

function pushCollectionSubtree(
  collection: DBCollection,
  folders: DBFolder[],
  source: OrganizedCollections,
  outColls: DBCollection[],
  outFolders: DBFolder[],
  outCatalogs: DBFolderCatalog[],
  outSources: DBFolderSource[],
) {
  outColls.push(collection);
  for (const f of folders) {
    outFolders.push(f);
    source.folderCatalogs.filter(c => c.folderId === f.id).forEach(c => outCatalogs.push(c));
    source.folderSources.filter(s => s.folderId === f.id).forEach(s => outSources.push(s));
  }
}
