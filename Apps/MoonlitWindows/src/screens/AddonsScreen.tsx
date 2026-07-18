import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { Puzzle, Play, Info, Grid3X3, Subtitles, Box } from 'lucide-react';
import { fetchManifest } from '@/lib/stremio';
import StrokeSpinner from '@/components/StrokeSpinner';
import EmptyState from '@/components/EmptyState';
import type { AddonManifest } from '@/lib/types';

interface InstalledAddon {
  manifestUrl: string;
  manifest: AddonManifest;
  enabled: boolean;
}

const STORAGE_KEY = 'moonlit.addons';

function loadAddons(): InstalledAddon[] {
  try { return JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]'); }
  catch { return []; }
}

function saveAddons(addons: InstalledAddon[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(addons));
}

type AddonCategory = 'streaming' | 'metadata' | 'catalogs' | 'subtitles' | 'other';

interface CategoryDef {
  key: AddonCategory;
  label: string;
  icon: React.ReactNode;
  color: string;
}

const CATEGORIES: CategoryDef[] = [
  { key: 'streaming', label: 'Streaming', icon: <Play size={14} />, color: '#3B82F6' },
  { key: 'metadata', label: 'Metadata', icon: <Info size={14} />, color: '#A855F7' },
  { key: 'catalogs', label: 'Catalogs', icon: <Grid3X3 size={14} />, color: '#F97316' },
  { key: 'subtitles', label: 'Subtitles', icon: <Subtitles size={14} />, color: '#22C55E' },
  { key: 'other', label: 'Other', icon: <Box size={14} />, color: '#6B7280' },
];

function categorise(addon: InstalledAddon): AddonCategory {
  const m = addon.manifest;
  if (m.resources?.some(r => (typeof r === 'string' ? r === 'stream' : r.name === 'stream'))) return 'streaming';
  if (m.resources?.some(r => (typeof r === 'string' ? r === 'meta' : r.name === 'meta'))) return 'metadata';
  if (m.resources?.some(r => (typeof r === 'string' ? r === 'catalog' : r.name === 'catalog'))) return 'catalogs';
  if (m.catalogs && m.catalogs.length > 0) return 'catalogs';
  if (m.resources?.some(r => (typeof r === 'string' ? r === 'subtitles' : r.name === 'subtitles'))) return 'subtitles';
  return 'other';
}

function resourceBadges(addon: InstalledAddon): string[] {
  const badges: string[] = [];
  const m = addon.manifest;
  if (m.resources?.some(r => (typeof r === 'string' ? r === 'stream' : r.name === 'stream'))) badges.push('Stream');
  if (m.resources?.some(r => (typeof r === 'string' ? r === 'meta' : r.name === 'meta'))) badges.push('Metadata');
  if (m.resources?.some(r => (typeof r === 'string' ? r === 'catalog' : r.name === 'catalog'))) badges.push('Catalogs');
  if (m.catalogs && m.catalogs.length > 0) badges.push('Catalogs');
  if (m.resources?.some(r => (typeof r === 'string' ? r === 'subtitles' : r.name === 'subtitles'))) badges.push('Subtitles');
  return badges;
}

