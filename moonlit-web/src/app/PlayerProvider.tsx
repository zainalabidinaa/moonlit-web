/* eslint-disable react-refresh/only-export-components */
import { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import { StreamItem } from '@/lib/types';
import {
  normalizePlayerLaunch,
  type NormalizedPlayerLaunch,
  type PlayerLaunch,
} from '@/lib/player/contracts';

export type { PlayerLaunch, PlayerMetadata } from '@/lib/player/contracts';

interface PlayerContextType {
  isOpen: boolean;
  launch: NormalizedPlayerLaunch | null;
  open: (launch: PlayerLaunch) => void;
  close: () => void;
  activeStream: StreamItem | null;
  allStreams: StreamItem[];
  setActiveStream: (s: StreamItem) => void;
  setAllStreams: (s: StreamItem[]) => void;
  switchStream: (s: StreamItem) => void;
  onStreamSwitch: ((s: StreamItem) => void) | null;
  registerStreamSwitchHandler: (fn: (s: StreamItem) => void) => () => void;
}

const PlayerContext = createContext<PlayerContextType | null>(null);

export function PlayerProvider({ children }: { children: ReactNode }) {
  const [isOpen, setIsOpen] = useState(false);
  const [launch, setLaunch] = useState<NormalizedPlayerLaunch | null>(null);
  const [activeStream, setActiveStream] = useState<StreamItem | null>(null);
  const [allStreams, setAllStreams] = useState<StreamItem[]>([]);
  const [onStreamSwitch, setOnStreamSwitch] = useState<((s: StreamItem) => void) | null>(null);

  const open = useCallback((l: PlayerLaunch) => {
    const normalized = normalizePlayerLaunch(l);
    const matchingStream = normalized.streamUrl
      ? normalized.streams?.find(stream => stream.url === normalized.streamUrl || stream.externalUrl === normalized.streamUrl)
      : undefined;
    setLaunch(normalized);
    setActiveStream(matchingStream ?? (normalized.streamUrl ? { url: normalized.streamUrl, addonName: 'Direct' } : null));
    setAllStreams(normalized.streams ?? []);
    setIsOpen(true);
    // Push history state so browser back dismisses the player
    try {
      window.history.pushState({ playerOpen: true }, '', `#player-${l.type}-${l.id}`);
    } catch { /* History updates are best effort in restricted browser contexts. */ }
  }, []);

  const close = useCallback(() => {
    setIsOpen(false);
    setLaunch(null);
    setActiveStream(null);
    setAllStreams([]);
    // Pop the history state if we pushed one
    if (window.location.hash.startsWith('#player-')) {
      try { window.history.back(); } catch { /* History updates are best effort in restricted browser contexts. */ }
    }
  }, []);

  const registerStreamSwitchHandler = useCallback((fn: (s: StreamItem) => void) => {
    setOnStreamSwitch(() => fn);
    return () => setOnStreamSwitch((current: ((stream: StreamItem) => void) | null) => (
      current === fn ? null : current
    ));
  }, []);

  const switchStream = useCallback((s: StreamItem) => {
    setActiveStream(s);
    if (onStreamSwitch) onStreamSwitch(s);
  }, [onStreamSwitch]);

  // Listen for browser back button to dismiss player
  useEffect(() => {
    const handler = () => {
      if (isOpen) close();
    };
    window.addEventListener('popstate', handler);
    return () => window.removeEventListener('popstate', handler);
  }, [isOpen, close]);

  return (
    <PlayerContext.Provider value={{
      isOpen, launch, open, close,
      activeStream, allStreams,
      setActiveStream, setAllStreams,
      switchStream, onStreamSwitch,
      registerStreamSwitchHandler,
    }}>
      {children}
    </PlayerContext.Provider>
  );
}

export function usePlayer() {
  const ctx = useContext(PlayerContext);
  if (!ctx) throw new Error('usePlayer must be used within PlayerProvider');
  return ctx;
}
