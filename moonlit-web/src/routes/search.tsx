import { useState, useEffect, useRef } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { useQuery } from '@tanstack/react-query';
import { MetaPreview } from '@/lib/types';
import { searchCatalogs, fetchManifest, fetchCatalog } from '@/lib/stremio';
import { getSystemAddon } from '@/lib/services/api';
import { Link, useNavigate } from '@tanstack/react-router';

const RECENT_KEY = 'moonlit_recent_searches';
function getRecent(): string[] {
  try { return JSON.parse(localStorage.getItem(RECENT_KEY) || '[]'); } catch { return []; }
}
function addRecent(q: string) {
  const prev = getRecent().filter(r => r !== q);
  localStorage.setItem(RECENT_KEY, JSON.stringify([q, ...prev].slice(0, 5)));
}
function removeRecent(q: string) {
  localStorage.setItem(RECENT_KEY, JSON.stringify(getRecent().filter(r => r !== q)));
}

type Filter = 'all' | 'movie' | 'series';

export default function SearchPage() {
  const { addons } = useAuth();
  const navigate = useNavigate();
  const inputRef = useRef<HTMLInputElement>(null);

  const [query, setQuery] = useState('');
  const [results, setResults] = useState<MetaPreview[]>([]);
  const [suggestions, setSuggestions] = useState<MetaPreview[]>([]);
  const [recent, setRecent] = useState<string[]>(() => getRecent());
  const [filter, setFilter] = useState<Filter>('all');
  const [loading, setLoading] = useState(false);
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const { data: trending = [] } = useQuery({
    queryKey: ['trending'],
    queryFn: async () => {
      const systemAddon = await getSystemAddon();
      if (!systemAddon?.manifest_url) return [];
      const manifest = await fetchManifest(systemAddon.manifest_url);
      if (!manifest.transportUrl) return [];
      const [movies, shows] = await Promise.all([
        fetchCatalog(manifest.transportUrl, 'movie', 'tmdb.trending_movie', { genre: 'Day' }).catch(() => []),
        fetchCatalog(manifest.transportUrl, 'series', 'tmdb.top_series').catch(() => []),
      ]);
      return [...movies, ...shows].slice(0, 10);
    },
    staleTime: 10 * 60 * 1000,
  });

  useEffect(() => {
    clearTimeout(debounceRef.current);
    if (!query.trim() || submitted) { setSuggestions([]); return; }
    debounceRef.current = setTimeout(async () => {
      const items = await searchCatalogs(addons, query);
      setSuggestions(items.slice(0, 5));
    }, 250);
    return () => clearTimeout(debounceRef.current);
  }, [query, addons, submitted]);

  async function handleSearch(e?: React.FormEvent) {
    e?.preventDefault();
    if (!query.trim()) return;
    setSubmitted(true);
    setShowSuggestions(false);
    setLoading(true);
    addRecent(query);
    setRecent(getRecent());
    const items = await searchCatalogs(addons, query);
    setResults(items);
    setLoading(false);
  }

  function handleSuggestionClick(item: MetaPreview) {
    addRecent(item.name);
    setRecent(getRecent());
    navigate({ to: '/browse/$type/$id', params: { type: item.type, id: item.id } });
  }

  function handleQueryChange(val: string) {
    setQuery(val);
    setSubmitted(false);
    setResults([]);
    setShowSuggestions(true);
  }

  function handleRecentClick(r: string) {
    setQuery(r);
    setSubmitted(false);
    setShowSuggestions(false);
    setTimeout(() => handleSearch(), 50);
  }

  const filtered = filter === 'all' ? results : results.filter(r => r.type === filter);
  const isEmpty = !query && !submitted;

  return (
    <div>
      <div className="pt-8 pb-8 bg-[#1f1f1f]/30">
        <div className="relative z-10 px-6 pt-4 max-w-2xl mx-auto">
          <h1 className="text-2xl font-bold text-white mb-6 text-center">Search</h1>
          <div className="relative">
            <div className={`flex items-center gap-3 bg-[#1f1f1f] border rounded px-4 py-3 transition-all ${query ? 'border-white/25' : 'border-white/10'}`}>
              <svg className="w-4 h-4 text-white/40 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35" strokeLinecap="round"/></svg>
              <form onSubmit={handleSearch} className="flex-1 flex items-center gap-2">
                <input ref={inputRef} type="text" value={query} onChange={e => handleQueryChange(e.target.value)}
                  onFocus={() => setShowSuggestions(true)} onBlur={() => setTimeout(() => setShowSuggestions(false), 150)}
                  placeholder="Search movies & shows..."
                  aria-label="Search"
                  className="flex-1 bg-transparent text-white text-[15px] placeholder-white/30 outline-none" autoComplete="off" />
                {query && (
                  <button type="button" onClick={() => { setQuery(''); setResults([]); setSubmitted(false); }}
                    className="w-5 h-5 rounded-full bg-white/10 flex items-center justify-center shrink-0">
                    <svg className="w-2.5 h-2.5" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3"><path d="M18 6L6 18M6 6l12 12"/></svg>
                  </button>
                )}
              </form>
            </div>
            {showSuggestions && query && !submitted && suggestions.length > 0 && (
              <div className="absolute top-full left-0 right-0 mt-1.5 bg-[#141414] border border-white/10 rounded overflow-hidden shadow-2xl z-50">
                <div className="py-1">
                  {suggestions.map(item => (
                    <button key={item.id} onMouseDown={() => handleSuggestionClick(item)}
                      className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-left transition-colors">
                      {item.poster ? <img src={item.poster} alt="" className="w-8 h-12 object-cover rounded shrink-0" /> : <div className="w-8 h-12 bg-white/5 rounded shrink-0" />}
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-semibold text-white/90 truncate">{item.name}</p>
                        <p className="text-xs text-white/40 mt-0.5">
                          {item.type === 'series' ? 'Series' : 'Movie'}
                          {item.releaseInfo ? ` · ${item.releaseInfo}` : ''}
                          {item.imdbRating ? ` · ★ ${item.imdbRating}` : ''}
                        </p>
                      </div>
                      <svg className="w-4 h-4 text-white/20 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18l6-6-6-6"/></svg>
                    </button>
                  ))}
                  <div className="border-t border-white/5 mt-1 pt-1 pb-1">
                    <button onMouseDown={() => handleSearch()} className="w-full text-center text-xs text-white/35 py-2 hover:text-white/60 transition-colors">
                      Press Enter to see all results
                    </button>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="px-6 md:px-14 pb-16 max-w-5xl mx-auto">
        {isEmpty && (
          <>
            {recent.length > 0 && (
              <section className="mb-8 mt-6">
                <p className="text-xs font-bold text-white/40 uppercase tracking-wider mb-3">Recent</p>
                <div className="flex gap-2 flex-wrap">
                  {recent.map(r => (
                    <div key={r} className="flex items-center gap-2 px-3 py-1.5 bg-[#1f1f1f] border border-white/10 rounded cursor-pointer group">
                      <svg className="w-3 h-3 text-white/30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
                      <span className="text-xs text-white/60" onClick={() => handleRecentClick(r)}>{r}</span>
                      <button onClick={() => { removeRecent(r); setRecent(getRecent()); }} className="opacity-0 group-hover:opacity-100 transition-opacity">
                        <svg className="w-2.5 h-2.5 text-white/30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><path d="M18 6L6 18M6 6l12 12"/></svg>
                      </button>
                    </div>
                  ))}
                </div>
              </section>
            )}
            {trending.length > 0 && (
              <section className="mt-8">
                <p className="text-xs font-bold text-white/40 uppercase tracking-wider mb-4">Trending Now</p>
                <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(155px, 1fr))' }}>
                  {trending.map(item => (
                    <Link key={item.id} to="/browse/$type/$id" params={{ type: item.type, id: item.id }} className="group cursor-pointer">
                      <div className="relative aspect-[2/3] rounded overflow-hidden bg-[#2a2a2a] mb-2 border border-white/[0.06]">
                        {item.poster ? <img src={item.poster} alt={item.name} className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105" loading="lazy" /> : <div className="absolute inset-0 flex items-center justify-center text-white/15 text-xs text-center px-2">{item.name}</div>}
                        <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                          <div className="w-9 h-9 rounded-full bg-white/20 flex items-center justify-center">
                            <svg viewBox="0 0 24 24" fill="white" className="w-4 h-4 ml-0.5"><polygon points="6,4 20,12 6,20"/></svg>
                          </div>
                        </div>
                      </div>
                      <p className="text-xs font-medium text-[#b3b3b3] truncate">{item.name}</p>
                      {item.releaseInfo && <p className="text-[10px] text-white/35 mt-0.5">{item.releaseInfo}</p>}
                    </Link>
                  ))}
                </div>
              </section>
            )}
          </>
        )}

        {loading && (
          <div className="flex items-center justify-center py-20">
            <div className="w-7 h-7 rounded-full border-2 border-white/[0.14] border-t-white animate-spin-arc" />
          </div>
        )}

        {!loading && submitted && (
          <>
            <div className="flex items-center gap-2 mb-6 mt-6">
              {(['all', 'movie', 'series'] as Filter[]).map(f => (
                <button key={f} onClick={() => setFilter(f)}
                  className={`px-4 py-1.5 rounded text-xs font-semibold transition-all ${filter === f ? 'bg-white text-black' : 'bg-[#1f1f1f] border border-white/10 text-white/50 hover:text-white/80'}`}>
                  {f === 'all' ? 'All' : f === 'movie' ? 'Movies' : 'Shows'}
                </button>
              ))}
              <span className="text-xs text-white/30 ml-auto">{filtered.length} results</span>
            </div>
            {filtered.length > 0 ? (
              <div className="flex flex-col gap-1.5 max-w-2xl">
                {filtered.map(item => (
                  <Link key={item.id} to="/browse/$type/$id" params={{ type: item.type, id: item.id }}
                    className="group flex items-center gap-3 p-2 rounded hover:bg-white/5 transition-colors">
                    {item.poster
                      ? <img src={item.poster} alt={item.name} loading="lazy" className="w-[52px] h-[78px] object-cover rounded shrink-0 bg-[#2a2a2a]" />
                      : <div className="w-[52px] h-[78px] rounded bg-[#2a2a2a] shrink-0 flex items-center justify-center text-white/15 text-[10px] text-center px-1">{item.name}</div>}
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-white truncate">{item.name}</p>
                      <div className="flex items-center gap-2 mt-1 text-[11px] text-white/45">
                        <span className="px-1.5 py-0.5 rounded bg-white/8 font-medium text-white/60">{item.type === 'series' ? 'Series' : 'Movie'}</span>
                        {item.imdbRating && <span className="text-moonlit-gold font-semibold">★ {item.imdbRating}</span>}
                        {item.releaseInfo && <span>{item.releaseInfo}</span>}
                      </div>
                    </div>
                    <svg className="w-4 h-4 text-white/20 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18l6-6-6-6"/></svg>
                  </Link>
                ))}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-24 gap-4">
                <svg className="w-12 h-12 text-white/15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35" strokeLinecap="round"/></svg>
                <p className="text-white/30 text-sm">No results for &ldquo;{query}&rdquo;</p>
                <p className="text-white/25 text-xs">Try a different spelling or keyword</p>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
