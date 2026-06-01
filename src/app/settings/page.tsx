'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '../AuthProvider';
import { useRouter } from 'next/navigation';
import { Sidebar } from '@/components/Sidebar';
import { getInstalledAddons, saveInstalledAddons } from '@/lib/services/api';
import { fetchManifest } from '@/lib/stremio';
import { DEFAULT_ADDONS } from '@/lib/supabase';
import { AddonManifest } from '@/lib/types';

export default function SettingsPage() {
  const { currentProfile, user, signOut, isLoading } = useAuth();
  const router = useRouter();
  const [addonUrls, setAddonUrls] = useState<string[]>([]);
  const [manifestCache, setManifestCache] = useState<Record<string, AddonManifest>>({});
  const [newUrl, setNewUrl] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    if (!currentProfile) { router.replace('/profiles'); return; }
    loadAddons();
  }, [currentProfile]);

  async function loadAddons() {
    if (!currentProfile) return;
    setLoading(true);
    const urls = await getInstalledAddons(currentProfile.id);
    const targetUrls = urls.length > 0 ? urls : DEFAULT_ADDONS;
    setAddonUrls(targetUrls);

    const cache: Record<string, AddonManifest> = {};
    await Promise.allSettled(
      targetUrls.map(async url => {
        try { cache[url] = await fetchManifest(url); } catch {}
      })
    );
    setManifestCache(cache);
    setLoading(false);
  }

  async function handleInstall() {
    if (!newUrl.trim() || !currentProfile) return;
    const url = newUrl.trim();
    const updated = [...addonUrls.filter(u => u !== url), url];
    setAddonUrls(updated);
    await saveInstalledAddons(currentProfile.id, updated);
    try {
      const manifest = await fetchManifest(url);
      setManifestCache(prev => ({ ...prev, [url]: manifest }));
    } catch {}
    setNewUrl('');
  }

  async function handleRemove(url: string) {
    if (!currentProfile) return;
    const updated = addonUrls.filter(u => u !== url);
    setAddonUrls(updated);
    await saveInstalledAddons(currentProfile.id, updated);
  }

  return (
    <Sidebar>
      {/* Gradient header band */}
      <div className="-mt-14 pt-14 pb-8 bg-gradient-to-b from-luna-elevated to-transparent">
        <div className="px-6 pt-8 max-w-2xl">
          <h1 className="text-2xl font-bold text-white">Settings</h1>
        </div>
      </div>

      <div className="px-6 pb-12 max-w-2xl space-y-4">

        {/* Profile card */}
        <div className="rounded-2xl bg-luna-surface border border-luna-border overflow-hidden">
          <div className="px-5 py-3 border-b border-luna-border">
            <p className="text-xs font-bold text-white/40 uppercase tracking-wider">Profile</p>
          </div>
          <div className="p-5 flex items-center gap-4">
            <div
              className="w-12 h-12 rounded-full flex items-center justify-center text-lg font-bold shrink-0"
              style={{ backgroundColor: currentProfile?.avatar_color || '#c084fc' }}
            >
              {currentProfile?.name?.[0]?.toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-semibold text-white">{currentProfile?.name}</p>
              <p className="text-xs text-luna-muted mt-0.5">{currentProfile?.role === 'admin' ? 'Administrator' : 'Member'}</p>
            </div>
            <button
              onClick={() => router.push('/profiles')}
              className="text-xs text-luna-accent font-medium px-3 py-1.5 rounded-lg bg-luna-accent/10 hover:bg-luna-accent/20 transition-colors shrink-0"
            >
              Switch Profile
            </button>
          </div>
        </div>

        {/* Addons card */}
        <div className="rounded-2xl bg-luna-surface border border-luna-border overflow-hidden">
          <div className="px-5 py-3 border-b border-luna-border flex items-center justify-between">
            <p className="text-xs font-bold text-white/40 uppercase tracking-wider">Addons</p>
            <span className="text-xs text-luna-muted">{addonUrls.length} installed</span>
          </div>
          <div className="divide-y divide-luna-border">
            {addonUrls.map(url => (
              <div key={url} className="px-5 py-3.5 flex items-center justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium text-white truncate">
                    {manifestCache[url]?.name || url.split('/')[2] || url}
                  </p>
                  <p className="text-[11px] text-luna-muted truncate mt-0.5">{url}</p>
                </div>
                <button
                  onClick={() => handleRemove(url)}
                  className="text-xs text-red-400/70 hover:text-red-400 border border-red-400/20 hover:border-red-400/40 px-2.5 py-1 rounded-lg transition-all shrink-0"
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
          <div className="p-5 border-t border-luna-border flex gap-2">
            <input
              value={newUrl}
              onChange={e => setNewUrl(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && handleInstall()}
              placeholder="https://.../manifest.json"
              className="flex-1 px-4 py-2.5 bg-luna-elevated rounded-xl text-white placeholder-luna-muted focus:outline-none focus:ring-1 focus:ring-luna-accent text-sm border border-luna-border"
            />
            <button
              onClick={handleInstall}
              disabled={!newUrl.trim()}
              className="px-4 py-2.5 bg-luna-accent rounded-xl text-sm font-semibold disabled:opacity-40 hover:bg-luna-accent/90 transition-colors"
            >
              Install
            </button>
          </div>
        </div>

        {/* Account card */}
        <div className="rounded-2xl bg-luna-surface border border-luna-border overflow-hidden">
          <div className="px-5 py-3 border-b border-luna-border">
            <p className="text-xs font-bold text-white/40 uppercase tracking-wider">Account</p>
          </div>
          <div className="p-5">
            <button
              onClick={signOut}
              className="px-4 py-2 bg-red-500/10 border border-red-500/20 text-red-400 rounded-xl text-sm font-medium hover:bg-red-500/20 transition-colors"
            >
              Sign Out
            </button>
          </div>
        </div>

        <p className="text-[11px] text-luna-muted text-center pt-2">Luna v1.0.0 · Powered by Stremio addon ecosystem</p>
      </div>
    </Sidebar>
  );
}
