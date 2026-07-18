import { useEffect, useState, useRef, useCallback } from 'react';
import { Search, X, Clock, MapPin, Sparkles, Star, Play, Film, Tv, type LucideIcon } from 'lucide-react';
import { useNavigate } from '@/shell/Shell';
import { searchCatalogs } from '@/lib/stremio';
import { useAuth } from '@/app/AuthProvider';
import { TMDB_API_KEY } from '@/lib/supabase';
import StrokeSpinner from '@/components/StrokeSpinner';
import type { MetaPreview } from '@/lib/types';

const RECENT_KEY = 'moonlit.recentSearches';
const MAX_RECENT = 15;
const GENRES = [
  'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary',
  'Drama', 'Family', 'Fantasy', 'History', 'Horror', 'Music',
  'Mystery', 'Romance', 'Science Fiction', 'Thriller', 'War', 'Western',
];

interface TmdbResult {
  id: number;
  media_type: 'movie' | 'tv' | 'person';
  title?: string;
  name?: string;
  poster_path?: string;
  backdrop_path?: string;
  profile_path?: string;
  overview?: string;
  release_date?: string;
  first_air_date?: string;
  vote_average?: number;
  known_for?: { title?: string; name?: string }[];
  popularity?: number;
  genre_ids?: number[];
}

