import { useState, useEffect } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Sidebar } from '@/components/Sidebar';
import { getLibrary, toggleLibrary as toggleLib, getWatchProgress } from '@/lib/services/api';
import { getLikedItems, removeLiked, refreshUpcoming, LikedItem, UpcomingInfo } from '@/lib/liked';
import { Link } from '@tanstack/react-router';

type MediaFilter = 'all' | 'movie' | 'series';

const POSTER_GRID = { gridTemplateColumns: 'repeat(auto-fill, minmax(120px, 1fr))' } as const;

// ── Shared poster card ────────────────────────────────────────────────────

function PosterCard({
  to, params, poster, name, mediaType, progress, onRemove,
}: {
  to: string; params: Record<string, string>; poster?: string | null;
  name: string; mediaType: string; progress?: number;
  onRemove?: (e: React.MouseEvent) => void;
}) {
  return (
    <Link to={to as any} params={params} className="group cursor-pointer block">
      <div className="relative rounded-xl overflow-hidden bg-moonlit-elevated mb-2" style={{ aspectRatio: '2/3' }}>
        {poster
          ? <img src={poster} alt={name} loading="lazy"
              className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105" />
          : <div className="absolute inset-0 flex items-center justify-center">
              <span className="text-white/20 text-xs text-center px-2">{name}</span>
            </div>}

        {onRemove && (
          <button onClick={onRemove}
            className="absolute top-1.5 right-1.5 w-6 h-6 rounded-full bg-black/70 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity z-10"
            aria-label="Remove">
            <svg className="w-3 h-3 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <path d="M18 6L6 18M6 6l12 12"/>
            </svg>
          </button>
        )}

        {/* Play overlay */}
        <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
          <div className="w-10 h-10 rounded-full bg-white/20 backdrop-blur-sm flex items-center justify-center">
            <svg viewBox="0 0 24 24" fill="white" className="w-5 h-5 ml-0.5"><polygon points="6,4 20,12 6,20"/></svg>
          </div>
        </div>

        {progress !== undefined && (
          <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-white/10">
            <div className="h-full bg-moonlit-accent" style={{ width: `${Math.round(progress * 100)}%` }} />
          </div>
        )}
      </div>
      <p className="text-xs font-medium text-white/80 truncate">{name}</p>
      <p className="text-[10px] text-white/35 mt-0.5">{mediaType === 'series' ? 'Series' : 'Movie'}</p>
    </Link>
  );
}

// ── Section header (matches iOS librarySectionHeader) ────────────────────

function SectionHeader({ title, count, icon }: { title: string; count: number; icon?: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2 mb-3 mt-8 first:mt-0">
      {icon}
      <h2 className="text-lg font-bold text-white">{title}</h2>
      <span className="text-sm text-white/35">({count})</span>
    </div>
  );
}

function FilterChips({ value, onChange }: { value: MediaFilter; onChange: (f: MediaFilter) => void }) {
  return (
    <div className="flex gap-2 mb-5">
      {(['all', 'movie', 'series'] as MediaFilter[]).map(f => (
        <button key={f} onClick={() => onChange(f)}
          className={`px-3.5 py-1.5 rounded-full text-xs font-semibold transition-all ${
            value === f ? 'bg-white/20 text-white' : 'bg-white/8 text-white/50 hover:text-white/80'
          }`}>
          {f === 'all' ? 'All' : f === 'movie' ? 'Movies' : 'Series'}
        </button>
      ))}
    </div>
  );
}

// ── Page ─────────────────────────────────────────────────────────────────

