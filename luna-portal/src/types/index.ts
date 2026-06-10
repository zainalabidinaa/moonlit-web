export type UserRole = 'admin' | 'friends_family' | 'premium' | 'premium_plus';

export interface Profile {
  id: string;
  user_id: string;
  name: string;
  avatar_color: string | null;
  avatar_id: number | null;
  profile_index: number;
  uses_primary_addons: boolean;
  pin_enabled: boolean;
  role: UserRole;
  created_at: string;
}

export interface InstalledAddon {
  id: string;
  profile_id: string;
  addon_url: string;
  addon_name: string | null;
  enabled: boolean;
  sort_order: number;
  created_at: string;
}

export interface InviteCode {
  code: string;
  created_by: string | null;
  used_by: string | null;
  used_at: string | null;
  created_at: string;
  max_uses: number;
  is_active: boolean;
}

export interface Collection {
  id: string;
  name: string;
  sort_order: number;
  backdrop_image: string | null;
  view_mode: string;
  show_all_tab: boolean;
  focus_glow_enabled: boolean;
  pin_to_top: boolean;
  created_at: string;
}

export interface Folder {
  id: string;
  collection_id: string;
  name: string;
  cover_image: string | null;
  focus_gif: string | null;
  sort_order: number;
  title_logo: string | null;
  hero_backdrop: string | null;
  hero_video_url: string | null;
  hide_title: boolean;
  tile_shape: string;
  focus_gif_enabled: boolean;
}

export interface FolderSource {
  id: string;
  folder_id: string;
  provider: string;
  title: string | null;
  tmdb_id: string | null;
  media_type: string | null;
  sort_order: number;
}

export type Plan = 'premium' | 'premium_plus';