export function AddonsScreen() {
  const [addons, setAddons] = useState<InstalledAddon[]>(loadAddons);
  const [url, setUrl] = useState('');
  const [isInstalling, setIsInstalling] = useState(false);
  const [installError, setInstallError] = useState<string | null>(null);

  const groupedAddons = CATEGORIES.map(cat => {
    const items = addons.filter(a => categorise(a) === cat.key);
    return { ...cat, addons: items };
  }).filter(g => g.addons.length > 0);

  const handleInstall = async () => {
    setInstallError(null);
    setIsInstalling(true);
    try {
      const manifest = await fetchManifest(url);
      const exists = addons.find(a =>
        a.manifestUrl === url ||
        a.manifest.id === manifest.id ||
        a.manifest.transportUrl === manifest.transportUrl
      );
      if (exists) {
        setInstallError('Addon is already installed.');
      } else {
        const newAddons = [...addons, { manifestUrl: url, manifest, enabled: true }];
        setAddons(newAddons);
        saveAddons(newAddons);
        setUrl('');
      }
    } catch (e: any) {
      setInstallError(e.message || 'Failed to install addon');
    }
    setIsInstalling(false);
  };

  const handleToggle = (index: number) => {
    const newAddons = [...addons];
    newAddons[index] = { ...newAddons[index], enabled: !newAddons[index].enabled };
    setAddons(newAddons);
    saveAddons(newAddons);
  };

  const handleDelete = (index: number) => {
    const newAddons = addons.filter((_, i) => i !== index);
    setAddons(newAddons);
    saveAddons(newAddons);
  };

  return (
    <div className="min-h-screen bg-moonlit-bg">
      <div className="max-w-[760px] mx-auto px-6 pt-24 pb-12">
        <div className="mb-5">
          <span className="text-[11px] font-bold text-white/35 tracking-[1px] uppercase block mb-2">Install Addon</span>
          <div className="p-4 bg-white/[0.04] rounded-[18px] border border-white/[0.06]">
            <div className="flex gap-2.5">
              <input
                type="text"
                value={url}
                onChange={e => setUrl(e.target.value)}
                placeholder="https://.../manifest.json"
                className="flex-1 px-3 py-2.5 bg-white/[0.07] rounded-lg text-white text-[14px] outline-none border border-white/[0.08]"
              />
              <button
                type="button"
                onClick={handleInstall}
                disabled={!url || isInstalling}
                className="flex items-center gap-1.5 px-5 py-2.5 text-[14px] font-semibold text-white bg-blue-500 rounded-lg disabled:opacity-40 min-w-[96px] justify-center"
              >
                {isInstalling && <StrokeSpinner size={14} />}
                {isInstalling ? 'Installing' : 'Install'}
              </button>
            </div>
            {installError && (
              <p className="text-[12px] text-red-400 mt-2">{installError}</p>
            )}
          </div>
        </div>

        {groupedAddons.length === 0 ? (
          <EmptyState
            icon={<Puzzle size={24} />}
            title="No addons loaded"
            message="Install an addon using the URL field above."
          />
        ) : (
          groupedAddons.map(({ key, label, icon, color, addons: items }) => (
            <div key={key} className="mb-5">
              <div className="flex items-center gap-2 mb-2">
                <span style={{ color }}>{icon}</span>
                <span className="text-[12px] font-bold uppercase tracking-[1px]" style={{ color }}>{label}</span>
              </div>
              <div className="bg-white/[0.04] rounded-[18px] border border-white/[0.06] overflow-hidden">
                {items.map((addon, i) => {
                  const catDef = CATEGORIES.find(c => c.key === categorise(addon))!;
                  return (
                    <div key={i}>
                      <div className="flex items-center gap-3.5 px-4 py-4">
                        <div
                          className="w-[36px] h-[36px] rounded-full flex items-center justify-center shrink-0"
                          style={{ backgroundColor: `${catDef.color}28` }}
                        >
                          <span style={{ color: catDef.color }}>{catDef.icon}</span>
                        </div>
                        <div className="flex flex-col gap-1 flex-1 min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="text-[14px] font-semibold text-white">{addon.manifest.name}</span>
                            <span className="text-[10px] font-bold text-blue-400 px-1.5 py-0.5 bg-blue-400/15 rounded-full">System</span>
                          </div>
                          <span className="text-[12px] text-white/40 truncate">{addon.manifestUrl}</span>
                          <div className="flex gap-1.5 mt-0.5">
                            {resourceBadges(addon).map(badge => (
                              <span
                                key={badge}
                                className="text-[10px] font-semibold text-white/75 px-1.5 py-0.5 bg-white/[0.1] rounded-full"
                              >
                                {badge}
                              </span>
                            ))}
                          </div>
                        </div>
                        <button
                          type="button"
                          onClick={() => handleToggle(i)}
                          className={`w-11 h-6 rounded-full transition-colors relative shrink-0 ${addon.enabled ? 'bg-blue-500' : 'bg-white/[0.15]'}`}
                        >
                          <div className={`w-5 h-5 rounded-full bg-white absolute top-0.5 transition-transform ${addon.enabled ? 'translate-x-[22px]' : 'translate-x-[2px]'}`} />
                        </button>
                        <button
                          type="button"
                          onClick={() => handleDelete(i)}
                          className="text-red-400 text-[13px] font-medium hover:underline shrink-0"
                        >
                          Remove
                        </button>
                      </div>
                      {i < items.length - 1 && <div className="h-px bg-white/[0.08] ml-[62px]" />}
                    </div>
                  );
                })}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
