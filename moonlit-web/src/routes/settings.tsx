import { useState, useCallback, useEffect, useRef } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ProfileAvatar } from '@/components/ProfileAvatar';
import { getInstalledAddons, saveInstalledAddons } from '@/lib/services/api';
import { fetchManifest } from '@/lib/stremio';
import { DEFAULT_ADDONS } from '@/lib/supabase';
import type { AddonManifest } from '@/lib/types';
import { useNavigate } from '@tanstack/react-router';
import { getStreamingServerUrl, setStreamingServerUrl } from '@/lib/config';
import { pingServer } from '@/lib/streaming-server';
import {
  createProfilePreferencesRepository,
  DEFAULT_HOME_PREFERENCES,
  DEFAULT_ARTWORK_PREFERENCES,
  DEFAULT_PLAYER_PREFERENCES,
  DEFAULT_SUBTITLE_PREFERENCES,
  normalizeSubtitlePreferences,
  type HomePreferences,
  type ArtworkPreferences,
  type PlayerPreferences,
  type SubtitlePreferences,
  type PlayerEnginePreference,
  type PlayerCacheMode,
  type SubtitlePreset,
  type SubtitleAlignment,
} from '@/lib/preferences/profile-preferences';
import { saveSubtitlePreferences, loadSubtitlePreferences, subscribeSubtitlePreferences } from '@/lib/subtitle-preferences';
import { isDesktop } from '@/lib/platform';

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
  subtitles:    { label: 'Subtitles', color: 'text-moonlit-gold bg-moonlit-gold/10 border-moonlit-gold/20' },
  addon_catalog:{ label: 'Directory', color: 'text-slate-400  bg-slate-400/10  border-slate-400/20'  },
};

function CapabilityBadge({ cap }: { cap: string }) {
  const cfg = CAPABILITY_LABELS[cap] ?? { label: cap, color: 'text-white/50 bg-white/5 border-white/10' };
  return (
    <span className={`text-[10px] font-bold px-2 py-0.5 rounded border ${cfg.color}`}>
      {cfg.label}
    </span>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-xs font-bold text-white/40 uppercase tracking-wider px-1 pt-6 pb-1.5">
      {children}
    </p>
  );
}

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
        className="w-7 h-7 rounded flex items-center justify-center shrink-0"
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

function Toggle({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <label className="flex items-center justify-between gap-3 py-2 px-4 hover:bg-white/[0.02] cursor-pointer">
      <span className="text-sm text-white/80">{label}</span>
      <button
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`relative inline-flex h-6 w-10 items-center rounded-full transition-colors ${checked ? 'bg-white' : 'bg-white/15'}`}
      >
        <span
          className={`inline-block h-4 w-4 rounded-full bg-black transition-transform ${checked ? 'translate-x-5' : 'translate-x-1'}`}
        />
      </button>
    </label>
  );
}

function SliderSetting({ label, value, min, max, step, onChange, unit }: {
  label: string; value: number; min: number; max: number; step: number;
  onChange: (v: number) => void; unit?: string;
}) {
  return (
    <label className="flex items-center justify-between gap-4 py-2 px-4 hover:bg-white/[0.02] cursor-pointer">
      <span className="text-sm text-white/80 min-w-0">{label}</span>
      <div className="flex items-center gap-2 shrink-0">
        <input
          type="range"
          min={min}
          max={max}
          step={step}
          value={value}
          onChange={e => onChange(parseFloat(e.target.value))}
          className="w-24 h-1.5 accent-white"
        />
        <span className="text-xs text-white/40 w-12 text-right tabular-nums">
          {value}{unit ?? ''}
        </span>
      </div>
    </label>
  );
}

