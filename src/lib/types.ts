export interface MetaPreview {
  id: string;
  type: string;
  name: string;
  poster?: string;
  banner?: string;
  logo?: string;
  posterShape?: string;
  description?: string;
  releaseInfo?: string;
  imdbRating?: string;
  genres?: string[];
  popularity?: number;
}

export interface MetaLink {
  name: string;
  category?: string;
  url: string;
}

export interface MetaDetail {
  id: string;
  type: string;
  name: string;
  poster?: string;
  background?: string;
  logo?: string;
  description?: string;
  releaseInfo?: string;
  status?: string;
  imdbRating?: string;
  runtime?: string;
  genres?: string[];
  director?: string[];
  cast?: Person[];
  trailers?: Trailer[];
  videos?: MetaVideo[];
  seasons?: Season[];
  links?: MetaLink[];
  moreLikeThis?: MetaPreview[];
}

export interface Person {
  id: string;
  name: string;
  photo?: string;
}

export interface Trailer {
  id: string;
  title?: string;
  thumbnail?: string;
  youtubeId?: string;
}

export interface MetaVideo {
  id: string;
  title: string;
  season?: number;
  episode?: number;
  thumbnail?: string;
  overview?: string;
  released?: string;
}

export interface Season {
  id: string;
  number: number;
  name?: string;
  poster?: string;
  episodes?: MetaVideo[];
}

export interface StreamItem {
  name?: string;
  title?: string;
  description?: string;
  url?: string;
  externalUrl?: string;
  infoHash?: string;
  addonName?: string;
  addonId?: string;
  behaviorHints?: { notWebReady?: boolean; bingeGroup?: string; proxyHeaders?: { request?: Record<string, string> } };
}

export interface AddonManifest {
  id: string;
  name: string;
  version: string;
  description?: string;
  types?: string[];
  resources?: (string | { name: string; types?: string[] })[];
  catalogs?: { type: string; id: string; name?: string; extra?: { name: string; isRequired?: boolean; options?: string[] }[] }[];
  transportUrl?: string;
  logo?: string;
}

export interface HomeCatalogRow {
  id: string;
  title: string;
  type: string;
  catalogId: string;
  items: MetaPreview[];
  isMainRow?: boolean;
  coverImage?: string;
}

export interface FeaturedHomeItem {
  row: HomeCatalogRow;
  item: MetaPreview;
}

export interface LunaProfile {
  id: string;
  user_id: string;
  name: string;
  avatar_color?: string;
  avatar_id?: number;
  profile_index: number;
  role: string;
  isAdmin: boolean;
}

export interface WatchProgressEntry {
  id: string;
  profile_id: string;
  media_id: string;
  media_type: string;
  position_seconds: number;
  duration_seconds: number;
  completed: boolean;
  updated_at: string;
}

export interface LibraryItem {
  id: string;
  profile_id: string;
  media_id: string;
  media_type: string;
  name?: string;
  poster?: string;
  saved_at: string;
}

export interface InviteCode {
  code: string;
  created_by: string;
  used_by?: string;
  created_at: string;
  max_uses: number;
  is_active: boolean;
}

export interface AdminStats {
  totalUsers: number;
  totalProfiles: number;
  activeInviteCodes: number;
  totalWatchlistItems: number;
  totalWatchedItems: number;
  activeUsers: number;
}

export interface SystemAddon {
  id: string;
  manifest_url: string;
  name: string | null;
  updated_at: string;
}

export interface Collection {
  id: string;
  name: string;
  sort_order: number;
  focus_glow_enabled?: boolean;
  created_at: string;
  folders?: Folder[];
}

export interface Folder {
  id: string;
  collection_id: string;
  name: string;
  cover_image: string | null;
  focus_gif: string | null;
  focus_gif_enabled?: boolean;
  tile_shape: 'LANDSCAPE' | 'PORTRAIT' | null;
  sort_order: number;
  created_at: string;
  folder_catalogs?: FolderCatalog[];
}

export interface FolderCatalog {
  id: string;
  folder_id: string;
  catalog_id: string;
  media_type: string;
}
