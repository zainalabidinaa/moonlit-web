import { createContext, useContext, useState, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { usePlayer } from '@/app/PlayerProvider';
import type { PlayerLaunch } from '@/app/PlayerProvider';
import { PillNavBar } from './PillNavBar';
import { BackButton } from './BackButton';

import { HomeScreen } from '@/screens/HomeScreen';
import { BrowseScreen } from '@/screens/BrowseScreen';
import { LiveTVScreen } from '@/screens/LiveTVScreen';
import { LibraryScreen } from '@/screens/LibraryScreen';
import { DownloadsScreen } from '@/screens/DownloadsScreen';
import { SettingsScreen } from '@/screens/SettingsScreen';
import { AdminScreen } from '@/screens/AdminScreen';
import { SearchScreen } from '@/screens/SearchScreen';
import { PlayerScreen } from '@/screens/PlayerScreen';
import { DetailScreen } from '@/screens/DetailScreen';
import { GenreHubScreen } from '@/screens/GenreHubScreen';
import { LanguageHubScreen } from '@/screens/LanguageHubScreen';
import { ActorBioScreen } from '@/screens/ActorBioScreen';
import { FolderScreen } from '@/screens/FolderScreen';
import { StreamingServiceScreen } from '@/screens/StreamingServiceScreen';
import { AwardHubScreen } from '@/screens/AwardHubScreen';

export type Tab = 'home' | 'movies' | 'series' | 'live' | 'library' | 'downloads' | 'settings' | 'admin';

interface DetailItem { type: string; id: string }
interface GenreHubItem { genre: string; mediaKind: 'movie' | 'series' }
interface LanguageHubItem { iso: string; name: string }
interface ActorItem { id: string; name: string }
interface FolderItem { rowId: string; folderId: string; name: string }
interface StreamingServiceItem { rowId: string; name: string }
interface AwardHubItem { awardId: string }

type OverlayKind = 'actorBio' | 'streamingService' | 'folder' | 'detail' | 'genreHub' | 'languageHub' | 'awardHub' | null;

interface NavigateContextType {
  navigateTo: (type: string, id: string) => void;
  navigateToGenre: (genre: string, mediaKind: 'movie' | 'series') => void;
  navigateToLanguage: (iso: string, name: string) => void;
  navigateToActor: (id: string, name: string) => void;
  navigateToFolder: (rowId: string, folderId: string, name: string) => void;
  navigateToStreamingService: (rowId: string, name: string) => void;
  navigateToAward: (awardId: string) => void;
  startPlayback: (launch: PlayerLaunch) => void;
  openSearch: () => void;
  openSettings: () => void;
  dismissOverlay: () => void;
}

const NavigateContext = createContext<NavigateContextType | null>(null);

export function useNavigate() {
  const ctx = useContext(NavigateContext);
  if (!ctx) throw new Error('useNavigate must be used within Shell');
  return ctx;
}

export function Shell() {
  const { open: playerOpenFn, launch: playerLaunchVal, close: closePlayer } = usePlayer();

  const [activeTab, setActiveTab] = useState<Tab>('home');
  const [searchOpen, setSearchOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [actorItem, setActorItem] = useState<ActorItem | null>(null);
  const [streamingService, setStreamingService] = useState<StreamingServiceItem | null>(null);
  const [folderItem, setFolderItem] = useState<FolderItem | null>(null);
  const [detailItem, setDetailItem] = useState<DetailItem | null>(null);
  const [genreHub, setGenreHub] = useState<GenreHubItem | null>(null);
  const [languageHub, setLanguageHub] = useState<LanguageHubItem | null>(null);
  const [awardHub, setAwardHub] = useState<AwardHubItem | null>(null);

  const currentOverlay: OverlayKind =
    actorItem ? 'actorBio'
    : streamingService ? 'streamingService'
    : folderItem ? 'folder'
    : detailItem ? 'detail'
    : genreHub ? 'genreHub'
    : languageHub ? 'languageHub'
    : awardHub ? 'awardHub'
    : null;

  const isShowingOverlay = currentOverlay !== null;

  const dismissOverlay = useCallback(() => {
    setActorItem(null);
    setStreamingService(null);
    setFolderItem(null);
    setDetailItem(null);
    setGenreHub(null);
    setLanguageHub(null);
    setAwardHub(null);
  }, []);

  const dismissTopmost = useCallback(() => {
    if (actorItem) { setActorItem(null); return; }
    if (streamingService) { setStreamingService(null); return; }
    if (folderItem) { setFolderItem(null); return; }
    if (detailItem) { setDetailItem(null); return; }
    if (genreHub) { setGenreHub(null); return; }
    if (languageHub) { setLanguageHub(null); return; }
    if (awardHub) { setAwardHub(null); return; }
  }, [actorItem, streamingService, folderItem, detailItem, genreHub, languageHub, awardHub]);

  const handleTabChange = useCallback((tab: Tab) => {
    setActiveTab(tab);
    dismissOverlay();
    setSearchOpen(false);
    setSettingsOpen(false);
  }, [dismissOverlay]);

  const navigate: NavigateContextType = {
    navigateTo: (_type, _id) => { dismissOverlay(); setDetailItem({ type: _type, id: _id }); },
    navigateToGenre: (genre, mediaKind) => { dismissOverlay(); setGenreHub({ genre, mediaKind }); },
    navigateToLanguage: (iso, name) => { dismissOverlay(); setLanguageHub({ iso, name }); },
    navigateToActor: (id, name) => { setActorItem({ id, name }); },
    navigateToFolder: (rowId, folderId, name) => { setFolderItem({ rowId, folderId, name }); },
    navigateToStreamingService: (rowId, name) => { setStreamingService({ rowId, name }); },
    navigateToAward: (awardId) => { setAwardHub({ awardId }); },
    startPlayback: (launch) => { playerOpenFn(launch); },
    openSearch: () => { setSearchOpen(true); },
    openSettings: () => { setSettingsOpen(true); },
    dismissOverlay,
  };

  const playerOpen = playerLaunchVal !== null;

  return (
    <NavigateContext.Provider value={navigate}>
      <div className="min-h-screen bg-moonlit-bg">
        {!(searchOpen || settingsOpen) && (
          <PillNavBar
            activeTab={activeTab}
            onTabChange={handleTabChange}
            onSearchTap={() => setSearchOpen(true)}
          />
        )}

        <AnimatePresence mode="wait">
          {!isShowingOverlay && !searchOpen && !settingsOpen && !playerOpen && (
            <motion.div
              key={activeTab}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.15 }}
            >
              {activeTab === 'home' && <HomeScreen />}
              {activeTab === 'movies' && <BrowseScreen mediaKind="movie" />}
              {activeTab === 'series' && <BrowseScreen mediaKind="series" />}
              {activeTab === 'live' && <LiveTVScreen />}
              {activeTab === 'library' && <LibraryScreen />}
              {activeTab === 'downloads' && <DownloadsScreen />}
              {activeTab === 'settings' && <SettingsScreen />}
              {activeTab === 'admin' && <AdminScreen />}
            </motion.div>
          )}
        </AnimatePresence>

        {actorItem && <ActorBioScreen name={actorItem.name} />}
        {!actorItem && streamingService && <StreamingServiceScreen name={streamingService.name} />}
        {!actorItem && !streamingService && folderItem && <FolderScreen name={folderItem.name} />}
        {!actorItem && !streamingService && !folderItem && detailItem && (
          <DetailScreen type={detailItem.type} id={detailItem.id} />
        )}
        {!actorItem && !streamingService && !folderItem && !detailItem && genreHub && (
          <GenreHubScreen genre={genreHub.genre} mediaKind={genreHub.mediaKind} />
        )}
        {!actorItem && !streamingService && !folderItem && !detailItem && !genreHub && languageHub && (
          <LanguageHubScreen iso={languageHub.iso} name={languageHub.name} />
        )}
        {!actorItem && !streamingService && !folderItem && !detailItem && !genreHub && !languageHub && awardHub && (
          <AwardHubScreen awardId={awardHub.awardId} />
        )}

        {settingsOpen && <SettingsScreen />}
        {searchOpen && <SearchScreen onClose={() => setSearchOpen(false)} />}
        {playerOpen && playerLaunchVal && (
          <PlayerScreen launch={playerLaunchVal} onClose={() => closePlayer()} />
        )}

        {isShowingOverlay && (
          <BackButton onClick={dismissTopmost} />
        )}
      </div>
    </NavigateContext.Provider>
  );
}
