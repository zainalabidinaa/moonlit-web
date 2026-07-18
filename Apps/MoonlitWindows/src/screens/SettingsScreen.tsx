import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import {
  Key, Play, Palette, Puzzle, Shield, User, ChevronRight,
  LogOut, RefreshCw
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { getInstalledAddons, generateInviteCode, getInviteCodes, revokeInviteCode, signOut } from '@/lib/services/api';
import { fetchManifest } from '@/lib/stremio';
import { getSystemAddon } from '@/lib/services/api';
import type { InviteCode, AddonManifest } from '@/lib/types';

type SettingsSection = 'general' | 'account' | 'playback' | 'appearance' | 'addons' | 'admin';

interface SidebarGroup {
  heading?: string;
  sections: { key: SettingsSection; label: string; icon: React.ReactNode }[];
}

interface ManagedAddonItem {
  manifestUrl: string;
  manifest: AddonManifest;
  enabled: boolean;
}

function loadAddonsFromStorage(): ManagedAddonItem[] {
  try {
    return JSON.parse(localStorage.getItem('moonlit.addons') || '[]');
  } catch { return []; }
}

function saveAddonsToStorage(addons: ManagedAddonItem[]) {
  localStorage.setItem('moonlit.addons', JSON.stringify(addons));
}

export function SettingsScreen() {
  const [selectedSection, setSelectedSection] = useState<SettingsSection>('general');
  const [profileName, setProfileName] = useState('Profile');
  const [profileEmail, setProfileEmail] = useState('');
  const [isAdmin, setIsAdmin] = useState(false);
  const [systemAddon, setSystemAddon] = useState<{ name: string; url: string } | null>(null);
  const [addons, setAddons] = useState<ManagedAddonItem[]>(loadAddonsFromStorage);
  const [inviteCodes, setInviteCodes] = useState<InviteCode[]>([]);
  const [inviteMaxUses, setInviteMaxUses] = useState(1);
  const [isGenerating, setIsGenerating] = useState(false);
  const [tmdbKey, setTmdbKey] = useState(localStorage.getItem('moonlit.tmdbApiKey') || '');
  const [cinematicMode, setCinematicMode] = useState(
    localStorage.getItem('moonlit.cinematicModeEnabled') !== 'false'
  );
  const [addonUrl, setAddonUrl] = useState('');
  const [isInstallingAddon, setIsInstallingAddon] = useState(false);

  const profileId = 'default';

  useEffect(() => {
    async function load() {
      try {
        const { data: { session } } = await supabase.auth.getSession();
        if (session?.user) {
          setProfileEmail(session.user.email || '');
          setProfileName(session.user.email?.split('@')[0] || 'Profile');
        }

        const { data: profiles } = await supabase
          .from('profiles')
          .select('*')
          .eq('user_id', session?.user?.id || '')
          .limit(1);
        if (profiles?.[0]) {
          setIsAdmin(profiles[0].role === 'admin');
          setProfileName(profiles[0].name || 'Profile');
        }

        const sys = await getSystemAddon();
        if (sys) setSystemAddon({ name: sys.name || 'System Addon', url: sys.manifest_url });

        if (profiles?.[0]?.role === 'admin') {
          const codes = await getInviteCodes();
          setInviteCodes(codes);
        }
      } catch {}
    }
    load();
  }, []);

  const sidebarGroups: SidebarGroup[] = [
    {
      heading: 'Account',
      sections: [
        { key: 'general', label: 'General', icon: <Key size={14} /> },
        { key: 'account', label: 'Account', icon: <User size={14} /> },
      ],
    },
    {
      heading: 'Playback',
      sections: [
        { key: 'playback', label: 'Playback', icon: <Play size={14} /> },
      ],
    },
    {
      heading: 'Appearance',
      sections: [
        { key: 'appearance', label: 'Appearance', icon: <Palette size={14} /> },
        { key: 'addons', label: 'Addons', icon: <Puzzle size={14} /> },
      ],
    },
  ];

  if (isAdmin) {
    sidebarGroups.push({
      heading: 'Admin',
      sections: [
        { key: 'admin', label: 'Admin', icon: <Shield size={14} /> },
      ],
    });
  }

  const handleSaveTMDBKey = () => {
    localStorage.setItem('moonlit.tmdbApiKey', tmdbKey);
  };

  const handleCinematicToggle = () => {
    const newVal = !cinematicMode;
    setCinematicMode(newVal);
    localStorage.setItem('moonlit.cinematicModeEnabled', String(newVal));
  };

  const handleGenerateCode = async () => {
    setIsGenerating(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (session?.user) {
        await generateInviteCode(session.user.id, inviteMaxUses);
        const codes = await getInviteCodes();
        setInviteCodes(codes);
      }
    } catch {}
    setIsGenerating(false);
  };

  const handleRevokeCode = async (code: string) => {
    await revokeInviteCode(code);
    const codes = await getInviteCodes();
    setInviteCodes(codes);
  };

  const handleInstallAddon = async () => {
    setIsInstallingAddon(true);
    try {
      const manifest = await fetchManifest(addonUrl);
      const exists = addons.find(a => a.manifestUrl === addonUrl || a.manifest.id === manifest.id);
      if (!exists) {
        const newAddons = [...addons, { manifestUrl: addonUrl, manifest, enabled: true }];
        setAddons(newAddons);
        saveAddonsToStorage(newAddons);
        setAddonUrl('');
      }
    } catch {}
    setIsInstallingAddon(false);
  };

  const handleToggleAddon = (index: number) => {
    const newAddons = [...addons];
    newAddons[index] = { ...newAddons[index], enabled: !newAddons[index].enabled };
    setAddons(newAddons);
    saveAddonsToStorage(newAddons);
  };

  const handleDeleteAddon = (index: number) => {
    const newAddons = addons.filter((_, i) => i !== index);
    setAddons(newAddons);
    saveAddonsToStorage(newAddons);
  };

  const handleSignOut = async () => {
    await signOut();
  };

  return (
    <div className="min-h-screen bg-moonlit-bg flex">
      <div className="w-[240px] shrink-0 bg-moonlit-surface/35 pt-20 pb-5 flex flex-col gap-4.5 overflow-y-auto">
        <div className="px-2.5">
          <div className="flex items-center gap-2.5 px-2 py-1.5 rounded-xl hover:bg-white/[0.04] cursor-pointer transition-colors"
            onClick={() => setSelectedSection('account')}
          >
            <div className="w-[34px] h-[34px] rounded-full bg-harbor-gold flex items-center justify-center shrink-0">
              <span className="text-[14px] font-bold text-white">{profileName[0]?.toUpperCase() || 'P'}</span>
            </div>
            <div className="flex flex-col gap-0.5 min-w-0">
              <span className="text-[13px] font-semibold text-white truncate">{profileName}</span>
              <span className="text-[10px] font-semibold text-harbor-gold">{isAdmin ? 'Admin' : 'Profile'}</span>
            </div>
          </div>
        </div>

        {sidebarGroups.map(group => (
          <div key={group.heading} className="flex flex-col gap-0.5">
            {group.heading && (
              <span className="text-[10px] font-bold text-white/35 tracking-[1px] uppercase px-2.5 pb-1">{group.heading}</span>
            )}
            {group.sections.map(section => {
              const isSelected = selectedSection === section.key;
              return (
                <button
                  key={section.key}
                  type="button"
                  onClick={() => setSelectedSection(section.key)}
                  className={`flex items-center gap-2.5 mx-2 px-1.5 py-1.5 rounded-[10px] transition-colors ${
                    isSelected ? 'bg-white/[0.06]' : ''
                  }`}
                >
                  <div className={`w-[34px] h-[34px] rounded-[9px] flex items-center justify-center ${
                    isSelected ? 'bg-white/[0.12]' : 'bg-white/[0.05]'
                  }`}>
                    <span className={isSelected ? 'text-harbor-gold' : 'text-white/55'}>
                      {section.icon}
                    </span>
                  </div>
                  <span className={`text-[13px] ${isSelected ? 'font-semibold text-white' : 'font-medium text-white/70'}`}>
                    {section.label}
                  </span>
                </button>
              );
            })}
          </div>
        ))}
      </div>

      <div className="w-px bg-white/[0.08]" />

      <div className="flex-1 overflow-y-auto">
        <div className="max-w-[640px] px-7 pt-20 pb-7">
          {selectedSection === 'general' && (
            <div className="flex flex-col gap-5.5">
              <div>
                <h2 className="text-[30px] font-bold text-white">General</h2>
                <p className="text-[13px] text-white/60 mt-1">Metadata sources, Trakt sync, and system addon status.</p>
              </div>

              <SettingsCard title="Metadata">
                <div className="px-[18px] py-3.5">
                  <div className="flex items-center gap-3.5">
                    <Key size={20} className="text-harbor-gold shrink-0" />
                    <div className="flex flex-col gap-0.5 flex-1">
                      <span className="text-[14px] font-semibold text-white">Metadata Integrations</span>
                      <span className="text-[12px] text-white/40">{tmdbKey ? 'TMDB configured' : 'No API keys configured'}</span>
                    </div>
                    <ChevronRight size={14} className="text-white/40" />
                  </div>
                </div>
                <div className="px-[18px] pb-4">
                  <label className="text-[11px] font-bold text-white/35 uppercase tracking-[1px] block mb-1.5">TMDB API Key</label>
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={tmdbKey}
                      onChange={e => setTmdbKey(e.target.value)}
                      placeholder="Paste TMDB API key"
                      className="flex-1 px-3 py-2 bg-white/[0.07] rounded-lg text-white text-[14px] outline-none border border-white/[0.09]"
                    />
                    <button
                      type="button"
                      onClick={handleSaveTMDBKey}
                      className="px-4 py-2 text-[13px] font-semibold text-black bg-harbor-gold rounded-lg"
                    >
                      Save
                    </button>
                  </div>
                </div>
              </SettingsCard>

              {systemAddon && (
                <SettingsCard title="System Addon">
                  <div className="flex items-center gap-3.5 px-[18px] py-3.5">
                    <div className="w-[34px] h-[34px] rounded-full bg-harbor-gold/20 flex items-center justify-center">
                      <Puzzle size={16} className="text-harbor-gold" />
                    </div>
                    <div className="flex flex-col gap-0.5 min-w-0">
                      <span className="text-[14px] font-semibold text-white">{systemAddon.name}</span>
                      <span className="text-[12px] text-white/40 truncate">{systemAddon.url}</span>
                    </div>
                  </div>
                </SettingsCard>
              )}
            </div>
          )}

          {selectedSection === 'account' && (
            <div className="flex flex-col gap-5.5">
              <div>
                <h2 className="text-[30px] font-bold text-white">Account</h2>
                <p className="text-[13px] text-white/60 mt-1">Your profile, app version, and sign-out.</p>
              </div>

              <div className="p-5 bg-white/[0.04] rounded-[20px] border border-white/[0.06]">
                <div className="flex items-center gap-4">
                  <div className="w-[62px] h-[62px] rounded-full bg-harbor-gold flex items-center justify-center shrink-0">
                    <span className="text-[22px] font-bold text-white">{profileName[0]?.toUpperCase() || 'P'}</span>
                  </div>
                  <div className="flex flex-col gap-1">
                    <div className="flex items-center gap-2">
                      <span className="text-[18px] font-bold text-white">{profileName}</span>
                      {isAdmin && (
                        <span className="text-[11px] font-bold text-harbor-gold px-2 py-0.5 bg-harbor-gold/[0.18] rounded-full">Admin</span>
                      )}
                    </div>
                    {profileEmail && (
                      <span className="text-[14px] text-white/60">{profileEmail}</span>
                    )}
                  </div>
                </div>
              </div>

              <SettingsCard title="About">
                <div className="flex items-center justify-between px-[18px] py-3.5">
                  <span className="text-[14px] font-semibold text-white">Version</span>
                  <span className="text-[14px] text-white/60">Moonlit for Windows · v1.0</span>
                </div>
              </SettingsCard>

              <button
                type="button"
                onClick={handleSignOut}
                className="flex items-center justify-center gap-2 w-full py-2.5 text-[14px] font-semibold text-red-400 bg-white/[0.04] rounded-xl border border-white/[0.06] hover:bg-red-400/10 transition-colors"
              >
                <LogOut size={16} />
                Sign Out
              </button>
            </div>
          )}

          {selectedSection === 'playback' && (
            <div className="flex flex-col gap-5.5">
              <div>
                <h2 className="text-[30px] font-bold text-white">Playback</h2>
                <p className="text-[13px] text-white/60 mt-1">Video engine, subtitle style, and stream auto-play behavior.</p>
              </div>

              <SettingsCard title="Playback">
                <SettingsRow icon={<Play size={18} />} title="Video Player" subtitle="Format compatibility, skip intro, player engine" />
                <Divider />
                <SettingsRow icon={<Play size={18} />} title="Subtitles" subtitle="Style and readability" />
                <Divider />
                <SettingsRow icon={<Play size={18} />} title="Stream Auto-Play" subtitle="Manual stream picker" />
              </SettingsCard>
            </div>
          )}

          {selectedSection === 'appearance' && (
            <div className="flex flex-col gap-5.5">
              <div>
                <h2 className="text-[30px] font-bold text-white">Appearance</h2>
                <p className="text-[13px] text-white/60 mt-1">Home row layout and collection display styles.</p>
              </div>

              <SettingsCard title="Appearance">
                <SettingsRow icon={<Palette size={18} />} title="Collection Design" subtitle="Home row visibility and display styles" />
                <Divider />
                <div className="flex items-center justify-between px-[18px] py-3.5">
                  <div className="flex items-center gap-3.5">
                    <Palette size={20} className="text-harbor-gold" />
                    <div className="flex flex-col gap-0.5">
                      <span className="text-[14px] font-semibold text-white">Cinematic Mode</span>
                      <span className="text-[12px] text-white/40">Use ambient hero artwork behind Home</span>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={handleCinematicToggle}
                    className={`w-11 h-6 rounded-full transition-colors relative ${cinematicMode ? 'bg-blue-500' : 'bg-white/[0.15]'}`}
                  >
                    <div className={`w-5 h-5 rounded-full bg-white absolute top-0.5 transition-transform ${cinematicMode ? 'translate-x-[22px]' : 'translate-x-[2px]'}`} />
                  </button>
                </div>
              </SettingsCard>
            </div>
          )}

          {selectedSection === 'addons' && (
            <div className="flex flex-col gap-5.5">
              <div>
                <h2 className="text-[30px] font-bold text-white">Addons</h2>
                <p className="text-[13px] text-white/60 mt-1">Install and manage the addons your library pulls from.</p>
              </div>

              <SettingsCard title="Install Addon">
                <div className="px-[18px] py-4">
                  <div className="flex gap-2.5">
                    <input
                      type="text"
                      value={addonUrl}
                      onChange={e => setAddonUrl(e.target.value)}
                      placeholder="https://.../manifest.json"
                      className="flex-1 px-3 py-2.5 bg-white/[0.07] rounded-lg text-white text-[14px] outline-none border border-white/[0.08]"
                    />
                    <button
                      type="button"
                      onClick={handleInstallAddon}
                      disabled={!addonUrl || isInstallingAddon}
                      className="px-5 py-2.5 text-[14px] font-semibold text-white bg-blue-500 rounded-lg disabled:opacity-40"
                    >
                      {isInstallingAddon ? 'Installing...' : 'Install'}
                    </button>
                  </div>
                </div>
              </SettingsCard>

              {addons.length === 0 ? (
                <div className="text-center py-8">
                  <p className="text-[14px] text-white/40">No addons installed. Add one above.</p>
                </div>
              ) : (
                <SettingsCard title={`Installed (${addons.length})`}>
                  {addons.map((addon, i) => (
                    <div key={i}>
                      <div className="flex items-center gap-3.5 px-[18px] py-3.5">
                        <div className="w-[36px] h-[36px] rounded-full bg-harbor-gold/20 flex items-center justify-center shrink-0">
                          <Puzzle size={18} className="text-harbor-gold" />
                        </div>
                        <div className="flex flex-col gap-1 flex-1 min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="text-[14px] font-semibold text-white">{addon.manifest.name}</span>
                            <span className="text-[10px] font-bold text-blue-400 px-1.5 py-0.5 bg-blue-400/15 rounded-full">System</span>
                          </div>
                          <span className="text-[12px] text-white/40 truncate">{addon.manifestUrl}</span>
                        </div>
                        <button
                          type="button"
                          onClick={() => handleToggleAddon(i)}
                          className={`w-11 h-6 rounded-full transition-colors relative ${addon.enabled ? 'bg-blue-500' : 'bg-white/[0.15]'}`}
                        >
                          <div className={`w-5 h-5 rounded-full bg-white absolute top-0.5 transition-transform ${addon.enabled ? 'translate-x-[22px]' : 'translate-x-[2px]'}`} />
                        </button>
                        <button
                          type="button"
                          onClick={() => handleDeleteAddon(i)}
                          className="text-red-400 text-[13px] font-medium hover:underline"
                        >
                          Remove
                        </button>
                      </div>
                      {i < addons.length - 1 && <Divider />}
                    </div>
                  ))}
                </SettingsCard>
              )}
            </div>
          )}

          {selectedSection === 'admin' && isAdmin && (
            <div className="flex flex-col gap-5.5">
              <div>
                <h2 className="text-[30px] font-bold text-white">Admin</h2>
                <p className="text-[13px] text-white/60 mt-1">Invite codes, catalogs, and hero carousel management.</p>
              </div>

              <SettingsCard title="Generate Invite Code">
                <div className="px-[18px] py-4">
                  <div className="flex items-center gap-4">
                    <span className="text-[14px] text-white/60">Max uses</span>
                    <div className="flex items-center gap-3">
                      <button
                        type="button"
                        onClick={() => setInviteMaxUses(Math.max(1, inviteMaxUses - 1))}
                        className="w-7 h-7 rounded-full bg-white/[0.08] text-white flex items-center justify-center"
                      >-</button>
                      <span className="text-[16px] font-semibold text-white w-6 text-center">{inviteMaxUses}</span>
                      <button
                        type="button"
                        onClick={() => setInviteMaxUses(Math.min(100, inviteMaxUses + 1))}
                        className="w-7 h-7 rounded-full bg-white/[0.08] text-white flex items-center justify-center"
                      >+</button>
                    </div>
                    <div className="flex-1" />
                    <button
                      type="button"
                      onClick={handleGenerateCode}
                      disabled={isGenerating}
                      className="px-5 py-2 text-[13px] font-semibold text-black bg-harbor-gold rounded-lg disabled:opacity-40"
                    >
                      {isGenerating ? 'Generating...' : 'Generate'}
                    </button>
                  </div>
                </div>
              </SettingsCard>

              <SettingsCard title={`Invite Codes (${inviteCodes.length})`}>
                {inviteCodes.length === 0 ? (
                  <div className="px-[18px] py-4 text-[12px] text-white/40">No invite codes yet.</div>
                ) : (
                  inviteCodes.map((code, i) => (
                    <div key={code.code}>
                      <div className="flex items-center gap-3 px-[18px] py-3">
                        <span className="text-[14px] font-bold font-mono text-harbor-gold">{code.code}</span>
                        <div className="flex-1" />
                        <div className={`w-[7px] h-[7px] rounded-full ${
                          code.is_active && !code.used_by ? 'bg-green-400' : code.used_by ? 'bg-gray-400' : 'bg-red-400'
                        }`} />
                        <span className="text-[12px] text-white/40">
                          {code.is_active && !code.used_by ? 'Active' : code.used_by ? 'Used' : 'Revoked'}
                        </span>
                        {code.is_active && !code.used_by && (
                          <button
                            type="button"
                            onClick={() => handleRevokeCode(code.code)}
                            className="text-red-400 text-[12px] font-medium hover:underline"
                          >
                            Revoke
                          </button>
                        )}
                      </div>
                      {i < inviteCodes.length - 1 && <Divider />}
                    </div>
                  ))
                )}
              </SettingsCard>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function SettingsCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <span className="text-[11px] font-bold text-white/35 tracking-[1px] uppercase pl-1 mb-2 block">{title}</span>
      <div className="bg-white/[0.04] rounded-[18px] border border-white/[0.06] overflow-hidden">
        {children}
      </div>
    </div>
  );
}

function SettingsRow({ icon, title, subtitle }: { icon: React.ReactNode; title: string; subtitle: string }) {
  return (
    <div className="flex items-center gap-3.5 px-[18px] py-3.5 cursor-pointer hover:bg-white/[0.02] transition-colors">
      <div className="w-[34px] flex items-center justify-center">
        <span className="text-harbor-gold">{icon}</span>
      </div>
      <div className="flex flex-col gap-0.5 flex-1">
        <span className="text-[14px] font-semibold text-white">{title}</span>
        <span className="text-[12px] text-white/40">{subtitle}</span>
      </div>
      <ChevronRight size={14} className="text-white/40" />
    </div>
  );
}

function Divider() {
  return <div className="h-px bg-white/[0.08] ml-[66px]" />;
}
