import { useState, useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import { useAuth } from '@/app/AuthProvider';
import { isDesktop } from '@/lib/platform';
import { SPRING } from '@/lib/design/motion';
import type { Tab } from './Shell';

const TABS: { id: Tab; label: string; shortcut: number }[] = [
  { id: 'home', label: 'Home', shortcut: 1 },
  { id: 'movies', label: 'Movies', shortcut: 2 },
  { id: 'series', label: 'Series', shortcut: 3 },
  { id: 'live', label: 'Live TV', shortcut: 4 },
  { id: 'library', label: 'Library', shortcut: 5 },
  { id: 'downloads', label: 'Downloads', shortcut: 6 },
  { id: 'settings', label: 'Settings', shortcut: 7 },
  { id: 'admin', label: 'Admin', shortcut: 8 },
];

const MAIN_TABS = TABS.filter(t => t.id !== 'downloads');
const DOWNLOADS_TAB = TABS.find(t => t.id === 'downloads')!;

function Separator() {
  return <div className="w-px h-5 bg-white/10 mx-1.5" />;
}

function AvatarCircle({ name, color }: { name: string; color?: string }) {
  const initial = name.charAt(0).toUpperCase() || '?';
  const bg = color || '#444';
  return (
    <div
      className="w-[30px] h-[30px] rounded-full ring-2 ring-white/20 flex items-center justify-center text-white text-[13px] font-semibold select-none flex-shrink-0"
      style={{ backgroundColor: bg }}
    >
      {initial}
    </div>
  );
}

interface PillNavBarProps {
  activeTab: Tab;
  onTabChange: (tab: Tab) => void;
  onSearchTap: () => void;
}

export function PillNavBar({ activeTab, onTabChange, onSearchTap }: PillNavBarProps) {
  const { currentProfile, selectProfile, signOut } = useAuth();
  const [accountOpen, setAccountOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!isDesktop()) return;
    const handler = (e: KeyboardEvent) => {
      if (e.ctrlKey || e.metaKey) {
        const tab = TABS.find(t => t.shortcut === Number(e.key));
        if (tab) {
          e.preventDefault();
          onTabChange(tab.id);
        }
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onTabChange]);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setAccountOpen(false);
      }
    }
    if (accountOpen) {
      document.addEventListener('mousedown', handleClick);
      return () => document.removeEventListener('mousedown', handleClick);
    }
  }, [accountOpen]);

  return (
    <div className="fixed top-4 left-1/2 -translate-x-1/2 z-50 glass-liquid-capsule px-2 py-2">
      <div className="flex items-center">
        <span className="font-brand text-[14px] tracking-[2px] text-white px-3 select-none">
          MOONLIT
        </span>

        <Separator />

        <nav className="flex items-center gap-0.5">
          {MAIN_TABS.map(tab => (
            <motion.button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className={`relative px-[13px] py-1.5 text-[12.5px] font-semibold rounded-full transition-colors
                ${activeTab === tab.id ? 'text-white' : 'text-white/65 hover:text-white'}`}
            >
              {activeTab === tab.id && (
                <motion.div
                  layoutId="navPill"
                  className="absolute inset-0 bg-white/10 rounded-full border border-white/[0.12]"
                  transition={SPRING.nav}
                />
              )}
              <span className="relative z-10">{tab.label}</span>
            </motion.button>
          ))}
        </nav>

        <Separator />

        <motion.button
          onClick={() => onTabChange('downloads')}
          className={`flex items-center justify-center rounded-full transition-colors
            ${activeTab === 'downloads' ? 'text-white bg-white/10' : 'text-white/60 hover:text-white'}`}
          style={{ width: 34, height: 34 }}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10" />
            <path d="M8 12l4 4 4-4" />
            <path d="M12 8v8" />
          </svg>
        </motion.button>

        <Separator />

        <motion.button
          whileHover={{ width: 'auto' }}
          className="glass-capsule px-3 py-1.5 flex items-center gap-2 h-7 overflow-hidden"
          style={{ width: 30 }}
          onClick={onSearchTap}
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-white/60 flex-shrink-0">
            <circle cx="11" cy="11" r="8" />
            <path d="M21 21l-4.35-4.35" />
          </svg>
          <span className="text-[12.5px] text-white/60 font-medium whitespace-nowrap">Search</span>
        </motion.button>

        <Separator />

        {currentProfile && (
          <div className="relative" ref={menuRef}>
            <button
              onClick={() => setAccountOpen(!accountOpen)}
              className="flex items-center justify-center"
            >
              <AvatarCircle
                name={currentProfile.name}
                color={currentProfile.avatar_color}
              />
            </button>

            {accountOpen && (
              <div className="absolute top-full right-0 mt-2 w-48 glass-dark-card py-1.5 z-50">
                <div className="px-3 py-1.5 text-[12px] font-semibold text-white/70 border-b border-white/10 mb-1">
                  {currentProfile.name}
                </div>
                <button
                  onClick={() => { setAccountOpen(false); onTabChange('settings'); }}
                  className="w-full text-left px-3 py-1.5 text-[13px] text-white/80 hover:bg-white/10 hover:text-white"
                >
                  Settings
                </button>
                <button
                  onClick={() => { setAccountOpen(false); selectProfile(null as any); }}
                  className="w-full text-left px-3 py-1.5 text-[13px] text-white/80 hover:bg-white/10 hover:text-white"
                >
                  Switch Profile
                </button>
                <button
                  onClick={() => { setAccountOpen(false); signOut(); }}
                  className="w-full text-left px-3 py-1.5 text-[13px] text-red-400 hover:bg-white/10"
                >
                  Sign Out
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