function SelectSetting<T extends string>({ label, value, options, onChange }: {
  label: string; value: T; options: { value: T; label: string }[];
  onChange: (v: T) => void;
}) {
  return (
    <label className="flex items-center justify-between gap-4 py-2 px-4 hover:bg-white/[0.02]">
      <span className="text-sm text-white/80">{label}</span>
      <select
        value={value}
        onChange={e => onChange(e.target.value as T)}
        className="bg-[#2a2a2a] rounded text-sm text-white px-2 py-1 border border-white/10 focus:outline-none focus:ring-1 focus:ring-white/30"
      >
        {options.map(o => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </label>
  );
}

function ColorSetting({ label, value, onChange }: {
  label: string; value: string; onChange: (v: string) => void;
}) {
  return (
    <label className="flex items-center justify-between gap-4 py-2 px-4 hover:bg-white/[0.02]">
      <span className="text-sm text-white/80">{label}</span>
      <div className="flex items-center gap-2">
        <input
          type="color"
          value={value}
          onChange={e => onChange(e.target.value)}
          className="w-7 h-7 rounded border border-white/10 bg-transparent cursor-pointer"
        />
        <span className="text-xs text-white/40 w-16 tabular-nums">{value}</span>
      </div>
    </label>
  );
}

function ArtworkPreview({ scale, radius, halo }: { scale: number; radius: number; halo: boolean }) {
  return (
    <div className="flex justify-center py-6 bg-[#191919] rounded border border-white/5">
      <div className="relative" style={{ perspective: '800px' }}>
        {halo && (
          <>
            <div className="absolute -inset-3 rounded opacity-30 blur-xl"
              style={{ background: 'linear-gradient(135deg, rgba(255,255,255,0.15), rgba(255,255,255,0.05))' }} />
            <div className="absolute -inset-6 rounded opacity-15 blur-2xl"
              style={{ background: 'linear-gradient(135deg, rgba(255,255,255,0.1), transparent)' }} />
          </>
        )}
        <div
          className="relative bg-gradient-to-br from-[#2a2a2a] to-[#1a1a1a] border border-white/10 overflow-hidden"
          style={{
            width: `${154 * scale}px`,
            height: `${231 * scale}px`,
            borderRadius: `${radius}px`,
          }}
        >
          <div className="absolute inset-0 flex items-center justify-center">
            <svg viewBox="0 0 24 24" fill="none" className="w-8 h-8 text-white/15" stroke="currentColor" strokeWidth="1">
              <rect x="3" y="3" width="18" height="18" rx="3" />
              <path d="M3 16l5-5 4 4 5-5 4 4" />
              <circle cx="8.5" cy="8.5" r="1.5" />
            </svg>
          </div>
        </div>
      </div>
    </div>
  );
}

function SubtitlePreview({ prefs }: { prefs: SubtitlePreferences }) {
  const n = normalizeSubtitlePreferences(prefs);
  return (
    <div className="flex justify-center py-8 bg-[#111111] rounded border border-white/5 relative">
      <div className="absolute top-3 left-3 text-[10px] text-white/20">Preview</div>
      <div
        className="text-center px-4 max-w-sm"
        style={{
          fontSize: `${Math.round(n.fontSize * n.scale)}px`,
          color: n.textColorHex,
          fontWeight: n.isBold ? 700 : 400,
          fontStyle: n.isItalic ? 'italic' : 'normal',
          textShadow: `0 0 ${n.textBlur}px rgba(0,0,0,0.8), ${['left', 'right'].includes(n.horizontalAlignment) ? 'none' : '-1px -1px 0 ' + n.outlineColorHex + ', 1px -1px 0 ' + n.outlineColorHex + ', -1px 1px 0 ' + n.outlineColorHex + ', 1px 1px 0 ' + n.outlineColorHex}`,
          background: n.backgroundColorHex
            ? `linear-gradient(${n.backgroundColorHex}${Math.round(n.backgroundOpacity * 255).toString(16).padStart(2, '0')}, ${n.backgroundColorHex}${Math.round(n.backgroundOpacity * 255).toString(16).padStart(2, '0')})`
            : undefined,
          textAlign: n.horizontalAlignment as 'left' | 'center' | 'right',
          padding: `${n.horizontalMargin}px ${n.horizontalMargin}px`,
        }}
      >
        This is how your subtitles will look
      </div>
    </div>
  );
}

export default function SettingsPage() {
  const { currentProfile, signOut, refreshAddons } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [newUrl, setNewUrl] = useState('');
  const [installing, setInstalling] = useState(false);
  const [installError, setInstallError] = useState('');
  const [showAddons, setShowAddons] = useState(false);
  const [showServer, setShowServer] = useState(false);
  const [showHome, setShowHome] = useState(false);
  const [showArtwork, setShowArtwork] = useState(false);
  const [showPlayer, setShowPlayer] = useState(false);
  const [showSubtitles, setShowSubtitles] = useState(false);

  const [serverUrl, setServerUrlState] = useState(() => getStreamingServerUrl());
  const [testing, setTesting] = useState(false);
  const [serverStatus, setServerStatus] = useState<'idle' | 'ok' | 'fail'>('idle');

  const repo = createProfilePreferencesRepository();

  const { data: prefs } = useQuery({
    queryKey: ['profile-preferences', currentProfile?.id],
    queryFn: async () => {
      if (!currentProfile) return null;
      const results = await Promise.all([
        repo.load(currentProfile.id, 'home'),
        repo.load(currentProfile.id, 'artwork'),
        repo.load(currentProfile.id, 'player'),
      ]);
      return {
        home: results[0].value as HomePreferences,
        artwork: results[1].value as ArtworkPreferences,
        player: results[2].value as PlayerPreferences,
        subtitles: loadSubtitlePreferences(),
      };
    },
    enabled: !!currentProfile,
  });

  const [homePrefs, setHomePrefs] = useState<HomePreferences>(DEFAULT_HOME_PREFERENCES);
  const [artworkPrefs, setArtworkPrefs] = useState<ArtworkPreferences>(DEFAULT_ARTWORK_PREFERENCES);
  const [playerPrefs, setPlayerPrefs] = useState<PlayerPreferences>(DEFAULT_PLAYER_PREFERENCES);
  const [subPrefs, setSubPrefs] = useState<SubtitlePreferences>(DEFAULT_SUBTITLE_PREFERENCES);
  const prefsInitialized = useRef(false);

  useEffect(() => {
    if (prefs && !prefsInitialized.current) {
      prefsInitialized.current = true;
      setHomePrefs(prefs.home);
      setArtworkPrefs(prefs.artwork);
      setPlayerPrefs(prefs.player);
      setSubPrefs(prefs.subtitles);
    }
  }, [prefs]);

  useEffect(() => {
    return subscribeSubtitlePreferences(newPrefs => {
      setSubPrefs(newPrefs);
    });
  }, []);

  const savePrefs = useCallback(async () => {
    if (!currentProfile) return;
    void Promise.all([
      repo.save(currentProfile.id, 'home', homePrefs),
      repo.save(currentProfile.id, 'artwork', artworkPrefs),
      repo.save(currentProfile.id, 'player', playerPrefs),
    ]);
    saveSubtitlePreferences(subPrefs);
  }, [currentProfile, homePrefs, artworkPrefs, playerPrefs, subPrefs, repo]);

  const resetSection = useCallback(async <T extends keyof typeof defaults>(namespace: T, setter: (v: (typeof defaults)[T]) => void) => {
    const defaults = {
      home: DEFAULT_HOME_PREFERENCES,
      artwork: DEFAULT_ARTWORK_PREFERENCES,
      player: DEFAULT_PLAYER_PREFERENCES,
      subtitles: DEFAULT_SUBTITLE_PREFERENCES,
    } as const;
    const value = defaults[namespace];
    setter(value as (typeof defaults)[T]);
    if (!currentProfile) return;
    if (namespace === 'subtitles') {
      saveSubtitlePreferences(value as SubtitlePreferences);
    } else {
      void repo.save(currentProfile.id, namespace, value);
    }
  }, [currentProfile, repo]);

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
          try { cache[url] = await fetchManifest(url); } catch { /* skip unreachable addon */ }
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

  const ENGINE_OPTIONS: { value: PlayerEnginePreference; label: string }[] = [
    { value: 'auto', label: 'Auto' },
    { value: 'native', label: 'Native' },
    { value: 'mpv', label: 'MPV' },
  ];

  const CACHE_OPTIONS: { value: PlayerCacheMode; label: string }[] = [
    { value: 'memory', label: 'Memory' },
    { value: 'disk', label: 'Disk' },
    { value: 'off', label: 'Off' },
  ];

  const PRESET_OPTIONS: { value: SubtitlePreset; label: string }[] = [
    { value: 'standard', label: 'Standard' },
    { value: 'boxed', label: 'Boxed' },
    { value: 'classic', label: 'Classic' },
    { value: 'minimal', label: 'Minimal' },
  ];

  const ALIGN_OPTIONS: { value: SubtitleAlignment; label: string }[] = [
    { value: 'left', label: 'Left' },
    { value: 'center', label: 'Center' },
    { value: 'right', label: 'Right' },
  ];

  return (
    <div className="px-6 md:px-14 py-8 max-w-2xl mx-auto">
      <h1 className="text-2xl font-bold text-white mb-6">Settings</h1>

      <div className="rounded bg-[#1f1f1f] border border-white/10 overflow-hidden">
        <div className="px-4 py-3.5 flex items-center gap-3">
          {currentProfile && <ProfileAvatar profile={currentProfile} size={44} className="shrink-0" />}
          <div className="flex-1 min-w-0">
            <p className="font-semibold text-white text-sm">{currentProfile?.name}</p>
            <p className="text-xs text-moonlit-muted mt-0.5">{currentProfile?.role === 'admin' ? 'Administrator' : 'Member'}</p>
          </div>
          <button onClick={() => navigate({ to: '/profiles' })}
            className="text-xs text-white/80 font-semibold px-3 py-1.5 rounded bg-white/8 border border-white/[0.12] hover:bg-white/15 transition-colors shrink-0">
            Switch
          </button>
        </div>
      </div>

      <div className="flex items-center justify-between mt-6">
        <SectionLabel>Compatibility</SectionLabel>
        {isDesktop() && (
          <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-white/5 text-white/30 border border-white/10">
            Desktop
          </span>
        )}
      </div>
      <div className="rounded bg-[#1f1f1f] border border-white/10 overflow-hidden">
        <SettingsRow
          iconBg="#2C7DE8"
          icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M3 3h18v2H3zm0 4h18v2H3zm0 4h12v2H3zm0 4h12v2H3zm0 4h18v2H3z"/></svg>}
          title="Metadata"
          subtitle="TMDB · TVDB sources"
          chevron={false}
          value="TMDB"
        />
        {isDesktop() && (
          <>
            <RowDivider />
            <SettingsRow
              iconBg="#8B5CF6"
              icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M12 2l8 4v6c0 5-3.4 8.4-8 10-4.6-1.6-8-5-8-10V6l8-4z"/></svg>}
              title="Anime4K"
              subtitle="GPU-accelerated upscaling"
              chevron={false}
              value="Available"
            />
          </>
        )}
      </div>

      {currentProfile?.role === 'admin' && (
        <>
          <SectionLabel>Admin</SectionLabel>
          <div className="rounded bg-[#1f1f1f] border border-white/10 overflow-hidden">
            <SettingsRow
              iconBg="#636366"
              icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M12 2l8 4v6c0 5-3.4 8.4-8 10-4.6-1.6-8-5-8-10V6l8-4zm0 6a2.5 2.5 0 100 5 2.5 2.5 0 000-5zm-4 9a4 4 0 018 0H8z"/></svg>}
              title="Admin Dashboard"
              subtitle="Collections, invite codes & stats"
              onClick={() => navigate({ to: '/admin' })}
            />
          </div>
        </>
      )}

      <SectionLabel>Content Management</SectionLabel>
      <div className="rounded bg-[#1f1f1f] border border-white/10 overflow-hidden">
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
          <div className="border-t border-white/10">
            {isLoading ? (
              <div className="p-5 flex justify-center">
                <div className="w-5 h-5 rounded-full border-2 border-white/[0.14] border-t-white animate-spin-arc" />
              </div>
            ) : (
              <div className="divide-y divide-white/10">
                {addonUrls.map(url => {
                  const manifest = manifestCache[url];
                  const caps = manifest ? getAddonCapabilities(manifest) : [];
                  const isDefault = DEFAULT_ADDONS.includes(url);
                  return (
                    <div key={url} className="px-4 py-3.5 flex items-start justify-between gap-3">
                      <div className="flex items-start gap-3 min-w-0 flex-1">
                        {manifest?.logo && (
                          <img src={manifest.logo} alt="" width={32} height={32} loading="eager"
                            className="w-8 h-8 rounded object-contain bg-white/5 shrink-0 mt-0.5" />
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
                          className="text-xs text-red-400/70 hover:text-red-400 border border-red-400/20 hover:border-red-400/40 px-2.5 py-1 rounded transition-all shrink-0 mt-0.5">
                          Remove
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
            )}

            <div className="p-4 border-t border-white/10 space-y-2">
              <div className="flex gap-2">
                <label htmlFor="addon-url" className="sr-only">Addon manifest URL</label>
                <input
                  id="addon-url"
                  value={newUrl}
                  onChange={e => { setNewUrl(e.target.value); setInstallError(''); }}
                  onKeyDown={e => e.key === 'Enter' && !installing && handleInstall()}
                  placeholder="https://.../manifest.json"
                  className="flex-1 px-4 py-2.5 bg-[#2a2a2a] rounded text-white placeholder-moonlit-muted focus:outline-none focus:ring-1 focus:ring-white/30 text-sm border border-white/10"
                />
                <button
                  onClick={handleInstall}
                  disabled={!newUrl.trim() || installing}
                  className="px-4 py-2.5 bg-white text-black rounded text-sm font-semibold disabled:opacity-40 hover:bg-white/90 transition-colors min-w-[80px] flex items-center justify-center"
                >
                  {installing
                    ? <div className="w-4 h-4 rounded-full border-2 border-black/20 border-t-black animate-spin-arc" />
                    : 'Install'}
                </button>
              </div>
              {installError && <p className="text-xs text-red-400" role="alert">{installError}</p>}
              <p className="text-[11px] text-moonlit-muted">
                Paste a Stremio addon manifest URL.
              </p>
            </div>
          </div>
        )}
      </div>

      <SectionLabel>Home</SectionLabel>
      <div className="rounded bg-[#1f1f1f] border border-white/10 overflow-hidden">
        <SettingsRow
          iconBg="#007AFF"
          icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>}
          title="Home Screen"
          subtitle={`Cinematic mode ${homePrefs.cinematicModeEnabled ? 'on' : 'off'}`}
          onClick={() => setShowHome(v => !v)}
        />
        {showHome && (
          <div className="border-t border-white/10">
            <Toggle checked={homePrefs.cinematicModeEnabled} onChange={v => setHomePrefs(p => ({ ...p, cinematicModeEnabled: v }))} label="Cinematic mode" />
            <div className="flex justify-end px-4 py-2">
              <button onClick={() => { setHomePrefs(DEFAULT_HOME_PREFERENCES); savePrefs(); }}
                className="text-xs text-white/40 hover:text-white mr-2">Reset</button>
              <button onClick={savePrefs}
                className="text-xs font-semibold text-white bg-white/10 px-3 py-1 rounded hover:bg-white/20">Save</button>
            </div>
          </div>
        )}
      </div>

      <SectionLabel>Appearance</SectionLabel>
      <div className="rounded bg-[#1f1f1f] border border-white/10 overflow-hidden">
        <SettingsRow
          iconBg="#FF9500"
          icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M20 3H4c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM8.5 19h7c.3 0 .5.2.5.5s-.2.5-.5.5z"/></svg>}
          title="Artwork"
          subtitle={`Scale ${artworkPrefs.posterScale}x · Radius ${artworkPrefs.posterRadius}px`}
          value={artworkPrefs.artworkHaloEnabled ? 'Halo on' : 'Halo off'}
          onClick={() => setShowArtwork(v => !v)}
        />
        {showArtwork && (
          <div className="border-t border-white/10">
            <ArtworkPreview scale={artworkPrefs.posterScale} radius={artworkPrefs.posterRadius} halo={artworkPrefs.artworkHaloEnabled} />
            <SliderSetting label="Poster scale" value={artworkPrefs.posterScale} min={0.5} max={2} step={0.05}
              onChange={v => setArtworkPrefs(p => ({ ...p, posterScale: v }))} unit="x" />
            <SliderSetting label="Poster radius" value={artworkPrefs.posterRadius} min={0} max={24} step={1}
              onChange={v => setArtworkPrefs(p => ({ ...p, posterRadius: v }))} unit="px" />
            <Toggle checked={artworkPrefs.artworkHaloEnabled}
              onChange={v => setArtworkPrefs(p => ({ ...p, artworkHaloEnabled: v }))} label="Artwork halo" />
            <Toggle checked={artworkPrefs.hoverPreviewEnabled}
              onChange={v => setArtworkPrefs(p => ({ ...p, hoverPreviewEnabled: v }))} label="Hover preview" />
            {artworkPrefs.hoverPreviewEnabled && (
              <SliderSetting label="Preview delay" value={artworkPrefs.hoverPreviewDelaySeconds} min={0.1} max={2} step={0.1}
                onChange={v => setArtworkPrefs(p => ({ ...p, hoverPreviewDelaySeconds: v }))} unit="s" />
            )}
            <div className="px-4 pt-2 pb-1">
              <p className="text-xs font-bold text-white/40 uppercase tracking-wider">Poster Badges</p>
              <p className="text-[11px] text-white/30 mt-0.5">bttrr.cc overlays</p>
            </div>
            <Toggle checked={artworkPrefs.posterBadges.trend}
              onChange={v => setArtworkPrefs(p => ({ ...p, posterBadges: { ...p.posterBadges, trend: v } }))} label="Trend" />
            <Toggle checked={artworkPrefs.posterBadges.genre}
              onChange={v => setArtworkPrefs(p => ({ ...p, posterBadges: { ...p.posterBadges, genre: v } }))} label="Genre" />
            <Toggle checked={artworkPrefs.posterBadges.rating}
              onChange={v => setArtworkPrefs(p => ({ ...p, posterBadges: { ...p.posterBadges, rating: v } }))} label="Rating" />
            <Toggle checked={artworkPrefs.posterBadges.quality}
              onChange={v => setArtworkPrefs(p => ({ ...p, posterBadges: { ...p.posterBadges, quality: v } }))} label="Quality" />
            <Toggle checked={artworkPrefs.posterBadges.age}
              onChange={v => setArtworkPrefs(p => ({ ...p, posterBadges: { ...p.posterBadges, age: v } }))} label="Age rating" />
            <div className="flex justify-end px-4 py-2">
              <button onClick={() => resetSection('artwork', setArtworkPrefs)}
                className="text-xs text-white/40 hover:text-white mr-2">Reset</button>
              <button onClick={savePrefs}
                className="text-xs font-semibold text-white bg-white/10 px-3 py-1 rounded hover:bg-white/20">Save</button>
            </div>
          </div>
        )}
      </div>

      <SectionLabel>Playback</SectionLabel>
      <div className="rounded bg-[#1f1f1f] border border-white/10 overflow-hidden">
        <SettingsRow
          iconBg="#FF3B30"
          icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M4 4h16a1 1 0 011 1v14a1 1 0 01-1 1H4a1 1 0 01-1-1V5a1 1 0 011-1zm6 7.5l5 2.5-5 2.5v-5z"/></svg>}
          title="Video Player"
          subtitle={playerPrefs.usePerTypePlayers ? 'Per-type' : playerPrefs.moviePlayer}
          value={playerPrefs.showOnlyCompatibleFormats ? 'Compatible only' : 'Auto'}
          onClick={() => setShowPlayer(v => !v)}
        />
        <RowDivider />
        <SettingsRow
          iconBg="#636366"
          icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M3 6h18v2H3zm0 5h18v2H3zm0 5h14v2H3z"/></svg>}
          title="Subtitles"
          subtitle={subPrefs.preset}
          value={`${subPrefs.fontSize}px`}
          onClick={() => setShowSubtitles(v => !v)}
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

        {showPlayer && (
          <div className="border-t border-white/10">
            <Toggle checked={playerPrefs.autoplayNextEpisode}
              onChange={v => setPlayerPrefs(p => ({ ...p, autoplayNextEpisode: v }))} label="Autoplay next episode" />
            <Toggle checked={playerPrefs.showSkipIntroButton}
              onChange={v => setPlayerPrefs(p => ({ ...p, showSkipIntroButton: v }))} label="Show skip intro button" />
            <Toggle checked={playerPrefs.autoSkipIntros}
              onChange={v => setPlayerPrefs(p => ({ ...p, autoSkipIntros: v }))} label="Auto-skip intros" />
            <Toggle checked={playerPrefs.showTimelineHighlights}
              onChange={v => setPlayerPrefs(p => ({ ...p, showTimelineHighlights: v }))} label="Timeline highlights" />
            <Toggle checked={playerPrefs.autoplayPreviews}
              onChange={v => setPlayerPrefs(p => ({ ...p, autoplayPreviews: v }))} label="Autoplay previews" />
            <Toggle checked={playerPrefs.showOnlyCompatibleFormats}
              onChange={v => setPlayerPrefs(p => ({ ...p, showOnlyCompatibleFormats: v }))} label="Show only compatible formats" />
            {isDesktop() && (
              <Toggle checked={playerPrefs.anime4KEnabled}
                onChange={v => setPlayerPrefs(p => ({ ...p, anime4KEnabled: v }))} label="Anime4K upscaling" />
            )}
            <SelectSetting label="Cache mode" value={playerPrefs.cacheMode} options={CACHE_OPTIONS}
              onChange={v => setPlayerPrefs(p => ({ ...p, cacheMode: v }))} />
            <SelectSetting label="Movie player" value={playerPrefs.moviePlayer} options={ENGINE_OPTIONS}
              onChange={v => setPlayerPrefs(p => ({ ...p, moviePlayer: v }))} />
            <SelectSetting label="Series player" value={playerPrefs.seriesPlayer} options={ENGINE_OPTIONS}
              onChange={v => setPlayerPrefs(p => ({ ...p, seriesPlayer: v }))} />
            <SelectSetting label="Live TV player" value={playerPrefs.livePlayer} options={ENGINE_OPTIONS}
              onChange={v => setPlayerPrefs(p => ({ ...p, livePlayer: v }))} />
            <div className="flex justify-end px-4 py-2">
              <button onClick={() => resetSection('player', setPlayerPrefs)}
                className="text-xs text-white/40 hover:text-white mr-2">Reset</button>
              <button onClick={savePrefs}
                className="text-xs font-semibold text-white bg-white/10 px-3 py-1 rounded hover:bg-white/20">Save</button>
            </div>
          </div>
        )}

        {showSubtitles && (
          <div className="border-t border-white/10">
            <SubtitlePreview prefs={subPrefs} />
            <SelectSetting label="Preset" value={subPrefs.preset} options={PRESET_OPTIONS}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, preset: v }))} />
            <SliderSetting label="Font size" value={subPrefs.fontSize} min={16} max={64} step={1}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, fontSize: v }))} unit="px" />
            <SliderSetting label="Scale" value={subPrefs.scale} min={0.5} max={2} step={0.05}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, scale: v }))} unit="x" />
            <Toggle checked={subPrefs.isBold}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, isBold: v }))} label="Bold" />
            <Toggle checked={subPrefs.isItalic}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, isItalic: v }))} label="Italic" />
            <ColorSetting label="Text color" value={subPrefs.textColorHex}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, textColorHex: v }))} />
            <ColorSetting label="Outline color" value={subPrefs.outlineColorHex}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, outlineColorHex: v }))} />
            <ColorSetting label="Background color" value={subPrefs.backgroundColorHex}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, backgroundColorHex: v }))} />
            <SliderSetting label="Background opacity" value={subPrefs.backgroundOpacity} min={0} max={1} step={0.05}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, backgroundOpacity: v }))} unit="" />
            <SelectSetting label="Alignment" value={subPrefs.horizontalAlignment} options={ALIGN_OPTIONS}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, horizontalAlignment: v }))} />
            <SliderSetting label="Vertical position" value={subPrefs.verticalPosition} min={0} max={200} step={1}
              onChange={v => setSubPrefs(p => normalizeSubtitlePreferences({ ...p, verticalPosition: v }))} unit="px" />
            <div className="flex justify-end px-4 py-2">
              <button onClick={() => resetSection('subtitles', setSubPrefs)}
                className="text-xs text-white/40 hover:text-white mr-2">Reset</button>
              <button onClick={savePrefs}
                className="text-xs font-semibold text-white bg-white/10 px-3 py-1 rounded hover:bg-white/20">Save</button>
            </div>
          </div>
        )}

        {showServer && (
          <div className="p-4 border-t border-white/10 space-y-2">
            <div className="flex gap-2">
              <label htmlFor="server-url" className="sr-only">Streaming server URL</label>
              <input
                id="server-url"
                value={serverUrl}
                onChange={e => { setServerUrlState(e.target.value); setServerStatus('idle'); }}
                onKeyDown={e => e.key === 'Enter' && !testing && handleSaveServer()}
                placeholder="https://moonlit-stremio-server.up.railway.app"
                className="flex-1 px-4 py-2.5 bg-[#2a2a2a] rounded text-white placeholder-moonlit-muted focus:outline-none focus:ring-1 focus:ring-white/30 text-sm border border-white/10"
              />
              <button
                onClick={handleSaveServer}
                disabled={testing}
                className="px-4 py-2.5 bg-white text-black rounded text-sm font-semibold disabled:opacity-40 hover:bg-white/90 transition-colors min-w-[110px] flex items-center justify-center"
              >
                {testing
                  ? <div className="w-4 h-4 rounded-full border-2 border-black/20 border-t-black animate-spin-arc" />
                  : 'Save & Test'}
              </button>
            </div>
            <p className="text-[11px] text-moonlit-muted leading-relaxed">
              Plays streams the browser can't (MKV, etc.) by remuxing them. Deploy from
              <span className="text-white/50"> deploy/stremio-server/</span> on Railway or Render.
            </p>
          </div>
        )}
      </div>

      <SectionLabel>App</SectionLabel>
      <div className="rounded bg-[#1f1f1f] border border-white/10 overflow-hidden">
        <SettingsRow
          iconBg="#3A3A3C"
          icon={<svg viewBox="0 0 24 24" fill="white" className="w-4 h-4"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg>}
          title="Moonlit v1.0.0"
          subtitle="Powered by Stremio addon ecosystem"
          chevron={false}
        />
      </div>

      <button
        onClick={signOut}
        className="mt-6 w-full py-3.5 rounded bg-[#1f1f1f] border border-white/10 text-red-400 text-sm font-semibold hover:bg-red-500/5 transition-colors"
      >
        Sign Out
      </button>
    </div>
  );
}
