import { supabase } from '../supabase';
import { MoonlitProfile, WatchProgressEntry, LibraryItem, InviteCode, AdminStats, SystemAddon, Collection, Folder, FolderCatalog, UserList, UserListItem } from '../types';

export async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signUp(email: string, password: string, inviteCode: string) {
  const valid = await validateInviteCode(inviteCode);
  if (!valid) throw new Error('Invalid or used invite code');

  const { data, error } = await supabase.auth.signUp({ email, password });
  if (error) throw error;

  if (data.user) {
    await supabase.from('invite_codes').update({
      used_by: data.user.id,
      used_email: email,
      used_at: new Date().toISOString()
    }).eq('code', inviteCode);

    await supabase.from('profiles').insert({
      user_id: data.user.id,
      name: 'Default',
      profile_index: 0,
      role: 'user'
    });
  }

  return data;
}

export async function signOut() {
  await supabase.auth.signOut();
}

export async function validateInviteCode(code: string): Promise<boolean> {
  const { data } = await supabase
    .from('invite_codes')
    .select('code, is_active, used_by, expires_at')
    .eq('code', code.toUpperCase())
    .single();

  const isExpired = data?.expires_at ? new Date(data.expires_at) <= new Date() : false;
  return !!data && data.is_active && !data.used_by && !isExpired;
}

export async function getProfiles(userId: string): Promise<MoonlitProfile[]> {
  const { data } = await supabase
    .from('profiles')
    .select('*')
    .eq('user_id', userId)
    .order('profile_index');

  return (data || []).map((p: any) => ({
    ...p,
    isAdmin: p.role === 'admin'
  }));
}

export async function createProfile(userId: string, name: string) {
  const { data: existing } = await supabase
    .from('profiles')
    .select('profile_index')
    .eq('user_id', userId)
    .order('profile_index', { ascending: false })
    .limit(1);

  const nextIndex = (existing?.[0]?.profile_index ?? -1) + 1;

  await supabase.from('profiles').insert({
    user_id: userId,
    name,
    profile_index: nextIndex,
    avatar_color: ['#FF6B6B','#4ECDC4','#45B7D1','#96CEB4','#FFEAA7'][Math.floor(Math.random()*5)],
    avatar_id: Math.floor(Math.random() * 30),
    role: 'user'
  });
}

export async function deleteProfile(profileId: string) {
  await supabase.from('profiles').delete().eq('id', profileId);
}

export async function getWatchProgress(profileId: string): Promise<WatchProgressEntry[]> {
  const { data } = await supabase
    .from('watch_progress')
    .select('*')
    .eq('profile_id', profileId);
  return data || [];
}

export async function updateWatchProgress(
  profileId: string,
  mediaId: string,
  mediaType: string,
  positionSeconds: number,
  durationSeconds: number,
  completed: boolean = false,
  name?: string,
  poster?: string
) {
  const { data: existing } = await supabase
    .from('watch_progress')
    .select('id')
    .eq('profile_id', profileId)
    .eq('media_id', mediaId)
    .maybeSingle();

  if (existing) {
    await supabase.from('watch_progress').update({
      position_seconds: positionSeconds,
      duration_seconds: durationSeconds,
      completed,
      updated_at: new Date().toISOString(),
      ...(name !== undefined && { name }),
      ...(poster !== undefined && { poster }),
    }).eq('id', existing.id);
  } else {
    await supabase.from('watch_progress').insert({
      profile_id: profileId,
      media_id: mediaId,
      media_type: mediaType,
      position_seconds: positionSeconds,
      duration_seconds: durationSeconds,
      completed,
      name,
      poster,
    });
  }
}

export async function getLibrary(profileId: string): Promise<LibraryItem[]> {
  const { data } = await supabase
    .from('library_items')
    .select('*')
    .eq('profile_id', profileId)
    .order('saved_at', { ascending: false });
  return data || [];
}

export async function toggleLibrary(
  profileId: string,
  mediaId: string,
  mediaType: string,
  name?: string,
  poster?: string
) {
  const { data: existing } = await supabase
    .from('library_items')
    .select('id')
    .eq('profile_id', profileId)
    .eq('media_id', mediaId)
    .single();

  if (existing) {
    await supabase.from('library_items').delete().eq('id', existing.id);
  } else {
    await supabase.from('library_items').insert({
      profile_id: profileId,
      media_id: mediaId,
      media_type: mediaType,
      name,
      poster
    });
  }
}

