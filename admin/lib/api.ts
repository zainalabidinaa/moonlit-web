import { supabase } from './supabase';

export interface AdminUser {
  id: string;
  email: string;
  created_at: string;
  profiles: AdminProfile[];
}

export interface AdminProfile {
  id: string;
  user_id: string;
  name: string;
  role: string;
  avatar_color?: string;
  profile_index: number;
  addon_count?: number;
  library_count?: number;
  user_email?: string;
}

export interface AdminStats {
  totalUsers: number;
  totalProfiles: number;
  activeInvites: number;
  watchEvents: number;
}

export interface InviteCode {
  code: string;
  created_by: string;
  used_by?: string;
  created_at: string;
  max_uses: number;
  is_active: boolean;
}

export async function getUsers(): Promise<AdminUser[]> {
  const [usersRes, profilesRes] = await Promise.all([
    fetch('/api/users').then(r => r.json()),
    supabase.from('profiles').select('*').order('profile_index'),
  ]);

  const authUsers: { id: string; email: string; created_at: string }[] = usersRes;
  const profiles: AdminProfile[] = profilesRes.data || [];

  return authUsers.map(u => ({
    ...u,
    profiles: profiles.filter(p => p.user_id === u.id),
  }));
}

export async function getAllProfiles(): Promise<AdminProfile[]> {
  const [profilesRes, addonsRes, libraryRes] = await Promise.all([
    supabase.from('profiles').select('*').order('created_at' as any, { ascending: false }),
    supabase.from('installed_addons').select('profile_id'),
    supabase.from('library_items').select('profile_id'),
  ]);

  const profiles: AdminProfile[] = profilesRes.data || [];
  const addonRows: { profile_id: string }[] = addonsRes.data || [];
  const libraryRows: { profile_id: string }[] = libraryRes.data || [];

  const addonCounts: Record<string, number> = {};
  const libraryCounts: Record<string, number> = {};
  for (const r of addonRows) addonCounts[r.profile_id] = (addonCounts[r.profile_id] || 0) + 1;
  for (const r of libraryRows) libraryCounts[r.profile_id] = (libraryCounts[r.profile_id] || 0) + 1;

  return profiles.map(p => ({
    ...p,
    addon_count: addonCounts[p.id] || 0,
    library_count: libraryCounts[p.id] || 0,
  }));
}

export async function getAdminStats(): Promise<AdminStats> {
  const [profilesRes, invitesRes, watchRes] = await Promise.all([
    supabase.from('profiles').select('id', { count: 'exact', head: true }),
    supabase.from('invite_codes').select('id', { count: 'exact', head: true }).eq('is_active', true).is('used_by', null),
    supabase.from('watch_progress').select('id', { count: 'exact', head: true }),
  ]);

  const { data: userRows } = await supabase.from('profiles').select('user_id');
  const uniqueUsers = new Set((userRows || []).map((r: any) => r.user_id)).size;

  return {
    totalUsers: uniqueUsers,
    totalProfiles: profilesRes.count || 0,
    activeInvites: invitesRes.count || 0,
    watchEvents: watchRes.count || 0,
  };
}

export async function getInviteCodes(): Promise<InviteCode[]> {
  const { data } = await supabase
    .from('invite_codes')
    .select('*')
    .order('created_at', { ascending: false });
  return data || [];
}

export async function generateInviteCode(userId: string, maxUses: number): Promise<string> {
  const code = Array.from({ length: 8 }, () =>
    'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[Math.floor(Math.random() * 32)]
  ).join('');
  await supabase.from('invite_codes').insert({ code, created_by: userId, max_uses: maxUses, is_active: true });
  return code;
}

export async function revokeInviteCode(code: string): Promise<void> {
  await supabase.from('invite_codes').update({ is_active: false }).eq('code', code);
}

export async function deleteProfile(profileId: string): Promise<void> {
  await supabase.from('profiles').delete().eq('id', profileId);
}

export const DEFAULT_ADDON_URLS = [
  'https://aiometadata.elfhosted.com/stremio/d67da46b-f48e-4efa-a9e2-21ac1a6c3a4a/manifest.json',
  'https://aiostreamsfortheweak.nhyira.dev/stremio/4d34b9a5-8712-4421-a545-aacc60047a58/eyJpIjoibzNiUkNBYkg1U2FvUnd2bmgzL0dhQT09IiwiZSI6ImJZQ3BZZFp5NXRYUHIyS0hoVGxQdmpxYUl5Zi9Xd2JUYUw3SGpjdmVjSHM9IiwidCI6ImEifQ/manifest.json',
  'https://v3-cinemeta.strem.io/manifest.json',
  'https://opensubtitles-v3.strem.io/manifest.json',
];