export function SearchScreen({ onClose }: { onClose: () => void }) {
  const { navigateTo, startPlayback } = useNavigate();
  const { addons } = useAuth();

  const [query, setQuery] = useState('');
  const [recents, setRecents] = useState<string[]>([]);
  const [localHits, setLocalHits] = useState<MetaPreview[]>([]);
  const [tmdbMovies, setTmdbMovies] = useState<MetaPreview[]>([]);
  const [tmdbSeries, setTmdbSeries] = useState<MetaPreview[]>([]);
  const [tmdbPeople, setTmdbPeople] = useState<TmdbResult[]>([]);
  const [addonResults, setAddonResults] = useState<MetaPreview[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);

  const inputRef = useRef<HTMLInputElement>(null);
  const searchTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => {
    inputRef.current?.focus();
    loadRecents();
  }, []);

  const loadRecents = () => {
    try {
      const raw = localStorage.getItem(RECENT_KEY);
      if (raw) setRecents(JSON.parse(raw).slice(0, MAX_RECENT));
    } catch {}
  };

  const recordRecent = (term: string) => {
    const next = [term, ...recents.filter((r) => r !== term)].slice(0, MAX_RECENT);
    setRecents(next);
    try { localStorage.setItem(RECENT_KEY, JSON.stringify(next)); } catch {}
  };

  const clearRecents = () => {
    setRecents([]);
    try { localStorage.removeItem(RECENT_KEY); } catch {}
  };

  const removeRecent = (term: string) => {
    const next = recents.filter((r) => r !== term);
    setRecents(next);
    try { localStorage.setItem(RECENT_KEY, JSON.stringify(next)); } catch {}
  };

  const toMetaPreview = (r: TmdbResult): MetaPreview => {
    const title = r.title ?? r.name ?? '';
    const year = (r.release_date ?? r.first_air_date ?? '').slice(0, 4);
    return {
      id: r.media_type === 'movie' ? `tt${r.id}` : `tt${r.id}`,
      type: r.media_type === 'tv' ? 'series' : r.media_type,
      name: title,
      poster: r.poster_path ? `https://image.tmdb.org/t/p/w500${r.poster_path}` : undefined,
      background: r.backdrop_path ? `https://image.tmdb.org/t/p/w1280${r.backdrop_path}` : undefined,
      description: r.overview,
      releaseInfo: year || undefined,
      imdbRating: r.vote_average ? r.vote_average.toFixed(1) : undefined,
      popularity: r.popularity,
    };
  };

  const performSearch = useCallback(
    (q: string) => {
      clearTimeout(searchTimerRef.current);
      const trimmed = q.trim();
      if (!trimmed || trimmed.length < 2) {
        setLocalHits([]);
        setTmdbMovies([]);
        setTmdbSeries([]);
        setTmdbPeople([]);
        setAddonResults([]);
        setIsSearching(false);
        setHasSearched(false);
        return;
      }

      setIsSearching(true);
      setHasSearched(true);

      searchTimerRef.current = setTimeout(async () => {
        const tmdbPromise = fetch(
          `https://api.themoviedb.org/3/search/multi?query=${encodeURIComponent(trimmed)}&api_key=${TMDB_API_KEY}&include_adult=false`,
        )
          .then((r) => r.json())
          .catch(() => ({ results: [] }));

        const addonPromise = searchCatalogs(addons, trimmed).catch(() => []);

        const [tmdbData, addonData] = await Promise.all([tmdbPromise, addonPromise]);

        const results: TmdbResult[] = tmdbData.results ?? [];

        setTmdbMovies(
          results
            .filter((r) => r.media_type === 'movie')
            .slice(0, 12)
            .map(toMetaPreview),
        );
        setTmdbSeries(
          results
            .filter((r) => r.media_type === 'tv')
            .slice(0, 12)
            .map(toMetaPreview),
        );
        setTmdbPeople(
          results.filter((r) => r.media_type === 'person').slice(0, 10),
        );
        setAddonResults(addonData);
        setIsSearching(false);
      }, 250);
    },
    [addons],
  );

  useEffect(() => {
    performSearch(query);
    return () => clearTimeout(searchTimerRef.current);
  }, [query, performSearch]);

  const handleSelect = (item: MetaPreview) => {
    recordRecent(query);
    navigateTo(item.type, item.id);
    onClose();
  };

  const allMovies = dedupe([...tmdbMovies, ...addonResults.filter((r) => r.type === 'movie')]);
  const allSeries = dedupe([...tmdbSeries, ...addonResults.filter((r) => r.type === 'series')]);
  const topMatch = [...allMovies, ...allSeries].sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0))[0];

  const hasResults = allMovies.length > 0 || allSeries.length > 0 || tmdbPeople.length > 0;

  const isEmpty = query.trim().length < 2;

  return (
    <div className="fixed inset-0 z-50 bg-moonlit-bg/95 backdrop-blur-xl flex flex-col" onClick={onClose}>
      <div className="flex flex-col items-center pt-12 pb-6" onClick={(e) => e.stopPropagation()}>
        <div className="w-full max-w-[480px] px-4">
          <div className="glass-dark-capsule flex items-center gap-3 h-[50px] px-5">
            <Search size={17} className="text-white/40 shrink-0" />
            <input
              ref={inputRef}
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search movies, shows, people..."
              className="flex-1 bg-transparent text-white text-[15px] outline-none placeholder:text-white/30"
              onKeyDown={(e) => e.key === 'Escape' && onClose()}
            />
            {isSearching && <StrokeSpinner size={16} />}
            {query && (
              <button onClick={() => { setQuery(''); inputRef.current?.focus(); }} className="text-white/40 hover:text-white">
                <X size={16} />
              </button>
            )}
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-12" onClick={(e) => e.stopPropagation()}>
        <div className="max-w-[900px] mx-auto space-y-8">

          {isEmpty && (
            <>
              {recents.length > 0 && (
                <div>
                  <div className="flex items-center justify-between mb-3">
                    <SectionLabel icon={Clock} text="RECENT SEARCHES" />
                    <button onClick={clearRecents} className="text-[11px] font-bold text-white/40 hover:text-white/60">
                      Clear History
                    </button>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {recents.map((term) => (
                      <div key={term} className="h-8 glass-capsule flex items-center gap-1 pl-4 pr-1.5">
                        <button
                          onClick={() => { setQuery(term); inputRef.current?.focus(); }}
                          className="text-[13px] font-medium text-white/85"
                        >
                          {term}
                        </button>
                        <button
                          onClick={() => removeRecent(term)}
                          className="w-5 h-5 flex items-center justify-center text-white/30 hover:text-white/60"
                        >
                          <X size={11} />
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <div>
                <SectionLabel icon={MapPin} text="JUMP TO" />
                <div className="flex flex-wrap gap-2 mt-3">
                  <JumpChip label="Home" icon={Play} onClick={() => { onClose(); }} />
                  <JumpChip label="Library" icon={Clock} onClick={() => { onClose(); }} />
                  <JumpChip label="Settings" icon={MapPin} onClick={() => { onClose(); }} />
                </div>
              </div>

              <div>
                <SectionLabel icon={Sparkles} text="TRY A GENRE" />
                <div className="flex flex-wrap gap-2 mt-3">
                  {GENRES.map((g) => (
                    <button
                      key={g}
                      onClick={() => { setQuery(g); inputRef.current?.focus(); }}
                      className="px-4 py-2 text-[13px] font-medium text-white/85 glass-capsule"
                    >
                      {g}
                    </button>
                  ))}
                </div>
              </div>
            </>
          )}

          {!isEmpty && isSearching && !hasResults && (
            <div className="flex justify-center py-16">
              <StrokeSpinner size={28} />
            </div>
          )}

          {!isEmpty && !isSearching && hasSearched && !hasResults && (
            <div className="flex flex-col items-center gap-2 py-16 text-white/40">
              <Search size={28} />
              <span>No results for &ldquo;{query}&rdquo;</span>
            </div>
          )}

          {!isEmpty && hasResults && (
            <>
              {topMatch && (
                <div className="flex gap-6 p-5 rounded-2xl bg-white/[0.035]">
                  <div className="shrink-0 w-[132px] h-[198px] rounded-xl bg-moonlit-elevated overflow-hidden">
                    {topMatch.poster ? (
                      <img src={topMatch.poster} alt={topMatch.name} className="w-full h-full object-cover" />
                    ) : (
                      <div className="w-full h-full bg-moonlit-elevated" />
                    )}
                  </div>
                  <div className="flex flex-col gap-2">
                    <span className="text-[11px] font-black tracking-[2px] text-moonlit-gold">TOP MATCH</span>
                    <h2 className="text-[28px] font-medium text-white leading-tight">{topMatch.name}</h2>
                    <div className="flex items-center gap-2 text-[13px] text-white/50">
                      <span>{topMatch.type === 'series' ? 'Series' : 'Movie'}</span>
                      {topMatch.releaseInfo && <><span>·</span><span>{topMatch.releaseInfo}</span></>}
                      {topMatch.imdbRating && (
                        <span className="inline-flex items-center gap-1 text-moonlit-gold">
                          <Star size={10} fill="currentColor" />{topMatch.imdbRating}
                        </span>
                      )}
                    </div>
                    {topMatch.description && (
                      <p className="text-[13px] text-white/60 line-clamp-3">{topMatch.description}</p>
                    )}
                    <button
                      onClick={() => handleSelect(topMatch)}
                      className="mt-2 inline-flex items-center gap-2 btn-primary w-fit text-[13px]"
                    >
                      <Play size={14} fill="currentColor" /> Open
                    </button>
                  </div>
                </div>
              )}

              {tmdbPeople.length > 0 && (
                <div>
                  <SectionLabel icon={Film} text="PEOPLE" />
                  <div className="flex gap-4 overflow-x-auto py-2 scrollbar-hide">
                    {tmdbPeople.map((person) => (
                      <div key={person.id} className="flex flex-col items-center gap-2 shrink-0 w-[96px]">
                        <div className="w-[84px] h-[84px] rounded-full bg-moonlit-elevated overflow-hidden">
                          {person.profile_path ? (
                            <img src={`https://image.tmdb.org/t/p/w185${person.profile_path}`} alt={person.name} className="w-full h-full object-cover" />
                          ) : (
                            <div className="w-full h-full flex items-center justify-center text-white/20">
                              <Film size={28} />
                            </div>
                          )}
                        </div>
                        <span className="text-[12px] font-semibold text-white line-clamp-1 text-center">{person.name}</span>
                        {person.known_for?.[0] && (
                          <span className="text-[10px] text-white/40 line-clamp-1 text-center">
                            {person.known_for[0].title ?? person.known_for[0].name}
                          </span>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <div className="flex gap-10">
                <div className="flex-1">
                  <SectionLabel icon={Film} text="MOVIES" />
                  {allMovies.length > 0 ? (
                    <div className="space-y-3 mt-3">
                      {allMovies.slice(0, 8).map((item) => (
                        <SearchResultRow key={item.id} item={item} onClick={() => handleSelect(item)} />
                      ))}
                    </div>
                  ) : null}
                </div>
                <div className="flex-1">
                  <SectionLabel icon={Tv} text="SERIES" />
                  {allSeries.length > 0 ? (
                    <div className="space-y-3 mt-3">
                      {allSeries.slice(0, 8).map((item) => (
                        <SearchResultRow key={item.id} item={item} onClick={() => handleSelect(item)} />
                      ))}
                    </div>
                  ) : null}
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function SectionLabel({ icon: Icon, text }: { icon: LucideIcon; text: string }) {
  return (
    <div className="flex items-center gap-2">
      <Icon size={12} />
      <span className="text-[11px] font-bold tracking-[1.6px] text-white/45">{text}</span>
    </div>
  );
}

function JumpChip({ label, icon: Icon, onClick }: { label: string; icon: LucideIcon; onClick: () => void }) {
  return (
    <button onClick={onClick} className="glass-capsule flex items-center gap-2 px-4 py-2.5 text-[13px] font-semibold text-white/85 hover:text-white">
      <Icon size={14} className="text-white/50" />
      {label}
    </button>
  );
}

function SearchResultRow({ item, onClick }: { item: MetaPreview; onClick: () => void }) {
  return (
    <button onClick={onClick} className="flex items-start gap-3 w-full text-left hover:bg-white/[0.03] rounded-lg p-1.5 -m-1.5 transition-colors">
      <div className="shrink-0 w-[56px] h-[84px] rounded-lg bg-moonlit-elevated overflow-hidden">
        {item.poster ? (
          <img src={item.poster} alt={item.name} className="w-full h-full object-cover" />
        ) : (
          <div className="w-full h-full bg-moonlit-elevated" />
        )}
      </div>
      <div className="min-w-0">
        <h3 className="text-[14px] font-semibold text-white line-clamp-1">{item.name}</h3>
        <div className="flex items-center gap-1.5 text-[11px] text-white/50">
          {item.releaseInfo && <span>{item.releaseInfo}</span>}
          {item.imdbRating && (
            <span className="inline-flex items-center gap-0.5 text-moonlit-gold">
              <Star size={9} fill="currentColor" />{item.imdbRating}
            </span>
          )}
        </div>
        {item.description && (
          <p className="text-[12px] text-white/45 line-clamp-2 mt-1">{item.description}</p>
        )}
      </div>
    </button>
  );
}

function dedupe(items: MetaPreview[]): MetaPreview[] {
  const seen = new Set<string>();
  return items.filter((i) => {
    if (seen.has(i.id)) return false;
    seen.add(i.id);
    return true;
  });
}
