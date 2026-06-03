import { useState } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Sidebar } from '@/components/Sidebar';
import { getInstalledAddons, saveInstalledAddons } from '@/lib/services/api';
import { fetchManifest } from '@/lib/stremio';
import { DEFAULT_ADDONS } from '@/lib/supabase';
import { AddonManifest } from '@/lib/types';
import { useNavigate } from '@tanstack/react-router';

// ── Addon capability helpers ──────────────────────────────────────────────

function getAddonCapabilities(manifest: AddonManifest): string[] {
  if (!manifest.resources) return [];
  return [...new Set(
    manifest.resources.map(r => typeof r === 'string' ? r : r.name)
  )];
}

const CAPABILITY_LABELS: Record<string, { label: string; color: string }> = {
  stream:       { label: 'Streams',   color: 'text-emerald-400 bg-emerald-400/10 border-emerald-400/20' },
  meta:         { label: 'Metadata',  color: 'text-blue-400   bg-blue-400/10   border-blue-400/20'   },
  catalog:      { label: 'Catalog',   color: 'text-purple-400 bg-purple-400/10 border-purple-400/20' },
  subtitles:    { label: 'Subtitles', color: 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20' },
  addon_catalog:{ label: 'Directory', color: 'text-slate-400  bg-slate-400/10  border-slate-400/20'  },
};

function CapabilityBadge({ cap }: { cap: string }) {
  const cfg = CAPABILITY_LABELS[cap] ?? { label: cap, color: 'text-white/50 bg-white/5 border-white/10' };
  return (
    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${cfg.color}`}>
      {cfg.label}
    </span>
  );
}

// ── Page ─────────────────────────────────────────────────────────────────

export default function SettingsPage() {
  const { currentProfile, signOut, refreshAddons } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [newUrl, setNewUrl] = useState('');
  const [installing, setInstalling] = useState(false);
  const [installError, setInstallError] = useState('');

  const { data: addonData, isLoading } = useQuery({
    queryKey: ['addons', currentProfile?.id],
    queryFn: async () => {
      const urls = await getInstalledAddons(currentProfile!.id);
      const targetUrls = urls.length > 0 ? urls : DEFAULT_ADDONS;
      const cache: Record<string, AddonManifest> = {};
      await Promise.allSettled(
        targetUrls.map(async url => {
          try { cache[url] = await fetchManifest(url); } catch {}
        })
      );
      return { urls: targetUrls, manifests: cache };
    },
    enabled: !!currentProfile,
  });

  const addonUrls = addonData?.urls ?? [];
  const manifestCache = addonData?.manifests ?? {};

  async function handleInstall() {
    const url = newUrl.trim();
    if (!url || !currentProfile) return;
    setInstalling(true);
    setInstallError('');
    try {
      // Validate the manifest is reachable before saving
      await fetchManifest(url);
      const updated = [...addonUrls.filter(u => u !== url), url];
      await saveInstalledAddons(currentProfile.id, updated);
      // Refresh both the settings query AND the auth context so streams see it immediately
      queryClient.invalidateQueries({ queryKey: ['addons', currentProfile.id] });
      await refreshAddons();
      setNewUrl('');
    } catch {
      setInstallError('Could not load manifest. Check the URL and try again.');
    } finally {
      setInstalling(false);
    }
  }

  async function handleRemove(url: string) {
    if (!currentProfile) return;
    const updated = addonUrls.filter(u => u !== url);
    await saveInstalledAddons(currentProfile.id, updated);
    queryClient.invalidateQueries({ queryKey: ['addons', currentProfile.id] });
    await refreshAddons();
  }

  // Group addons by primary capability for display
  const grouped: Record<string, string[]> = { stream: [], meta: [], catalog: [], subtitles: [], other: [] };
  for (const url of addonUrls) {
    const caps = manifestCache[url] ? getAddonCapabilities(manifestCache[url]) : [];
    if (caps.includes('stream')) grouped.stream.push(url);
    else if (caps.includes('subtitles')) grouped.subtitles.push(url);
    else if (caps.includes('meta')) grouped.meta.push(url);
    else if (caps.includes('catalog')) grouped.catalog.push(url);
    else grouped.other.push(url);
  }

  return (
    <Sidebar>
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
            <div className="w-12 h-12 rounded-full flex items-center justify-center text-lg font-bold shrink-0"
              style={{ backgroundColor: currentProfile?.avatar_color || '#c084fc' }}>
              {currentProfile?.name?.[0]?.toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-semibold text-white">{currentProfile?.name}</p>
              <p className="text-xs text-luna-muted mt-0.5">{currentProfile?.role === 'admin' ? 'Administrator' : 'Member'}</p>
            </div>
            <button onClick={() => navigate({ to: '/profiles' })}
              className="text-xs text-luna-accent font-medium px-3 py-1.5 rounded-lg bg-luna-accent/10 hover:bg-luna-accent/20 transition-colors shrink-0">
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

          {isLoading ? (
            <div className="p-5 flex justify-center">
              <div className="animate-spin rounded-full h-5 w-5 border-2 border-luna-accent border-t-transparent" />
            </div>
          ) : (
            <div className="divide-y divide-luna-border">
              {addonUrls.map(url => {
                const manifest = manifestCache[url];
                const caps = manifest ? getAddonCapabilities(manifest) : [];
                const isDefault = DEFAULT_ADDONS.includes(url);
                return (
                  <div key={url} className="px-5 py-4 flex items-start justify-between gap-3">
                    <div className="flex items-start gap-3 min-w-0 flex-1">
                      {manifest?.logo && (
                        <img src={manifest.logo} alt="" className="w-8 h-8 rounded-lg object-contain bg-white/5 shrink-0 mt-0.5" />
                      )}
                      <div className="min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="text-sm font-semibold text-white truncate">
                            {manifest?.name || url.split('/')[2] || url}
                          </p>
                          {isDefault && (
                            <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-white/8 text-white/40 border border-white/10">
                              Built-in
                            </span>
                          )}
                        </div>
                        {caps.length > 0 && (
                          <div className="flex flex-wrap gap-1 mt-1.5">
                            {caps.map(cap => <CapabilityBadge key={cap} cap={cap} />)}
                          </div>
                        )}
                        {manifest?.description && (
                          <p className="text-[11px] text-luna-muted mt-1.5 line-clamp-2 leading-relaxed">
                            {manifest.description}
                          </p>
                        )}
                        <p className="text-[10px] text-white/20 mt-1 truncate">{url}</p>
                      </div>
                    </div>
                    {!isDefault && (
                      <button onClick={() => handleRemove(url)}
                        className="text-xs text-red-400/70 hover:text-red-400 border border-red-400/20 hover:border-red-400/40 px-2.5 py-1 rounded-lg transition-all shrink-0 mt-0.5">
                        Remove
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          )}

          {/* Install input */}
          <div className="p-5 border-t border-luna-border space-y-2">
            <div className="flex gap-2">
              <input
                value={newUrl}
                onChange={e => { setNewUrl(e.target.value); setInstallError(''); }}
                onKeyDown={e => e.key === 'Enter' && !installing && handleInstall()}
                placeholder="https://.../manifest.json"
                className="flex-1 px-4 py-2.5 bg-luna-elevated rounded-xl text-white placeholder-luna-muted focus:outline-none focus:ring-1 focus:ring-luna-accent text-sm border border-luna-border"
              />
              <button
                onClick={handleInstall}
                disabled={!newUrl.trim() || installing}
                className="px-4 py-2.5 bg-luna-accent rounded-xl text-sm font-semibold disabled:opacity-40 hover:bg-luna-accent/90 transition-colors min-w-[80px] flex items-center justify-center"
              >
                {installing
                  ? <div className="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent" />
                  : 'Install'}
              </button>
            </div>
            {installError && <p className="text-xs text-red-400">{installError}</p>}
            <p className="text-[11px] text-luna-muted">
              Paste a Stremio addon manifest URL. Streaming addons will appear immediately in Sources.
            </p>
          </div>
        </div>

        {/* Account card */}
        <div className="rounded-2xl bg-luna-surface border border-luna-border overflow-hidden">
          <div className="px-5 py-3 border-b border-luna-border">
            <p className="text-xs font-bold text-white/40 uppercase tracking-wider">Account</p>
          </div>
          <div className="p-5">
            <button onClick={signOut}
              className="px-4 py-2 bg-red-500/10 border border-red-500/20 text-red-400 rounded-xl text-sm font-medium hover:bg-red-500/20 transition-colors">
              Sign Out
            </button>
          </div>
        </div>

        <p className="text-[11px] text-luna-muted text-center pt-2">Luna v1.0.0 · Powered by Stremio addon ecosystem</p>
      </div>
    </Sidebar>
  );
}
