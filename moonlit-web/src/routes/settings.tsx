import { useState } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Sidebar } from '@/components/Sidebar';
import { getInstalledAddons, saveInstalledAddons } from '@/lib/services/api';
import { fetchManifest } from '@/lib/stremio';
import { DEFAULT_ADDONS } from '@/lib/supabase';
import { AddonManifest } from '@/lib/types';
import { useNavigate } from '@tanstack/react-router';
import { getStreamingServerUrl, setStreamingServerUrl } from '@/lib/config';
import { pingServer } from '@/lib/streaming-server';

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

// ── Section label (matches iOS "GENERAL", "PLAYBACK" etc.) ───────────────

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-xs font-bold text-white/40 uppercase tracking-wider px-1 pt-6 pb-1.5">
      {children}
    </p>
  );
}

// ── iOS-style settings row ────────────────────────────────────────────────

interface SettingsRowProps {
  iconBg: string;
  icon: React.ReactNode;
  title: string;
  subtitle?: string;
  value?: string;
  chevron?: boolean;
  onClick?: () => void;
}

function SettingsRow({ iconBg, icon, title, subtitle, value, chevron = true, onClick }: SettingsRowProps) {
  return (
    <button
      onClick={onClick}
      className="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/[0.03] transition-colors text-left"
    >
      <div
        className="w-7 h-7 rounded-lg flex items-center justify-center shrink-0"
        style={{ background: iconBg }}
      >
        {icon}
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-white">{title}</p>
        {subtitle && <p className="text-xs text-moonlit-muted truncate">{subtitle}</p>}
      </div>
      {value && <span className="text-xs text-white/40 shrink-0">{value}</span>}
      {chevron && (
        <svg className="w-3.5 h-3.5 text-white/20 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
          <path d="M9 18l6-6-6-6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
    </button>
  );
}

function RowDivider() {
  return <div className="h-px bg-white/[0.06] ml-14" />;
}

// ── Page ─────────────────────────────────────────────────────────────────

export default function SettingsPage() {
  const { currentProfile, signOut, refreshAddons } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [newUrl, setNewUrl] = useState('');
  const [installing, setInstalling] = useState(false);
  const [installError, setInstallError] = useState('');
  const [showAddons, setShowAddons] = useState(false);
  const [showServer, setShowServer] = useState(false);

  const [serverUrl, setServerUrlState] = useState(() => getStreamingServerUrl());
  const [testing, setTesting] = useState(false);
  const [serverStatus, setServerStatus] = useState<'idle' | 'ok' | 'fail'>('idle');

  async function handleSaveServer() {
    const url = serverUrl.trim().replace(/\/+$/, '');
    setStreamingServerUrl(url);
    setServerUrlState(url);
    if (!url) { setServerStatus('idle'); return; }
    setTesting(true);
    setServerStatus('idle');
    const ok = await pingServer(url);
    setServerStatus(ok ? 'ok' : 'fail');
    setTesting(false);
  }

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
      await fetchManifest(url);
      const updated = [...addonUrls.filter(u => u !== url), url];
      await saveInstalledAddons(currentProfile.id, updated);
      queryClient.invalidateQueries({ queryKey: ['addons', currentProfile.id] });
      await refreshAddons();
      setNewUrl('');
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      setInstallError(msg ? `Could not load manifest: ${msg}` : 'Could not load manifest. Check the URL and try again.');
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

  const serverStatusLabel =
    serverStatus === 'ok' ? 'Connected' :
    serverStatus === 'fail' ? 'Unreachable' :
    serverUrl ? 'Not tested' : 'Off';

  return (
    <Sidebar>
      <div className="-mt-14 pt-14 pb-8 bg-gradient-to-b from-moonlit-elevated to-transparent">
        <div className="px-6 pt-8 max-w-2xl mx-auto">
          <h1 className="text-2xl font-bold text-white">Settings</h1>
        </div>
      </div>

      <div className="px-6 pb-16 max-w-2xl mx-auto">

        {/* ── Profile card ── */}
        <div className="mt-2 rounded-2xl bg-moonlit-surface border border-moonlit-border overflow-hidden">
          <div className="px-4 py-3.5 flex items-center gap-3">
            <div className="w-11 h-11 rounded-full flex items-center justify-center text-base font-bold shrink-0"
              style={{ backgroundColor: currentProfile?.avatar_color || '#c084fc' }}>
              {currentProfile?.name?.[0]?.toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-semibold text-white text-sm">{currentProfile?.name}</p>
              <p className="text-xs text-moonlit-muted mt-0.5">{currentProfile?.role === 'admin' ? 'Administrator' : 'Member'}</p>
            </div>
            <button onClick={() => navigate({ to: '/profiles' })}
              className="text-xs text-white/80 font-semibold px-3 py-1.5 rounded-lg bg-white/8 border border-white/[0.12] hover:bg-white/15 transition-colors shrink-0">
              Switch
            </button>
          </div>
        </div>

        {/* ── GENERAL ── */}
        <SectionLabel>General</SectionLabel>
        <div className="rounded-2xl bg-moonlit-surface border border-moonlit-border overflow-hidden">
          <SettingsRow
            iconBg="#2C7DE8"
            icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M3 3h18v2H3zm0 4h18v2H3zm0 4h12v2H3zm0 4h12v2H3zm0 4h18v2H3z"/></svg>}
            title="Metadata"
            subtitle="TMDB · TVDB sources"
            chevron={false}
            value="TMDB"
          />
        </div>

        {/* ── CONTENT MANAGEMENT ── */}
        <SectionLabel>Content Management</SectionLabel>
        <div className="rounded-2xl bg-moonlit-surface border border-moonlit-border overflow-hidden">
          <SettingsRow
            iconBg="#5956D6"
            icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z"/></svg>}
            title="Addons"
            subtitle={isLoading ? 'Loading…' : `${addonUrls.length} installed`}
            onClick={() => setShowAddons(v => !v)}
          />

          {currentProfile?.role === 'admin' && (
            <>
              <RowDivider />
              <SettingsRow
                iconBg="#30A46C"
                icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zm0 8a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zm12-1a1 1 0 00-1 1v6a1 1 0 001 1h2a1 1 0 001-1v-6a1 1 0 00-1-1h-2z"/></svg>}
                title="Catalog Management"
                subtitle="Manage content catalogs"
                onClick={() => navigate({ to: '/admin' })}
              />
              <RowDivider />
              <SettingsRow
                iconBg="#E54D2E"
                icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M2 6a2 2 0 012-2h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6zm14.5 5.5a.5.5 0 01.5.5v4a.5.5 0 01-.5.5h-3a.5.5 0 01-.5-.5v-4a.5.5 0 01.5-.5h3z"/></svg>}
                title="Hero Management"
                subtitle="Configure featured content"
                onClick={() => navigate({ to: '/admin' })}
              />
            </>
          )}

          {showAddons && (
            <div className="border-t border-moonlit-border">
              {isLoading ? (
                <div className="p-5 flex justify-center">
                  <div className="animate-spin rounded-full h-5 w-5 border-2 border-moonlit-accent border-t-transparent" />
                </div>
              ) : (
                <div className="divide-y divide-moonlit-border">
                  {addonUrls.map(url => {
                    const manifest = manifestCache[url];
                    const caps = manifest ? getAddonCapabilities(manifest) : [];
                    const isDefault = DEFAULT_ADDONS.includes(url);
                    return (
                      <div key={url} className="px-4 py-3.5 flex items-start justify-between gap-3">
                        <div className="flex items-start gap-3 min-w-0 flex-1">
                          {manifest?.logo && (
                            <img src={manifest.logo} alt="" width={32} height={32} loading="eager"
                              className="w-8 h-8 rounded-lg object-contain bg-white/5 shrink-0 mt-0.5" />
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
              <div className="p-4 border-t border-moonlit-border space-y-2">
                <div className="flex gap-2">
                  <input
                    value={newUrl}
                    onChange={e => { setNewUrl(e.target.value); setInstallError(''); }}
                    onKeyDown={e => e.key === 'Enter' && !installing && handleInstall()}
                    placeholder="https://.../manifest.json"
                    className="flex-1 px-4 py-2.5 bg-moonlit-elevated rounded-xl text-white placeholder-moonlit-muted focus:outline-none focus:ring-1 focus:ring-moonlit-accent text-sm border border-moonlit-border"
                  />
                  <button
                    onClick={handleInstall}
                    disabled={!newUrl.trim() || installing}
                    className="px-4 py-2.5 bg-moonlit-accent rounded-xl text-sm font-semibold disabled:opacity-40 hover:bg-moonlit-accent/90 transition-colors min-w-[80px] flex items-center justify-center"
                  >
                    {installing
                      ? <div className="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent" />
                      : 'Install'}
                  </button>
                </div>
                {installError && <p className="text-xs text-red-400">{installError}</p>}
                <p className="text-[11px] text-moonlit-muted">
                  Paste a Stremio addon manifest URL. Streaming addons will appear immediately in Sources.
                </p>
              </div>
            </div>
          )}
        </div>

        {/* ── PLAYBACK ── */}
        <SectionLabel>Playback</SectionLabel>
        <div className="rounded-2xl bg-moonlit-surface border border-moonlit-border overflow-hidden">
          <SettingsRow
            iconBg="#FF3B30"
            icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M4 4h16a1 1 0 011 1v14a1 1 0 01-1 1H4a1 1 0 01-1-1V5a1 1 0 011-1zm6 7.5l5 2.5-5 2.5v-5z"/></svg>}
            title="Video Player"
            subtitle="Playback quality & behavior"
            chevron={false}
            value="Default"
          />
          <RowDivider />
          <SettingsRow
            iconBg="#636366"
            icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M3 6h18v2H3zm0 5h18v2H3zm0 5h14v2H3z"/></svg>}
            title="Subtitles"
            subtitle="Language & styling"
            chevron={false}
            value="Off"
          />
          <RowDivider />
          <SettingsRow
            iconBg="#5856D6"
            icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M8 5v14l11-7z"/></svg>}
            title="Stream Auto-Play"
            subtitle="Automatically select best stream"
            chevron={false}
            value="On"
          />
          <RowDivider />
          <SettingsRow
            iconBg="#1A5FAB"
            icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M19.59 12.41L8.59 1.41A2 2 0 005.76 3l-.01 18a2 2 0 002.83 1.59l11-11a2 2 0 000-2.83 2 2 0 00-.99-.35z"/></svg>}
            title="Streaming Server"
            subtitle={serverUrl || 'Not configured'}
            value={serverStatusLabel}
            onClick={() => setShowServer(v => !v)}
          />

          {showServer && (
            <div className="p-4 border-t border-moonlit-border space-y-2">
              <div className="flex gap-2">
                <input
                  value={serverUrl}
                  onChange={e => { setServerUrlState(e.target.value); setServerStatus('idle'); }}
                  onKeyDown={e => e.key === 'Enter' && !testing && handleSaveServer()}
                  placeholder="https://moonlit-stremio-server.up.railway.app"
                  className="flex-1 px-4 py-2.5 bg-moonlit-elevated rounded-xl text-white placeholder-moonlit-muted focus:outline-none focus:ring-1 focus:ring-moonlit-accent text-sm border border-moonlit-border"
                />
                <button
                  onClick={handleSaveServer}
                  disabled={testing}
                  className="px-4 py-2.5 bg-moonlit-accent rounded-xl text-sm font-semibold disabled:opacity-40 hover:bg-moonlit-accent/90 transition-colors min-w-[110px] flex items-center justify-center"
                >
                  {testing
                    ? <div className="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent" />
                    : 'Save & Test'}
                </button>
              </div>
              <p className="text-[11px] text-moonlit-muted leading-relaxed">
                Plays streams the browser can't (MKV, etc.) by remuxing them. Deploy from
                <span className="text-white/50"> deploy/stremio-server/</span> on Railway or Render.
                Leave blank to use direct play only.
              </p>
            </div>
          )}
        </div>

        {/* ── APP ── */}
        <SectionLabel>App</SectionLabel>
        <div className="rounded-2xl bg-moonlit-surface border border-moonlit-border overflow-hidden">
          <SettingsRow
            iconBg="#3A3A3C"
            icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg>}
            title="Moonlit v1.0.0"
            subtitle="Powered by Stremio addon ecosystem"
            chevron={false}
          />
        </div>

        {/* ── Sign Out ── */}
        <button
          onClick={signOut}
          className="mt-6 w-full py-3.5 rounded-2xl bg-moonlit-surface border border-moonlit-border text-red-400 text-sm font-semibold hover:bg-red-500/5 transition-colors"
        >
          Sign Out
        </button>
      </div>
    </Sidebar>
  );
}