export async function isInLibrary(profileId: string, mediaId: string): Promise<boolean> {
  const { data } = await supabase
    .from('library_items')
    .select('id')
    .eq('profile_id', profileId)
    .eq('media_id', mediaId)
    .maybeSingle();
  return !!data;
}

type UserListRecord = Omit<UserList, 'items'> & { user_list_items?: UserListItem[] };

function normalizeUserList(data: UserListRecord): UserList {
  const items = Array.isArray(data?.user_list_items)
    ? [...data.user_list_items].sort((left, right) => Date.parse(right.added_at) - Date.parse(left.added_at))
    : [];
  return {
    id: data.id,
    profile_id: data.profile_id,
    name: data.name || 'Watchlist',
    system_kind: data.system_kind ?? null,
    created_at: data.created_at,
    items,
  };
}

/** The web watchlist is a first-class user_list, not the legacy library_items table. */
export async function getUserWatchlist(profileId: string): Promise<UserList> {
  const { data, error } = await supabase
    .from('user_lists')
    .select('id, profile_id, name, system_kind, created_at, user_list_items(id, list_id, media_id, media_type, name, poster, added_at)')
    .eq('profile_id', profileId)
    .eq('system_kind', 'watchlist')
    .maybeSingle();
  if (error) throw error;
  if (data) return normalizeUserList(data);

  const { data: created, error: createError } = await supabase
    .from('user_lists')
    .insert({ profile_id: profileId, name: 'Watchlist', system_kind: 'watchlist' })
    .select('id, profile_id, name, system_kind, created_at')
    .single();
  if (createError) throw createError;
  return normalizeUserList({ ...created, user_list_items: [] });
}

export async function addUserWatchlistItem(
  profileId: string,
  item: Pick<UserListItem, 'media_id' | 'media_type' | 'name' | 'poster'>,
): Promise<UserListItem> {
  const list = await getUserWatchlist(profileId);
  const { data, error } = await supabase
    .from('user_list_items')
    .insert({ list_id: list.id, ...item })
    .select('id, list_id, media_id, media_type, name, poster, added_at')
    .single();
  if (error) throw error;
  return data as UserListItem;
}

export async function removeUserWatchlistItem(itemId: string): Promise<void> {
  const { error } = await supabase.from('user_list_items').delete().eq('id', itemId);
  if (error) throw error;
}

export async function toggleUserWatchlistItem(
  profileId: string,
  item: Pick<UserListItem, 'media_id' | 'media_type' | 'name' | 'poster'>,
): Promise<boolean> {
  const list = await getUserWatchlist(profileId);
  const existing = list.items.find(saved => saved.media_id === item.media_id);
  if (existing) {
    await removeUserWatchlistItem(existing.id);
    return false;
  }
  await addUserWatchlistItem(profileId, item);
  return true;
}

export async function isInUserWatchlist(profileId: string, mediaId: string): Promise<boolean> {
  const list = await getUserWatchlist(profileId);
  return list.items.some(item => item.media_id === mediaId);
}

export async function getInstalledAddons(profileId: string): Promise<string[]> {
  const { data } = await supabase
    .from('installed_addons')
    .select('addon_url')
    .eq('profile_id', profileId)
    .eq('enabled', true)
    .order('sort_order');
  return (data || []).map((a: any) => a.addon_url);
}

export async function saveInstalledAddons(profileId: string, urls: string[]) {
  await supabase.from('installed_addons').delete().eq('profile_id', profileId);
  if (urls.length > 0) {
    await supabase.from('installed_addons').insert(
      urls.map((url, i) => ({
        profile_id: profileId,
        addon_url: url,
        enabled: true,
        sort_order: i
      }))
    );
  }
}

