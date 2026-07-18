import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import { useNavigate } from '@/shell/Shell';
import { loadCollections } from '@/lib/collections/repository';
import { getWatchProgress } from '@/lib/services/api';
import type { MetaPreview, CatalogRow } from '@/lib/types';
import { useAmbientColors } from '@/lib/design/artwork-color';

import HomeHero from '@/components/HomeHero';
import CategoryPills from '@/components/CategoryPills';
import ContinueWatchingCard from '@/components/ContinueWatchingCard';
import GenreTile from '@/components/GenreTile';
import LanguageTile from '@/components/LanguageTile';
import MediaRow from '@/components/MediaRow';
import LoadingView from '@/components/LoadingView';
import ErrorState from '@/components/ErrorState';

type HomeCategory = 'featured' | 'movies' | 'series';

const HOME_CATEGORIES = [
  { id: 'featured', label: 'Featured' },
  { id: 'movies', label: 'Movies' },
  { id: 'series', label: 'Series' },
];

const HOME_GENRES: string[] = [
  'Action', 'Adventure', 'Thriller', 'Crime', 'Drama',
  'Romance', 'Mystery', 'Sci-Fi', 'Fantasy', 'Horror',
  'Comedy', 'Family', 'Animation', 'Western', 'War',
  'History', 'Documentary', 'Music',
];

const HOME_LANGUAGES: { iso: string; name: string; endonym: string; hue: number }[] = [
  { iso: 'ko', name: 'Korean', endonym: '\uD55C\uAD6D\uC5B4', hue: 25 },
  { iso: 'ja', name: 'Japanese', endonym: '\u65E5\u672C\u8A9E', hue: 350 },
  { iso: 'es', name: 'Spanish', endonym: 'Espa\u00F1ol', hue: 60 },
  { iso: 'fr', name: 'French', endonym: 'Fran\u00E7ais', hue: 260 },
  { iso: 'zh', name: 'Chinese', endonym: '\u4E2D\u6587', hue: 10 },
  { iso: 'hi', name: 'Indian', endonym: '\u0939\u093F\u0928\u094D\u0926\u0940', hue: 300 },
  { iso: 'de', name: 'German', endonym: 'Deutsch', hue: 40 },
  { iso: 'it', name: 'Italian', endonym: 'Italiano', hue: 145 },
  { iso: 'pt', name: 'Portuguese', endonym: 'Portugu\u00EAs', hue: 130 },
  { iso: 'tr', name: 'Turkish', endonym: 'T\u00FCrk\u00E7e', hue: 200 },
  { iso: 'sv', name: 'Swedish', endonym: 'Svenska', hue: 230 },
  { iso: 'da', name: 'Danish', endonym: 'Dansk', hue: 0 },
  { iso: 'no', name: 'Norwegian', endonym: 'Norsk', hue: 250 },
  { iso: 'ru', name: 'Russian', endonym: '\u0420\u0443\u0441\u0441\u043A\u0438\u0439', hue: 340 },
  { iso: 'pl', name: 'Polish', endonym: 'Polski', hue: 170 },
  { iso: 'th', name: 'Thai', endonym: '\u0E44\u0E17\u0E22', hue: 320 },
  { iso: 'nl', name: 'Dutch', endonym: 'Nederlands', hue: 80 },
  { iso: 'ar', name: 'Arabic', endonym: '\u0627\u0644\u0639\u0631\u0628\u064A\u0629', hue: 165 },
];

const MAIN_ROW_NAMES = new Set([
  'Popular Movies', 'Popular TV Shows',
  'Trending Movies', 'Trending TV Shows',
  'Popular Shows', 'Trending Shows',
  'Latest', 'Top Rated',
]);

function getTmdbApiKey(): string {
  try { return localStorage.getItem('moonlit.tmdbKey') || ''; } catch { return ''; }
}

function getRowStyle(rowTitle: string): 'standard' | 'heroBanner' | 'cardStack' | 'cinematic' | 'topTen' {
  try {
    const raw = localStorage.getItem('moonlit.collectionRowStyles');
    if (raw) {
      const store = JSON.parse(raw);
      if (store[rowTitle]) return store[rowTitle];
    }
  } catch {}
  return 'standard';
}

