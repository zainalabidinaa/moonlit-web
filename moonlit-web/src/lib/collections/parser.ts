import {
  OrganizedCollections, DBCollection, DBFolder,
  DBFolderCatalog, DBFolderSource,
  NuvioCollection, NuvioFolder, NuvioSource,
  BESTPack, BESTCollection, BESTFolder, BESTFolderCatalog,
} from './types';
import { resolveNuvioSource } from './resolver';

export function parseOrganizerJSON(json: unknown): OrganizedCollections | null {
  if (!json) return null;

  // Try Nuvio format: array of collections
  if (Array.isArray(json)) {
    return parseNuvio(json as NuvioCollection[]);
  }

  // Try BEST format: flat-pack object
  if (typeof json === 'object' && json !== null) {
    const obj = json as Record<string, unknown>;
    if ('collections' in obj && 'folders' in obj) {
      return parseBEST(obj as unknown as BESTPack);
    }
  }

  return null;
}

function parseNuvio(nuvioCollections: NuvioCollection[]): OrganizedCollections {
  const collections: DBCollection[] = [];
  const folders: DBFolder[] = [];
  const folderCatalogs: DBFolderCatalog[] = [];
  const folderSources: DBFolderSource[] = [];

  for (const nc of nuvioCollections) {
    const collId = nc.id;
    collections.push({
      id: collId,
      name: nc.title,
      sortOrder: collections.length,
      backdropImage: nc.backdropImageUrl,
      viewMode: nc.viewMode,
      showAllTab: nc.showAllTab,
      focusGlowEnabled: nc.focusGlowEnabled,
      pinToTop: nc.pinToTop,
    });

    for (const nf of nc.folders) {
      // Use the folder's specific ID if available, otherwise generate
      const folderId = nf.id || `${collId}-folder-${folders.length}`;
      folders.push({
        id: folderId,
        collectionId: collId,
        name: nf.title,
        sortOrder: folders.length,
        coverImage: nf.coverImageUrl,
        focusGif: nf.focusGifUrl,
        titleLogo: nf.titleLogoUrl,
        heroBackdrop: nf.heroBackdropUrl,
        heroVideoUrl: nf.heroVideoUrl,
        hideTitle: nf.hideTitle,
        tileShape: nf.tileShape,
        focusGifEnabled: nf.focusGifEnabled,
      });

      for (const ns of nf.sources) {
        const resolved = resolveNuvioSource(ns, folderId);
        if (resolved) {
          if (resolved.catalog) folderCatalogs.push(resolved.catalog);
          if (resolved.raw) folderSources.push(resolved.raw);
        }
      }
    }
  }

  return { collections, folders, folderCatalogs, folderSources };
}

function parseBEST(pack: BESTPack): OrganizedCollections {
  const collections: DBCollection[] = (pack.collections || []).map((bc: BESTCollection) => ({
    id: bc.source_key,
    name: bc.name,
    sortOrder: bc.sort_order ?? 0,
    backdropImage: bc.backdrop_image,
    viewMode: bc.view_mode,
    showAllTab: bc.show_all_tab,
    focusGlowEnabled: bc.focus_glow_enabled,
    pinToTop: bc.pin_to_top,
  }));

  const folders: DBFolder[] = (pack.folders || []).map((bf: BESTFolder) => ({
    id: bf.source_key,
    collectionId: bf.collection_source_key,
    name: bf.name,
    sortOrder: bf.sort_order ?? 0,
    coverImage: bf.cover_image,
    focusGif: bf.focus_gif,
    titleLogo: bf.title_logo,
    heroBackdrop: bf.hero_backdrop,
    heroVideoUrl: bf.hero_video_url,
    hideTitle: bf.hide_title,
    tileShape: bf.tile_shape,
    focusGifEnabled: bf.focus_gif_enabled,
  }));

  const folderCatalogs: DBFolderCatalog[] = (pack.folder_catalogs || []).map((bfc: BESTFolderCatalog) => ({
    folderId: bfc.folder_source_key,
    catalogId: bfc.catalog_id,
    mediaType: bfc.media_type,
    genre: bfc.genre,
  }));

  return { collections, folders, folderCatalogs, folderSources: [] };
}