export async function getInviteCodes(): Promise<InviteCode[]> {
  const { data } = await supabase
    .from('invite_codes')
    .select('*')
    .order('created_at', { ascending: false });

  const codes = (data || []) as InviteCode[];
  const usedUserIds = Array.from(new Set(codes.map(c => c.used_by).filter(Boolean))) as string[];
  if (usedUserIds.length === 0) return codes;

  const { data: profiles } = await supabase
    .from('profiles')
    .select('user_id, name')
    .in('user_id', usedUserIds)
    .order('profile_index');

  const profileNames = new Map<string, string>();
  for (const profile of profiles || []) {
    if (!profileNames.has(profile.user_id)) profileNames.set(profile.user_id, profile.name);
  }

  return codes.map(code => ({
    ...code,
    redeemed_by_label: code.used_email || (code.used_by ? profileNames.get(code.used_by) || code.used_by : null)
  }));
}

export async function generateInviteCode(userId: string, maxUses: number = 1, expiresAt?: string | null): Promise<string> {
  const code = Array.from({ length: 8 }, () =>
    'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[Math.floor(Math.random() * 32)]
  ).join('');

  await supabase.from('invite_codes').insert({
    code,
    created_by: userId,
    max_uses: maxUses,
    expires_at: expiresAt || null,
    is_active: true
  });

  return code;
}

export async function revokeInviteCode(code: string) {
  await supabase.from('invite_codes').update({ is_active: false }).eq('code', code);
}

export async function updateInviteCodeExpiration(code: string, expiresAt: string | null) {
  await supabase.from('invite_codes').update({ expires_at: expiresAt }).eq('code', code);
}

// ---- Collections (public reads) ----

export async function getCollections(): Promise<Collection[]> {
  const { data } = await supabase
    .from('collections')
    .select('*, folders(*, folder_catalogs(*))')
    .order('sort_order');
  return (data || []).map((c: any) => ({
    ...c,
    folders: (c.folders || []).sort((a: any, b: any) => a.sort_order - b.sort_order)
  }));
}

export async function getFolder(folderId: string): Promise<Folder | null> {
  const { data } = await supabase
    .from('folders')
    .select('*, folder_catalogs(*)')
    .eq('id', folderId)
    .single();
  return data || null;
}

export async function getSystemAddon(): Promise<SystemAddon | null> {
  const { data } = await supabase
    .from('system_addon')
    .select('*')
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  return data || null;
}

// ---- Admin writes ----

export async function upsertSystemAddon(manifestUrl: string, name: string): Promise<void> {
  const { data: existing } = await supabase
    .from('system_addon')
    .select('id')
    .limit(1)
    .maybeSingle();

  if (existing) {
    await supabase
      .from('system_addon')
      .update({ manifest_url: manifestUrl, name, updated_at: new Date().toISOString() })
      .eq('id', existing.id);
  } else {
    await supabase.from('system_addon').insert({ manifest_url: manifestUrl, name });
  }
}

export async function createCollection(name: string, sortOrder: number): Promise<Collection> {
  const { data, error } = await supabase
    .from('collections')
    .insert({ name, sort_order: sortOrder })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateCollection(id: string, updates: { name?: string; sort_order?: number }): Promise<void> {
  await supabase.from('collections').update(updates).eq('id', id);
}

export async function deleteCollection(id: string): Promise<void> {
  await supabase.from('collections').delete().eq('id', id);
}

export async function createFolder(
  collectionId: string,
  name: string,
  coverImage: string,
  focusGif: string,
  sortOrder: number,
  tileShape: string = 'PORTRAIT'
): Promise<Folder> {
  const { data, error } = await supabase
    .from('folders')
    .insert({ collection_id: collectionId, name, cover_image: coverImage, focus_gif: focusGif, sort_order: sortOrder, tile_shape: tileShape })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateFolder(
  id: string,
  updates: { name?: string; cover_image?: string; focus_gif?: string; sort_order?: number; tile_shape?: string }
): Promise<void> {
  await supabase.from('folders').update(updates).eq('id', id);
}

export async function deleteFolder(id: string): Promise<void> {
  await supabase.from('folders').delete().eq('id', id);
}

export async function setFolderCatalogs(folderId: string, catalogs: { catalog_id: string; media_type: string }[]): Promise<void> {
  await supabase.from('folder_catalogs').delete().eq('folder_id', folderId);
  if (catalogs.length > 0) {
    await supabase.from('folder_catalogs').insert(
      catalogs.map(c => ({ folder_id: folderId, catalog_id: c.catalog_id, media_type: c.media_type }))
    );
  }
}