export default function LibraryPage() {
  const { currentProfile } = useAuth();
  const queryClient = useQueryClient();
  const [watchlistFilter, setWatchlistFilter] = useState<MediaFilter>('all');
  const [likedFilter, setLikedFilter] = useState<MediaFilter>('all');
  const [likedItems, setLikedItems] = useState<LikedItem[]>(() => getLikedItems());
  const [upcoming, setUpcoming] = useState<Record<string, UpcomingInfo>>({});

  // Keep liked items in sync with localStorage changes
  useEffect(() => {
    function onChanged() { setLikedItems(getLikedItems()); }
    window.addEventListener('moonlit-liked-changed', onChanged);
    return () => window.removeEventListener('moonlit-liked-changed', onChanged);
  }, []);

  // Fetch upcoming info from TMDB for liked items
  useEffect(() => {
    if (likedItems.length === 0) return;
    refreshUpcoming(likedItems).then(setUpcoming);
  }, [likedItems]);

  // Watchlist from Supabase + watch progress
  const { data, isLoading } = useQuery({
    queryKey: ['library', currentProfile?.id],
    queryFn: async () => {
      const [items, progress] = await Promise.all([
        getLibrary(currentProfile!.id),
        getWatchProgress(currentProfile!.id),
      ]);
      const progressMap: Record<string, number> = {};
      for (const p of progress) {
        if (p.duration_seconds > 0 && !p.completed) {
          const baseId = decodeURIComponent(p.media_id).split(':')[0];
          const frac = p.position_seconds / p.duration_seconds;
          if (frac > 0.02) progressMap[baseId] = frac;
        }
      }
      return { items, progressMap };
    },
    enabled: !!currentProfile,
  });

  const watchlist = data?.items ?? [];
  const progressMap = data?.progressMap ?? {};

  const filteredWatchlist = watchlistFilter === 'all'
    ? watchlist : watchlist.filter(i => i.media_type === watchlistFilter);

  // Liked: separate upcoming from non-upcoming
  const upcomingItems = likedItems.filter(i => upcoming[i.mediaId]);
  const availableLiked = likedItems.filter(i => !upcoming[i.mediaId]);
  const filteredLiked = likedFilter === 'all'
    ? availableLiked : availableLiked.filter(i => i.mediaType === likedFilter);

  async function handleRemoveWatchlist(mediaId: string, mediaType: string) {
    if (!currentProfile) return;
    await toggleLib(currentProfile.id, mediaId, mediaType);
    queryClient.invalidateQueries({ queryKey: ['library', currentProfile.id] });
  }

  return (
    <Sidebar>
      <div className="px-5 pt-24 pb-16 max-w-screen-xl mx-auto">

        {/* ── WATCHLIST ── */}
        <SectionHeader
          title="Watchlist"
          count={watchlist.length}
          icon={
            <svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 text-white/70">
              <path d="M6.32 2.577a49.255 49.255 0 0111.36 0c1.497.174 2.57 1.46 2.57 2.93V21a.75.75 0 01-1.085.67L12 18.089l-7.165 3.583A.75.75 0 013.75 21V5.507c0-1.47 1.073-2.756 2.57-2.93z"/>
            </svg>
          }
        />

        {isLoading ? (
          <div className="flex items-center justify-center py-16">
            <div className="animate-spin rounded-full h-6 w-6 border-2 border-moonlit-accent border-t-transparent" />
          </div>
        ) : watchlist.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-white/35">
            <svg viewBox="0 0 24 24" fill="currentColor" className="w-10 h-10 mb-3 opacity-40">
              <path d="M6.32 2.577a49.255 49.255 0 0111.36 0c1.497.174 2.57 1.46 2.57 2.93V21a.75.75 0 01-1.085.67L12 18.089l-7.165 3.583A.75.75 0 013.75 21V5.507c0-1.47 1.073-2.756 2.57-2.93z"/>
            </svg>
            <p className="text-sm text-white/50">Nothing saved yet</p>
            <p className="text-xs mt-1 text-white/25">Tap the bookmark on any title</p>
          </div>
        ) : (
          <>
            <FilterChips value={watchlistFilter} onChange={setWatchlistFilter} />
            {filteredWatchlist.length === 0 ? (
              <p className="text-sm text-white/35 py-8 text-center">
                No {watchlistFilter === 'movie' ? 'movies' : 'series'} saved
              </p>
            ) : (
              <div className="grid gap-3" style={POSTER_GRID}>
                {filteredWatchlist.map(item => (
                  <PosterCard
                    key={item.id}
                    to="/browse/$type/$id"
                    params={{ type: item.media_type, id: item.media_id }}
                    poster={item.poster}
                    name={item.name || item.media_id}
                    mediaType={item.media_type}
                    progress={progressMap[item.media_id]}
                    onRemove={e => { e.preventDefault(); handleRemoveWatchlist(item.media_id, item.media_type); }}
                  />
                ))}
              </div>
            )}
          </>
        )}

        {/* ── LIKED ── */}
        <SectionHeader
          title="Liked"
          count={availableLiked.length}
          icon={
            <svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 text-red-400">
              <path d="M11.645 20.91l-.007-.003-.022-.012a15.247 15.247 0 01-.383-.218 25.18 25.18 0 01-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0112 5.052 5.5 5.5 0 0116.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 01-4.244 3.17 15.247 15.247 0 01-.383.219l-.022.012-.007.004-.003.001a.752.752 0 01-.704 0l-.003-.001z"/>
            </svg>
          }
        />

        {availableLiked.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-white/35">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="w-10 h-10 mb-3 opacity-40">
              <path strokeLinecap="round" strokeLinejoin="round" d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12z"/>
            </svg>
            <p className="text-sm text-white/50">Nothing liked yet</p>
            <p className="text-xs mt-1 text-white/25">Tap ❤️ on any title to add it</p>
          </div>
        ) : (
          <>
            <FilterChips value={likedFilter} onChange={setLikedFilter} />
            {filteredLiked.length === 0 ? (
              <p className="text-sm text-white/35 py-8 text-center">
                No {likedFilter === 'movie' ? 'movies' : 'series'} liked
              </p>
            ) : (
              <div className="grid gap-3" style={POSTER_GRID}>
                {filteredLiked.map(item => (
                  <PosterCard
                    key={item.id}
                    to="/browse/$type/$id"
                    params={{ type: item.mediaType, id: item.mediaId }}
                    poster={item.poster}
                    name={item.name}
                    mediaType={item.mediaType}
                    onRemove={e => { e.preventDefault(); removeLiked(item.mediaId); setLikedItems(getLikedItems()); }}
                  />
                ))}
              </div>
            )}
          </>
        )}

        {/* ── UPCOMING ── */}
        {upcomingItems.length > 0 && (
          <>
            <SectionHeader
              title="Upcoming"
              count={upcomingItems.length}
              icon={
                <svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 text-moonlit-accent">
                  <path fillRule="evenodd" d="M6.75 2.25A.75.75 0 017.5 3v1.5h9V3A.75.75 0 0118 3v1.5h.75a3 3 0 013 3v11.25a3 3 0 01-3 3H5.25a3 3 0 01-3-3V7.5a3 3 0 013-3H6V3a.75.75 0 01.75-.75zm13.5 9a1.5 1.5 0 00-1.5-1.5H5.25a1.5 1.5 0 00-1.5 1.5v7.5a1.5 1.5 0 001.5 1.5h13.5a1.5 1.5 0 001.5-1.5v-7.5z" clipRule="evenodd"/>
                </svg>
              }
            />
            <div className="rounded-2xl bg-moonlit-surface border border-moonlit-border overflow-hidden">
              {upcomingItems.map((item, idx) => (
                <div key={item.id}>
                  {idx > 0 && <div className="h-px bg-white/[0.06] ml-16" />}
                  <Link to="/browse/$type/$id" params={{ type: item.mediaType, id: item.mediaId }}
                    className="flex items-center gap-3 px-4 py-3 hover:bg-white/[0.03] transition-colors">
                    <div className="w-11 h-16 rounded-lg overflow-hidden bg-moonlit-elevated shrink-0">
                      {item.poster
                        ? <img src={item.poster} alt={item.name} className="w-full h-full object-cover" loading="lazy" />
                        : <div className="w-full h-full bg-white/5" />}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-white truncate">{item.name}</p>
                      <p className="text-xs text-white/40 mt-0.5">{item.mediaType === 'series' ? 'Series' : 'Movie'}</p>
                    </div>
                    <div className="text-right shrink-0">
                      <span className="text-xs font-semibold text-moonlit-accent bg-moonlit-accent/10 px-2 py-1 rounded-lg">
                        {upcoming[item.mediaId]?.badge}
                      </span>
                    </div>
                    <svg className="w-3.5 h-3.5 text-white/20 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                      <path d="M9 18l6-6-6-6" strokeLinecap="round" strokeLinejoin="round"/>
                    </svg>
                  </Link>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </Sidebar>
  );
}
