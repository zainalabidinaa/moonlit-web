'use client';

import { useState, useEffect, useRef } from 'react';
import { useAuth } from '../AuthProvider';
import { useRouter } from 'next/navigation';
import { Sidebar } from '@/components/Sidebar';
import { MetaPreview } from '@/lib/types';
import { searchCatalogs, fetchManifest, fetchCatalog } from '@/lib/stremio';
import { getSystemAddon } from '@/lib/services/api';
import Link from 'next/link';

const RECENT_KEY = 'luna_recent_searches';

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
  const { addons, user, currentProfile, isLoading } = useAuth();
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);

  const [query, setQuery] = useState('');
  const [results, setResults] = useState<MetaPreview[]>([]);
  const [suggestions, setSuggestions] = useState<MetaPreview[]>([]);
  const [trending, setTrending] = useState<MetaPreview[]>([]);
  const [recent, setRecent] = useState<string[]>([]);
  const [filter, setFilter] = useState<Filter>('all');
  const [loading, setLoading] = useState(false);
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    if (!currentProfile) { router.replace('/profiles'); return; }
    setRecent(getRecent());
    loadTrending();
  }, [isLoading, user, currentProfile]);

  async function loadTrending() {
    try {
      const systemAddon = await getSystemAddon();
      if (!systemAddon?.manifest_url) return;
      const manifest = await fetchManifest(systemAddon.manifest_url);
      if (!manifest.transportUrl) return;
      const [movies, shows] = await Promise.all([
        fetchCatalog(manifest.transportUrl, 'movie', 'tmdb.trending_movie', { genre: 'Day' }).catch(() => []),
        fetchCatalog(manifest.transportUrl, 'series', 'tmdb.top_series').catch(() => []),
      ]);
      setTrending([...movies, ...shows].slice(0, 10));
    } catch {}
  }

  // Debounced suggestions
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
    router.push(`/browse/${item.type}/${item.id}`);
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

  const filtered = filter === 'all' ? results
    : results.filter(r => r.type === filter);

  const isEmpty = !query && !submitted;

  return (
    <Sidebar>
      <div className="px-6 pt-20 pb-12 max-w-5xl">
        {/* Search input */}
        <div className="relative mb-6">
          <div className={`flex items-center gap-3 bg-[#141414] border rounded-xl px-4 py-3 transition-all ${query ? 'border-white/20' : 'border-white/8'}`}>
            <svg className="w-4 h-4 text-white/40 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35" strokeLinecap="round"/></svg>
            <form onSubmit={handleSearch} className="flex-1 flex items-center gap-2">
              <input
                ref={inputRef}
                type="text"
                value={query}
                onChange={e => handleQueryChange(e.target.value)}
                onFocus={() => setShowSuggestions(true)}
                onBlur={() => setTimeout(() => setShowSuggestions(false), 150)}
                placeholder="Search movies & shows..."
                className="flex-1 bg-transparent text-white text-[15px] placeholder-white/30 outline-none"
                autoComplete="off"
              />
              {query && (
                <button type="button" onClick={() => { setQuery(''); setResults([]); setSubmitted(false); }}
                  className="w-5 h-5 rounded-full bg-white/10 flex items-center justify-center shrink-0">
                  <svg className="w-2.5 h-2.5" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
              )}
            </form>
          </div>

          {/* Suggestions dropdown */}
          {showSuggestions && query && !submitted && suggestions.length > 0 && (
            <div className="absolute top-full left-0 right-0 mt-1.5 bg-[#141414] border border-white/10 rounded-xl overflow-hidden shadow-2xl z-50">
              <div className="py-1">
                {suggestions.map(item => (
                  <button key={item.id} onMouseDown={() => handleSuggestionClick(item)}
                    className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-white/5 text-left transition-colors">
                    {item.poster
                      ? <img src={item.poster} alt="" className="w-8 h-12 object-cover rounded-md shrink-0" />
                      : <div className="w-8 h-12 bg-white/5 rounded-md shrink-0" />}
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

        {/* EMPTY STATE */}
        {isEmpty && (
          <>
            {recent.length > 0 && (
              <section className="mb-8">
                <p className="text-xs font-bold text-white/30 uppercase tracking-wider mb-3">Recent</p>
                <div className="flex gap-2 flex-wrap">
                  {recent.map(r => (
                    <div key={r} className="flex items-center gap-2 px-3 py-1.5 bg-white/5 border border-white/8 rounded-full cursor-pointer group">
                      <svg className="w-3 h-3 text-white/30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
                      <span className="text-xs text-white/60" onClick={() => handleRecentClick(r)}>{r}</span>
                      <button onClick={() => { removeRecent(r); setRecent(getRecent()); }}
                        className="opacity-0 group-hover:opacity-100 transition-opacity">
                        <svg className="w-2.5 h-2.5 text-white/30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><path d="M18 6L6 18M6 6l12 12"/></svg>
                      </button>
                    </div>
                  ))}
                </div>
              </section>
            )}

            {trending.length > 0 && (
              <section>
                <p className="text-xs font-bold text-white/30 uppercase tracking-wider mb-3">Trending Now</p>
                <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
                  {trending.map((item, i) => (
                    <Link key={item.id} href={`/browse/${item.type}/${item.id}`}
                      className="flex items-center gap-3 flex-shrink-0 bg-[#141414] border border-white/6 rounded-xl px-3 py-2 hover:bg-[#1c1c1e] transition-colors cursor-pointer">
                      <span className="text-2xl font-black text-white/15 min-w-[20px]">{i + 1}</span>
                      {item.poster
                        ? <img src={item.poster} alt={item.name} className="w-9 h-[54px] object-cover rounded-md shrink-0" />
                        : <div className="w-9 h-[54px] bg-white/5 rounded-md shrink-0" />}
                      <div className="min-w-0">
                        <p className="text-xs font-semibold text-white/80 whitespace-nowrap">{item.name}</p>
                        <p className="text-[10px] text-white/35 mt-0.5">{item.type === 'series' ? 'Series' : 'Movie'}</p>
                      </div>
                    </Link>
                  ))}
                </div>
              </section>
            )}
          </>
        )}

        {/* LOADING */}
        {loading && (
          <div className="flex items-center justify-center py-20">
            <div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" />
          </div>
        )}

        {/* RESULTS */}
        {!loading && submitted && (
          <>
            <div className="flex items-center gap-3 mb-4">
              {(['all', 'movie', 'series'] as Filter[]).map(f => (
                <button key={f} onClick={() => setFilter(f)}
                  className={`px-3.5 py-1.5 rounded-full text-xs font-medium transition-all border ${
                    filter === f
                      ? 'bg-white/12 text-white border-white/20'
                      : 'bg-white/4 text-white/45 border-white/6 hover:text-white/70'
                  }`}>
                  {f === 'all' ? 'All' : f === 'movie' ? 'Movies' : 'Shows'}
                </button>
              ))}
              <span className="text-xs text-white/35 ml-auto">{filtered.length} results</span>
            </div>

            {filtered.length > 0 ? (
              <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3">
                {filtered.map(item => (
                  <Link key={item.id} href={`/browse/${item.type}/${item.id}`} className="group cursor-pointer">
                    <div className="relative aspect-[2/3] rounded-lg overflow-hidden bg-luna-elevated mb-2">
                      {item.poster
                        ? <img src={item.poster} alt={item.name} className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105" loading="lazy" />
                        : <div className="absolute inset-0 flex items-center justify-center text-white/20 text-xs text-center px-2">{item.name}</div>}
                      <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                        <div className="w-10 h-10 rounded-full bg-white/20 flex items-center justify-center">
                          <svg viewBox="0 0 24 24" fill="white" className="w-4 h-4 ml-0.5"><polygon points="6,4 20,12 6,20"/></svg>
                        </div>
                      </div>
                    </div>
                    <p className="text-xs font-medium text-white/80 truncate">{item.name}</p>
                    {item.releaseInfo && <p className="text-[10px] text-white/35 mt-0.5">{item.releaseInfo}</p>}
                  </Link>
                ))}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-24 gap-4">
                <svg className="w-12 h-12 text-white/15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35" strokeLinecap="round"/></svg>
                <p className="text-white/40 text-sm">No results for &ldquo;{query}&rdquo;</p>
                <p className="text-white/25 text-xs">Try a different spelling or keyword</p>
              </div>
            )}
          </>
        )}
      </div>
    </Sidebar>
  );
}
