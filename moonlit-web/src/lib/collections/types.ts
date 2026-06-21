// ── Internal collection models (unified, from JSON or Supabase) ──────────

export interface DBCollection {
  id: string;
  name: string;
  sortOrder: number;
  backdropImage?: string;
  viewMode?: string;
  showAllTab?: boolean;
  focusGlowEnabled?: boolean;
  pinToTop?: boolean;
}

export interface DBFolder {
  id: string;
  collectionId: string;
  name: string;
  sortOrder: number;
  coverImage?: string;
  focusGif?: string;
  titleLogo?: string;
  heroBackdrop?: string;
  heroVideoUrl?: string;
  hideTitle?: boolean;
  tileShape?: string;
  focusGifEnabled?: boolean;
}

export interface DBFolderCatalog {
  id?: string;
  folderId: string;
  catalogId: string;
  mediaType: string;
  genre?: string;
  extras?: Record<string, string>;
}

export interface DBFolderSource {
  id?: string;
  folderId: string;
  provider: string;
  title?: string;
  mediaType?: string;
  tmdbId?: string;
  tmdbSourceType?: string;
  sortBy?: string;
  filtersJson?: string;
}

export interface OrganizedCollections {
  collections: DBCollection[];
  folders: DBFolder[];
  folderCatalogs: DBFolderCatalog[];
  folderSources: DBFolderSource[];
}

// ── Nuvio JSON format (bundled home-organizer.json) ─────────────────────

export interface NuvioCollection {
  id: string;
  title: string;
  folders: NuvioFolder[];
  pinToTop?: boolean;
  viewMode?: string;
  showAllTab?: boolean;
  backdropImageUrl?: string;
  focusGlowEnabled?: boolean;
}

export interface NuvioFolder {
  id: string;
  title: string;
  sources: NuvioSource[];
  hideTitle?: boolean;
  tileShape?: string;
  focusGifUrl?: string;
  heroVideoUrl?: string;
  titleLogoUrl?: string;
  coverImageUrl?: string;
  focusGifEnabled?: boolean;
  heroBackdropUrl?: string;
}

export interface NuvioSource {
  title?: string;
  type?: string;
  genre?: string;
  provider?: string;
  catalogId?: string;
  mediaType?: string;
  traktListId?: number;
  tmdbId?: number;
  tmdbSourceType?: string;
  sortBy?: string;
  filters?: NuvioDiscoverFilters;
}

export interface NuvioDiscoverFilters {
  releaseDateGte?: string;
  releaseDateLte?: string;
  voteCountGte?: number;
  voteAverageGte?: number;
  withGenres?: string;
  withKeywords?: string;
  withOriginalLanguage?: string;
  year?: number;
}

// ── BEST format (from Supabase edge function) ──────────────────────────

export interface BESTPack {
  collections: BESTCollection[];
  folders: BESTFolder[];
  folder_catalogs: BESTFolderCatalog[];
}

export interface BESTCollection {
  source_key: string;
  sort_order: number;
  name: string;
  view_mode?: string;
  show_all_tab?: boolean;
  focus_glow_enabled?: boolean;
  pin_to_top?: boolean;
  backdrop_image?: string;
}

export interface BESTFolder {
  source_key: string;
  collection_source_key: string;
  sort_order: number;
  name: string;
  cover_image?: string;
  focus_gif?: string;
  title_logo?: string;
  hero_backdrop?: string;
  hero_video_url?: string;
  hide_title?: boolean;
  tile_shape?: string;
  focus_gif_enabled?: boolean;
}

export interface BESTFolderCatalog {
  folder_source_key: string;
  catalog_id: string;
  media_type: string;
  genre?: string;
}

// ── Display model ──────────────────────────────────────────────────────

export interface CatalogRow {
  id: string;
  title: string;
  items: MetaPreview[];
  addonName?: string;
  page: number;
  hasMore: boolean;
  tileShape?: string;
  coverImage?: string;
  focusGif?: string;
  focusGifEnabled?: boolean;
  titleLogo?: string;
  heroBackdrop?: string;
  hideTitle?: boolean;
  focusGlowEnabled?: boolean;
  viewMode?: string;
  showAllTab?: boolean;
  pinToTop?: boolean;
  backdropImage?: string;
  isGroupTile?: boolean;
  folderId?: string;
  collectionId?: string;
}

export interface MetaPreview {
  id: string;
  type: string;
  name: string;
  poster?: string;
  description?: string;
  releaseInfo?: string;
  imdbId?: string;
  imdbRating?: string;
  genres?: string[];
}

// ── User preferences ──────────────────────────────────────────────────

export interface CollectionDisplayPreferences {
  disabledCollectionIds: Set<string>;
  expandedCollectionIds: Set<string>;
  hiddenFolderIds: Set<string>;
}

// ── Stremio catalog types ─────────────────────────────────────────────

export interface StremioCatalogQuery {
  baseURL: string;
  type: string;
  id: string;
  extras?: Record<string, string>;
}

export interface AddonManifest {
  id: string;
  name: string;
  version: string;
  transportUrl: string;
  logo?: string;
  catalogs: AddonCatalog[];
  resources?: (string | { name: string })[] | { name: string }[];
}

export interface AddonCatalog {
  id: string;
  name: string;
  type: string;
  extra?: { name: string; options?: string[] }[];
}
