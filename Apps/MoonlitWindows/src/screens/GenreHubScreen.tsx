import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { Tag } from 'lucide-react';
import { useNavigate } from '@/shell/Shell';
import { genre as genrePalette } from '@/lib/design/oklch';
import { fetchTMDBDiscover } from '@/lib/design/tmdb-genres';
import PosterCard from '@/components/PosterCard';
import StrokeSpinner from '@/components/StrokeSpinner';
import LoadingView from '@/components/LoadingView';
import type { MetaPreview, CatalogRow } from '@/lib/types';

interface GenreHubScreenProps {
  genre: string;
  mediaKind: 'movie' | 'series';
}

const GENRE_DESCRIPTIONS: Record<string, string> = {
  action: 'The best action movies and series, layered by mood. Browse trending, dive into a director\'s run, sort by decade, find quiet gems.',
  horror: 'The best horror movies and series, from new nightmares to cult favorites and long-running franchises.',
  comedy: 'The best comedy movies and series, from comfort watches to sharp, chaotic crowd favorites.',
  drama: 'The best drama movies and series, from acclaimed essentials to emotional discoveries.',
  'sci-fi': 'The best sci-fi movies and series, from future worlds to strange experiments and cerebral classics.',
};

function normalize(s: string) {
  return s.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function genreDescription(genre: string) {
  const lower = genre.toLowerCase();
  const palette = GENRE_DESCRIPTIONS[normalize(genre)];
  if (palette) return palette;
  const key = Object.keys(GENRE_DESCRIPTIONS).find(k => normalize(k) === normalize(genre));
  if (key) return GENRE_DESCRIPTIONS[key];
  return `The best ${lower} movies and series, layered by mood. Browse trending, dive into collections, sort by era, find quiet gems.`;
}

interface BrowseRail {
  id: string;
  title: string;
  items: MetaPreview[];
}

type VoteFilter = 'any' | 'under100' | '100to500' | '500to1k' | 'over1k';

const VOTE_FILTERS: { key: VoteFilter; label: string }[] = [
  { key: 'any', label: 'Any' },
  { key: 'under100', label: '< 100' },
  { key: '100to500', label: '100-500' },
  { key: '500to1k', label: '500-1K' },
  { key: 'over1k', label: '1K+' },
];

function voteCount(item: MetaPreview): number {
  return (item as any).vote_count ?? (item as any).voteCount ?? 0;
}

function matchesVoteFilter(item: MetaPreview, filter: VoteFilter): boolean {
  const vc = voteCount(item);
  switch (filter) {
    case 'any': return true;
    case 'under100': return vc < 100;
    case '100to500': return vc >= 100 && vc <= 500;
    case '500to1k': return vc > 500 && vc <= 1000;
    case 'over1k': return vc > 1000;
  }
}

const TMDB_API_KEY_STORAGE_KEY = 'moonlit.tmdbApiKey';

function getTMDBKey(): string {
  try {
    return localStorage.getItem(TMDB_API_KEY_STORAGE_KEY) || '';
  } catch {
    return '';
  }
}

const BROWSE_DEFS = [
  { id: 'popular', title: 'Popular', sortBy: 'popularity.desc' },
  { id: 'top-rated', title: 'Top Rated', sortBy: 'vote_average.desc' },
  { id: 'new', title: 'New This Month', sortBy: 'primary_release_date.desc' },
];

export function GenreHubScreen({ genre, mediaKind }: GenreHubScreenProps) {
  const { navigateTo, navigateToFolder, dismissOverlay } = useNavigate();
  const [voteFilter, setVoteFilter] = useState<VoteFilter>('any');
  const [browseRails, setBrowseRails] = useState<BrowseRail[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [heroBackdrop, setHeroBackdrop] = useState<string | undefined>();

  const loadedRails = browseRails.filter(r => r.items.length > 0);

  const filteredBrowseRails = loadedRails.map(rail => ({
    ...rail,
    items: voteFilter === 'any' ? rail.items : rail.items.filter(i => matchesVoteFilter(i, voteFilter)),
  })).filter(r => r.items.length > 0);

  const handleMediaSelect = useCallback((item: MetaPreview) => {
    if (item.id.startsWith('folder_')) {
      const fallback: CatalogRow = {
        id: item.id,
        title: item.name,
        items: [],
        tileShape: 'poster',
        coverImage: item.poster,
        heroBackdrop: item.backdrop,
      };
      navigateToFolder(item.id, item.id, item.name);
    } else {
      navigateTo(item.type || mediaKind, item.id);
    }
  }, [navigateTo, navigateToFolder, mediaKind]);

  useEffect(() => {
    let cancelled = false;
    const apiKey = getTMDBKey();
    async function load() {
      setIsLoading(true);
      const rails: BrowseRail[] = [];
      for (const def of BROWSE_DEFS) {
        const { items } = await fetchTMDBDiscover(mediaKind, genre, def.sortBy, apiKey);
        rails.push({ id: def.id, title: displayTitle(def.title, genre), items });
      }
      if (!cancelled) {
        setBrowseRails(rails);
        setHeroBackdrop(rails[0]?.items[0]?.poster);
        setIsLoading(false);
      }
    }
    load();
    return () => { cancelled = true; };
  }, [genre, mediaKind]);

  const palette = genrePalette(genre);
  const ambientStyle = {
    background: `radial-gradient(ellipse 80% 60% at 30% 20%, ${palette.from}44, ${palette.to}11, transparent 70%)`,
  };

  const hasAnyRail = filteredBrowseRails.length > 0;

  return (
    <div className="min-h-screen bg-moonlit-bg relative">
      <div className="fixed inset-0 pointer-events-none" style={ambientStyle} />
      <div className="relative z-10">
        <div className="h-[440px] relative overflow-hidden flex items-end">
          {heroBackdrop && (
            <>
              <img
                src={heroBackdrop}
                alt=""
                className="absolute inset-0 w-full h-full object-cover"
              />
              <div className="absolute inset-0 bg-gradient-to-b from-moonlit-bg/0 via-moonlit-bg/55 to-moonlit-bg" />
              <div className="absolute inset-0 bg-gradient-to-r from-moonlit-bg/70 via-transparent to-transparent" />
            </>
          )}
          <div className="relative z-10 px-10 pb-[34px]">
            <div className="flex items-center gap-3 mb-5">
              <div className="w-[42px] h-[42px] rounded-full bg-white/[0.08] flex items-center justify-center">
                <Tag size={16} className="text-white/70" />
              </div>
              <span className="text-[13px] font-semibold tracking-[7px] text-white/40 uppercase">Genre</span>
            </div>
            <div className="flex items-center gap-[18px] mb-5">
              <h1 className="text-[66px] font-semibold font-serif text-white leading-none">{genre}</h1>
              <div className="w-[54px] h-[54px] rounded-full bg-white/[0.055] flex items-center justify-center">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-white/70"><path d="M6 9l6 6 6-6" /></svg>
              </div>
            </div>
            <p className="text-[18px] font-medium text-white/60 leading-relaxed max-w-[860px]">
              {genreDescription(genre)}
            </p>
          </div>
        </div>

        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.3 }}
        >
          {isLoading && !hasAnyRail ? (
            <LoadingView />
          ) : (
            <div className="flex flex-col gap-16 pt-4 pb-12">
              {loadedRails.length > 0 && (
                <div className="px-10">
                  <div className="flex gap-2.5 overflow-x-auto pb-1 scrollbar-hide">
                    {VOTE_FILTERS.map(f => (
                      <button
                        key={f.key}
                        type="button"
                        onClick={() => setVoteFilter(f.key)}
                        className={`px-4 py-2 text-[13px] font-semibold rounded-full transition-colors ${
                          voteFilter === f.key
                            ? 'bg-white text-black'
                            : 'bg-white/[0.06] text-white/70 hover:bg-white/[0.10]'
                        }`}
                      >
                        {f.label}
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {!hasAnyRail && !isLoading && (
                <div className="text-center py-16">
                  <p className="text-[15px] font-semibold text-white/50">Nothing here yet</p>
                </div>
              )}

              {filteredBrowseRails.map(rail => (
                <div key={rail.id}>
                  <div className="px-10 mb-6">
                    <h2 className="text-[28px] font-bold text-white">{rail.title}</h2>
                    <p className="text-[13px] font-bold tracking-[6px] text-white/30 uppercase mt-2">
                      {railSubtitle(rail.id)}
                    </p>
                  </div>
                  <div className="overflow-x-auto scrollbar-hide">
                    <div className="flex gap-6 px-10 py-2.5">
                      {rail.items.map(item => (
                        <PosterCard key={item.id} item={item} onClick={() => handleMediaSelect(item)} />
                      ))}
                    </div>
                  </div>
                </div>
              ))}

              {isLoading && hasAnyRail && (
                <div className="flex justify-center py-16">
                  <StrokeSpinner size={40} />
                </div>
              )}
            </div>
          )}
        </motion.div>
      </div>
    </div>
  );
}

function displayTitle(title: string, genre: string): string {
  switch (title) {
    case 'Popular': return `Popular ${genre}`;
    case 'Top Rated': return `Top Rated ${genre}`;
    case 'New This Month': return `Recent ${genre}`;
    default: return title;
  }
}

function railSubtitle(id: string): string {
  switch (id) {
    case 'popular': return "What's Hot Right Now";
    case 'top-rated': return 'All-Time Bests';
    case 'new': return 'Recently Added';
    default: return 'Spotlight';
  }
}
