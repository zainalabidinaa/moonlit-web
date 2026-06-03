import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { supabase } from '@/lib/supabase';
import { LunaProfile, AddonManifest } from '@/lib/types';
import { getProfiles, getInstalledAddons } from '@/lib/services/api';
import { fetchManifest } from '@/lib/stremio';
import { DEFAULT_ADDONS } from '@/lib/supabase';

interface AuthContextType {
  user: any;
  session: any;
  profiles: LunaProfile[];
  currentProfile: LunaProfile | null;
  addons: AddonManifest[];
  isLoading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string, inviteCode: string) => Promise<void>;
  signOut: () => Promise<void>;
  selectProfile: (profile: LunaProfile) => void;
  createProfile: (name: string) => Promise<void>;
  deleteProfile: (profileId: string) => Promise<void>;
  refreshProfiles: () => Promise<void>;
  refreshAddons: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<any>(null);
  const [session, setSession] = useState<any>(null);
  const [profiles, setProfiles] = useState<LunaProfile[]>([]);
  const [currentProfile, setCurrentProfile] = useState<LunaProfile | null>(null);
  const [addons, setAddons] = useState<AddonManifest[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setUser(data.session?.user ?? null);
      if (data.session?.user) {
        loadProfiles(data.session.user.id);
      } else {
        setIsLoading(false);
      }
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_e, session) => {
      setSession(session);
      setUser(session?.user ?? null);
      if (!session) {
        setProfiles([]);
        setCurrentProfile(null);
        setIsLoading(false);
      }
    });

    return () => listener?.subscription.unsubscribe();
  }, []);

  async function loadProfiles(userId: string) {
    const p = await getProfiles(userId);
    setProfiles(p);
    if (p.length > 0 && !currentProfile) {
      setCurrentProfile(p[0]);
      await loadAddons(p[0].id);
    }
    setIsLoading(false);
  }

  async function loadAddons(profileId: string) {
    try {
      const urls = await getInstalledAddons(profileId);
      // Always merge with DEFAULT_ADDONS so core addons (streams, metadata) are present
      const merged = [...new Set([...DEFAULT_ADDONS, ...urls])];
      const targetUrls = merged;
      const manifests = await Promise.allSettled(
        targetUrls.map(u => fetchManifest(u))
      );
      setAddons(
        manifests
          .filter((r): r is PromiseFulfilledResult<AddonManifest> => r.status === 'fulfilled')
          .map(r => r.value)
      );
    } catch {
      setAddons([]);
    }
  }

  async function handleSignIn(email: string, password: string) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    if (data.user) await loadProfiles(data.user.id);
  }

  async function handleSignUp(email: string, password: string, inviteCode: string) {
    const { data, error } = await supabase.auth.signUp({ email, password });
    if (error) throw error;
    if (data.user) {
      await supabase.from('invite_codes').update({
        used_by: data.user.id,
        used_at: new Date().toISOString()
      }).eq('code', inviteCode);

      await supabase.from('profiles').insert({
        user_id: data.user.id,
        name: 'Default',
        profile_index: 0,
        role: 'user'
      });
      await loadProfiles(data.user.id);
    }
  }

  async function handleSignOut() {
    await supabase.auth.signOut();
    setUser(null);
    setSession(null);
    setProfiles([]);
    setCurrentProfile(null);
    setAddons([]);
  }

  function handleSelectProfile(profile: LunaProfile) {
    setCurrentProfile(profile);
    loadAddons(profile.id);
  }

  async function handleCreateProfile(name: string) {
    if (!user) return;
    const { data: existing } = await supabase
      .from('profiles')
      .select('profile_index')
      .eq('user_id', user.id)
      .order('profile_index', { ascending: false })
      .limit(1);
    const nextIndex = (existing?.[0]?.profile_index ?? -1) + 1;
    await supabase.from('profiles').insert({
      user_id: user.id,
      name,
      profile_index: nextIndex,
      avatar_color: ['#FF6B6B','#4ECDC4','#45B7D1','#96CEB4'][Math.floor(Math.random()*4)],
      role: 'user'
    });
    await loadProfiles(user.id);
  }

  async function handleDeleteProfile(profileId: string) {
    await supabase.from('profiles').delete().eq('id', profileId);
    setProfiles(p => p.filter(x => x.id !== profileId));
    if (currentProfile?.id === profileId) {
      setCurrentProfile(null);
    }
  }

  return (
    <AuthContext.Provider value={{
      user, session, profiles, currentProfile, addons, isLoading,
      signIn: handleSignIn,
      signUp: handleSignUp,
      signOut: handleSignOut,
      selectProfile: handleSelectProfile,
      createProfile: handleCreateProfile,
      deleteProfile: handleDeleteProfile,
      refreshProfiles: () => user ? loadProfiles(user.id) : Promise.resolve(),
      refreshAddons: () => currentProfile ? loadAddons(currentProfile.id) : Promise.resolve()
    }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