function isMovie(item: MetaPreview): boolean {
  return item.type === 'movie' || (item.id?.startsWith('tt') && !item.id?.includes(':'));
}

function isSeries(item: MetaPreview): boolean {
  return item.type === 'series' || item.id?.includes(':series:') || item.id?.includes('series:') || false;
}

function itemMatchesCategory(item: MetaPreview, category: HomeCategory): boolean {
  if (category === 'featured') return true;
  if (category === 'movies') return isMovie(item);
  return isSeries(item);
}

export function HomeScreen() {
  const navigate = useNavigate();
  const { currentProfile, addons } = useAuth();
  const [category, setCategory] = useState<HomeCategory>('featured');

  const profileId = currentProfile?.id;
  const tmdbApiKey = getTmdbApiKey();

  const { data: catalogRows = [], isLoading: rowsLoading, error: rowsError } = useQuery({
    queryKey: ['home-collections', profileId, addons.length],
    queryFn: () => loadCollections(addons, tmdbApiKey),
    enabled: addons.length > 0,
    staleTime: 10 * 60 * 1000,
  });

  const { data: watchProgress = [] } = useQuery({
    queryKey: ['watch-progress', profileId],
    queryFn: () => getWatchProgress(profileId!),
    enabled: !!profileId,
    staleTime: 2 * 60 * 1000,
  });

  const featuredItems = useMemo(() => {
    const heroRows = catalogRows.filter(r => MAIN_ROW_NAMES.has(r.title));
    const source = heroRows.length > 0 ? heroRows : catalogRows;

    const seen = new Set<string>();
    const candidates: MetaPreview[] = [];
    for (const row of source) {
      let taken = 0;
      const sorted = [...row.items].sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0));
      for (const item of sorted) {
        if (seen.has(item.id)) continue;
        if (!itemMatchesCategory(item, category)) continue;
        if (taken >= 8 || candidates.length >= 20) break;
        seen.add(item.id);
        candidates.push(item);
        taken++;
      }
    }
    return candidates;
  }, [catalogRows, category]);

  const visibleRows = useMemo(() => {
    const filtered = catalogRows.filter(row => {
      if (category === 'featured') return true;
      return row.items.some(item => itemMatchesCategory(item, category));
    });
    return filtered;
  }, [catalogRows, category]);

  const continueWatchingItems = useMemo(() => {
    const inProgress = watchProgress
      .filter(w => !w.completed && w.position_seconds > 0)
      .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
      .slice(0, 20);
    return inProgress;
  }, [watchProgress]);

  const heroBackdrop = featuredItems[0]?.background ?? featuredItems[0]?.poster;
  const ambient = useAmbientColors(heroBackdrop);

  if (rowsLoading && catalogRows.length === 0) {
    return <LoadingView />;
  }

  if (rowsError) {
    return <ErrorState title="Failed to load" message={(rowsError as Error).message} onRetry={() => window.location.reload()} />;
  }

  return (
    <div className="min-h-screen bg-moonlit-bg" style={{ paddingTop: 0 }}>
      {ambient && (
        <>
          <div
            className="fixed inset-0 pointer-events-none z-0"
            style={{
              background: `radial-gradient(ellipse at 50% 0%, ${ambient[0]} 0%, ${ambient[0]}22 40%, transparent 90%)`,
              opacity: 0.45,
            }}
          />
          <div
            className="fixed inset-0 pointer-events-none z-0"
            style={{
              background: `radial-gradient(ellipse at 75% 10%, ${ambient[1]} 0%, transparent 55%)`,
              opacity: 0.30,
            }}
          />
        </>
      )}

      <div className="relative z-10">
        {featuredItems.length > 0 && (
          <HomeHero
            items={featuredItems}
            onPlay={(item) => {
              if (item.id.startsWith('folder_')) return;
              navigate.startPlayback({
                type: item.type,
                id: item.id,
                metadata: {
                  mediaId: item.id,
                  mediaType: item.type,
                  title: item.name,
                  poster: item.poster,
                  background: item.background,
                  logo: item.logo,
                },
              });
            }}
            onDetail={(item) => {
              if (item.id.startsWith('folder_')) {
                const folderId = item.id.replace('folder_', '');
                navigate.navigateToFolder(item.id, folderId, item.name);
              } else {
                navigate.navigateTo(item.type, item.id);
              }
            }}
          />
        )}

        <div className="mt-[14px] px-[32px]">
          <CategoryPills
            categories={HOME_CATEGORIES}
            selected={category}
            onSelect={(id) => setCategory(id as HomeCategory)}
          />
        </div>

        {continueWatchingItems.length > 0 && (
          <div className="mt-[26px] mb-[38px]">
            <div className="px-[32px] mb-[12px]">
              <h2 className="text-[21px] font-bold text-white">Continue Watching</h2>
            </div>
            <div className="overflow-x-auto scrollbar-hide">
              <div className="flex gap-[14px] px-[32px] py-[6px]">
                {continueWatchingItems.map((item) => {
                  const durationMs = item.duration_seconds > 0 ? item.duration_seconds * 1000 : 1;
                  const progressFraction = item.duration_seconds > 0
                    ? item.position_seconds / item.duration_seconds
                    : 0;

                  return (
                    <ContinueWatchingCard
                      key={item.id}
                      item={{
                        id: item.id,
                        name: item.name || 'Unknown',
                        poster: item.poster,
                        durationMs,
                        progressFraction,
                      }}
                      onClick={() => {
                        const decodedId = decodeURIComponent(item.media_id);
                        const lastStream = (() => {
                          try {
                            const ls = localStorage.getItem(`moonlit.lastPlaybackSource.${decodedId}`);
                            if (ls) return JSON.parse(ls);
                          } catch {}
                          return null;
                        })();

                        if (lastStream?.url) {
                          navigate.startPlayback({
                            type: item.media_type,
                            id: decodedId,
                            streamUrl: lastStream.url,
                            metadata: {
                              mediaId: decodedId,
                              mediaType: item.media_type,
                              title: item.name || 'Unknown',
                              poster: item.poster,
                            },
                            startPosition: item.position_seconds * 1000,
                          });
                        } else {
                          navigate.navigateTo(item.media_type, decodedId);
                        }
                      }}
                      onMarkWatched={() => {}}
                      onRemove={() => {}}
                    />
                  );
                })}
              </div>
            </div>
          </div>
        )}

        <div className="mt-[20px] mb-[24px]">
          <div className="px-[32px] mb-[16px]">
            <h2 className="text-[22px] font-bold text-white">Browse by Genre</h2>
          </div>
          <div className="overflow-x-auto scrollbar-hide">
            <div className="flex gap-[20px] px-[32px] py-[6px]">
              {HOME_GENRES.map((genre) => (
                <GenreTile
                  key={genre}
                  name={genre}
                  onClick={() => navigate.navigateToGenre(genre, 'movie')}
                />
              ))}
            </div>
          </div>
        </div>

        <div className="mb-[36px]">
          <div className="px-[32px] mb-[16px]">
            <h2 className="text-[22px] font-bold text-white">Browse by Language</h2>
          </div>
          <div className="overflow-x-auto scrollbar-hide">
            <div className="flex gap-[20px] px-[32px] py-[6px]">
              {HOME_LANGUAGES.map((lang) => (
                <LanguageTile
                  key={lang.iso}
                  iso={lang.iso}
                  name={lang.name}
                  endonym={lang.endonym}
                  hue={lang.hue}
                  onClick={() => navigate.navigateToLanguage(lang.iso, lang.name)}
                />
              ))}
            </div>
          </div>
        </div>

        {visibleRows.length > 0 && (
          <div className="flex flex-col gap-[44px] pb-16">
            {visibleRows.map((row) => (
              <MediaRow
                key={row.id}
                title={row.title}
                items={row.items.slice(0, 20)}
                layout={getRowStyle(row.title)}
                onItemClick={(item) => {
                  if (item.id.startsWith('folder_')) {
                    const folderId = item.id.replace('folder_', '');
                    navigate.navigateToFolder(item.id, folderId, item.name);
                  } else {
                    navigate.navigateTo(item.type, item.id);
                  }
                }}
                onShowMore={row.items.length > 20 ? () => navigate.navigateToFolder(row.id, row.id, row.title) : undefined}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
