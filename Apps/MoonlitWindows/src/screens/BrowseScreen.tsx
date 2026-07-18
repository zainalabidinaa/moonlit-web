import { useState, useMemo, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import { useNavigate } from '@/shell/Shell';
import { loadCollections } from '@/lib/collections/repository';
import { fetchTMDBDiscover, availableGenres } from '@/lib/design/tmdb-genres';
import { useAmbientColors } from '@/lib/design/artwork-color';
import type { MetaPreview, CatalogRow } from '@/lib/types';

import HomeHero from '@/components/HomeHero';
import PosterCard from '@/components/PosterCard';
import MediaCard from '@/components/MediaCard';
import LoadingView from '@/components/LoadingView';
import ErrorState from '@/components/ErrorState';

const MAIN_ROW_NAMES = new Set([
  'Popular Movies', 'Popular TV Shows',
  'Trending Movies', 'Trending TV Shows',
  'Popular Shows', 'Trending Shows',
  'Latest', 'Top Rated',
]);

function getTmdbApiKey(): string {
  try { return localStorage.getItem('moonlit.tmdbKey') || ''; } catch { return ''; }
}

const GENRE_FETCHES = [
  { title: 'Trending', sortBy: 'popularity.desc', subtitle: "WHAT'S HOT RIGHT NOW" },
  { title: 'Top Rated', sortBy: 'vote_average.desc', subtitle: 'ALL-TIME BESTS' },
  { title: 'New Releases', sortBy: 'primary_release_date.desc', subtitle: 'RECENTLY ADDED' },
];

export function BrowseScreen({ mediaKind }: { mediaKind: 'movie' | 'series' }) {
  const navigate = useNavigate();
  const { currentProfile, addons } = useAuth();
  const [selectedGenre, setSelectedGenre] = useState<string | null>(null);
  const [popoverOpen, setPopoverOpen] = useState(false);

  const tmdbApiKey = getTmdbApiKey();
  const profileId = currentProfile?.id;
  const browseNoun = mediaKind === 'movie' ? 'Movies' : 'Series';

  const { data: catalogRows = [], isLoading, error } = useQuery({
    queryKey: ['browse-collections', mediaKind, profileId, addons.length],
    queryFn: () => loadCollections(addons, tmdbApiKey),
    enabled: addons.length > 0,
    staleTime: 10 * 60 * 1000,
  });

  const featuredItems = useMemo(() => {
    const allRows = catalogRows;
    const heroRows = allRows.filter(r => MAIN_ROW_NAMES.has(r.title));
    const source = heroRows.length > 0 ? heroRows : allRows;

    const seen = new Set<string>();
    const candidates: MetaPreview[] = [];
    for (const row of source) {
      let taken = 0;
      const filtered = row.items.filter(item => {
        if (item.id.startsWith('folder_')) return false;
        if (mediaKind === 'movie') return item.type === 'movie' || (item.id?.startsWith('tt') && !item.id?.includes(':'));
        return item.type === 'series' || item.id?.includes(':series:') || item.id?.includes('series:');
      });
      const sorted = [...filtered].sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0));
      for (const item of sorted) {
        if (seen.has(item.id)) continue;
        if (taken >= 8 || candidates.length >= 20) break;
        seen.add(item.id);
        candidates.push(item);
        taken++;
      }
    }
    return candidates;
  }, [catalogRows, mediaKind]);

  const portalRows = useMemo(() => {
    if (selectedGenre) return [];
    return catalogRows.filter(row => {
      if (row.isGroupTile) return true;
      return row.items.some(item => {
        if (item.id.startsWith('folder_')) return true;
        if (mediaKind === 'movie') return item.type === 'movie' || (item.id?.startsWith('tt') && !item.id?.includes(':'));
        return item.type === 'series' || item.id?.includes(':series:') || item.id?.includes('series:');
      });
    });
  }, [catalogRows, selectedGenre, mediaKind]);

  const genres = useMemo(() => availableGenres(mediaKind), [mediaKind]);

  const { data: genreRails = [], isLoading: railsLoading } = useQuery({
    queryKey: ['browse-genre-rails', mediaKind, selectedGenre],
    queryFn: async () => {
      if (!selectedGenre || !tmdbApiKey) return [];
      const results = await Promise.all(
        GENRE_FETCHES.map(async (fetch) => {
          const data = await fetchTMDBDiscover(mediaKind, selectedGenre, fetch.sortBy, tmdbApiKey);
          return {
            title: `${fetch.title} ${browseNoun}`,
            subtitle: fetch.subtitle,
            items: data.items,
          };
        })
      );
      return results.filter(r => r.items.length > 0);
    },
    enabled: !!selectedGenre && !!tmdbApiKey,
    staleTime: 5 * 60 * 1000,
  });

  const heroBackdrop = featuredItems[0]?.background ?? featuredItems[0]?.poster;
  const ambient = useAmbientColors(heroBackdrop);

  const handleGenreSelect = useCallback((genre: string | null) => {
    setSelectedGenre(genre);
    setPopoverOpen(false);
  }, []);

  if (isLoading && catalogRows.length === 0) {
    return <LoadingView />;
  }

  if (error) {
    return <ErrorState title="Failed to load browse" message={(error as Error).message} onRetry={() => window.location.reload()} />;
  }

  return (
    <div className="min-h-screen bg-moonlit-bg">
      {ambient && (
        <>
          <div
            className="fixed inset-0 pointer-events-none z-0"
            style={{
              background: `radial-gradient(ellipse at 50% 0%, ${ambient[0]} 0%, ${ambient[0]}22 40%, transparent 90%)`,
              opacity: 0.30,
            }}
          />
          <div
            className="fixed inset-0 pointer-events-none z-0"
            style={{
              background: `radial-gradient(ellipse at 75% 10%, ${ambient[1]} 0%, transparent 55%)`,
              opacity: 0.22,
            }}
          />
        </>
      )}

      <div className="relative z-10">
        {featuredItems.length > 0 && (
          <HomeHero
            items={featuredItems}
            onPlay={(item) => {
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
            onDetail={(item) => navigate.navigateTo(item.type, item.id)}
          />
        )}

        <div className="mt-[14px] px-[32px] flex items-center gap-[12px]">
          <span className="text-[20px] font-bold text-white">Browse {browseNoun}</span>
          <div className="relative">
            <button
              type="button"
              className="flex items-center gap-[6px] text-[13px] font-semibold text-white/80 px-[14px] py-[7px] glass-dark-capsule"
              onClick={() => setPopoverOpen((v) => !v)}
            >
              {selectedGenre || 'All'}
              <svg width="9" height="9" viewBox="0 0 9 9" className="text-white/80" fill="none">
                <path d="M1.5 3L4.5 6L7.5 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
            </button>
            {popoverOpen && (
              <div className="absolute top-full left-0 mt-2 z-50">
                <div
                  className="p-[14px] rounded-ml-lg"
                  style={{
                    width: 380,
                    background: 'rgba(18,18,18,0.95)',
                    backdropFilter: 'blur(40px)',
                    border: '0.8px solid rgba(255,255,255,0.12)',
                  }}
                >
                  <div className="grid grid-cols-4 gap-[5px]">
                    <button
                      type="button"
                      className="text-[12px] font-semibold px-0 py-[8px] rounded-[7px] text-center transition-colors"
                      style={{
                        background: !selectedGenre ? '#D4AF37' : 'rgba(255,255,255,0.06)',
                        color: !selectedGenre ? '#000' : 'rgba(255,255,255,0.85)',
                      }}
                      onClick={() => handleGenreSelect(null)}
                    >
                      All
                    </button>
                    {genres.map((genre) => (
                      <button
                        key={genre}
                        type="button"
                        className="text-[12px] font-medium px-0 py-[8px] rounded-[7px] text-center transition-colors"
                        style={{
                          background: selectedGenre === genre ? '#D4AF37' : 'rgba(255,255,255,0.06)',
                          color: selectedGenre === genre ? '#000' : 'rgba(255,255,255,0.85)',
                          fontWeight: selectedGenre === genre ? 600 : 500,
                        }}
                        onClick={() => handleGenreSelect(genre)}
                      >
                        {genre}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>

        {!selectedGenre && portalRows.map((row) => {
          const isFolderTile = row.items[0]?.id.startsWith('folder_');

          if (isFolderTile) {
            return (
              <div key={row.id} className="mt-[48px]">
                <div className="px-[32px] mb-[16px] flex flex-col gap-[6px]">
                  <h2 className="text-[24px] font-bold text-white">{row.title}</h2>
                  <span className="text-[13px] font-bold text-white/30 tracking-[6px]">COLLECTIONS</span>
                </div>
                <div className="overflow-x-auto scrollbar-hide">
                  <div className="flex gap-[16px] px-[32px] py-[10px]">
                    {row.items.map((item) => (
                      <MediaCard
                        key={item.id}
                        item={item}
                        row={row}
                        width={220}
                        height={124}
                        onClick={() => {
                          const fid = item.id.startsWith('folder_') ? item.id.replace('folder_', '') : item.id;
                          navigate.navigateToFolder(`folder_${fid}`, fid, item.name);
                        }}
                      />
                    ))}
                  </div>
                </div>
              </div>
            );
          }

          return (
            <div key={row.id} className="mt-[48px]">
              <div className="px-[32px] mb-[16px] flex flex-col gap-[6px]">
                <h2 className="text-[24px] font-bold text-white">{row.title}</h2>
                <span className="text-[13px] font-bold text-white/30 tracking-[6px]">
                  {row.title.includes('Popular') || row.title.includes('Trending') ? "WHAT'S HOT RIGHT NOW"
                    : row.title.includes('Top Rated') ? 'ALL-TIME BESTS'
                    : 'SPOTLIGHT'}
                </span>
              </div>
              <div className="overflow-x-auto scrollbar-hide">
                <div className="flex gap-[22px] px-[32px] py-[10px]">
                  {row.items.map((item) => (
                    <PosterCard
                      key={item.id}
                      item={item}
                      onClick={() => navigate.navigateTo(item.type, item.id)}
                    />
                  ))}
                </div>
              </div>
            </div>
          );
        })}

        {railsLoading && (
          <div className="flex justify-center mt-[60px]">
            <LoadingView />
          </div>
        )}

        {!railsLoading && genreRails.map((rail) => (
          <div key={rail.title} className="mt-[48px]">
            <div className="px-[32px] mb-[16px] flex flex-col gap-[6px]">
              <h2 className="text-[24px] font-bold text-white">{rail.title}</h2>
              <span className="text-[13px] font-bold text-white/30 tracking-[6px]">{rail.subtitle}</span>
            </div>
            <div className="overflow-x-auto scrollbar-hide">
              <div className="flex gap-[22px] px-[32px] py-[10px]">
                {rail.items.map((item) => (
                  <PosterCard
                    key={item.id}
                    item={item}
                    onClick={() => navigate.navigateTo(item.type, item.id)}
                  />
                ))}
              </div>
            </div>
          </div>
        ))}

        {selectedGenre && !railsLoading && genreRails.length === 0 && (
          <div className="text-center mt-[60px] text-[15px] font-semibold text-white/50">
            Nothing found for {selectedGenre}
          </div>
        )}

        <div className="h-12" />
      </div>
    </div>
  );
}
