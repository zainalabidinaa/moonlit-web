import { useEffect, useState, useCallback } from 'react';
import { Bookmark, Heart, Calendar } from 'lucide-react';
import { useNavigate } from '@/shell/Shell';
import { useAuth } from '@/app/AuthProvider';
import { getLibrary, getWatchProgress, getLikedItems, toggleLiked, toggleLibrary, type LikedItem } from '@/lib/services/api';
import type { LibraryItem, WatchProgressEntry } from '@/lib/types';
import PosterCard from '@/components/PosterCard';
import CategoryPills from '@/components/CategoryPills';

type MediaFilter = 'all' | 'movies' | 'series';

const FILTERS = [
  { id: 'all', label: 'All' },
  { id: 'movies', label: 'Movies' },
  { id: 'series', label: 'Series' },
];

export function LibraryScreen() {
  const { navigateTo } = useNavigate();
  const { currentProfile } = useAuth();

  const [watchlist, setWatchlist] = useState<LibraryItem[]>([]);
  const [liked, setLiked] = useState<LikedItem[]>([]);
  const [progressMap, setProgressMap] = useState<Map<string, number>>(new Map());
  const [loading, setLoading] = useState(true);
  const [watchlistFilter, setWatchlistFilter] = useState<MediaFilter>('all');
  const [likedFilter, setLikedFilter] = useState<MediaFilter>('all');

  const loadData = useCallback(async () => {
    if (!currentProfile) return;
    setLoading(true);
    try {
      const [lib, prog, likedItems] = await Promise.all([
        getLibrary(currentProfile.id),
        getWatchProgress(currentProfile.id),
        getLikedItems(currentProfile.id),
      ]);
      setWatchlist(lib);
      const map = new Map<string, number>();
      for (const p of prog) {
        const frac = p.duration_seconds > 0 ? p.position_seconds / p.duration_seconds : 0;
        map.set(p.media_id, frac);
      }
      setProgressMap(map);
      setLiked(likedItems);
    } catch {}
    setLoading(false);
  }, [currentProfile]);

  useEffect(() => { loadData(); }, [loadData]);

  const filteredWatchlist = watchlist.filter((item) => {
    if (watchlistFilter === 'movies') return item.media_type === 'movie';
    if (watchlistFilter === 'series') return item.media_type !== 'movie';
    return true;
  });

  const filteredLiked = liked.filter((item) => {
    if (likedFilter === 'movies') return item.media_type === 'movie';
    if (likedFilter === 'series') return item.media_type !== 'movie';
    return true;
  });

  const handleOpenMedia = (mediaId: string, mediaType: string, name?: string, poster?: string) => {
    navigateTo(mediaType, mediaId);
  };

  const handleRemoveWatchlist = async (item: LibraryItem) => {
    if (!currentProfile) return;
    await toggleLibrary(currentProfile.id, item.media_id, item.media_type, item.name, item.poster);
    setWatchlist((prev) => prev.filter((i) => i.id !== item.id));
  };

  const handleRemoveLiked = async (item: LikedItem) => {
    if (!currentProfile) return;
    await toggleLiked(currentProfile.id, item.media_id, item.media_type, item.name, item.poster);
    setLiked((prev) => prev.filter((i) => i.id !== item.id));
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-moonlit-bg pt-24 px-6">
        <div className="flex justify-center py-20">
          <div className="inline-block h-6 w-6 rounded-full border-2 border-white/20 border-t-white/60 animate-spin" />
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-moonlit-bg">
      <div className="pt-24 pb-12">
        <SectionHeader
          icon={<Bookmark size={16} className="text-moonlit-gold" />}
          title="Watchlist"
          count={watchlist.length}
        />
        <div className="px-5 pb-3">
          <CategoryPills
            categories={FILTERS}
            selected={watchlistFilter}
            onSelect={(id) => setWatchlistFilter(id as MediaFilter)}
          />
        </div>

        {filteredWatchlist.length === 0 ? (
          <EmptyState icon={<Bookmark size={28} />} message="Nothing bookmarked yet" />
        ) : (
          <div className="px-4 grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-x-3 gap-y-5">
            {filteredWatchlist.map((item) => (
              <WatchlistCard
                key={item.id}
                item={item}
                progress={progressMap.get(item.media_id) ?? 0}
                onClick={() => handleOpenMedia(item.media_id, item.media_type, item.name, item.poster)}
                onRemove={() => handleRemoveWatchlist(item)}
              />
            ))}
          </div>
        )}

        <div className="mt-10">
          <SectionHeader
            icon={<Heart size={16} className="text-moonlit-gold" />}
            title="Liked"
            count={filteredLiked.length}
          />
          <div className="px-5 pb-3">
            <CategoryPills
              categories={FILTERS}
              selected={likedFilter}
              onSelect={(id) => setLikedFilter(id as MediaFilter)}
            />
          </div>

          {filteredLiked.length === 0 ? (
            <EmptyState icon={<Heart size={28} />} message="Nothing liked yet" />
          ) : (
            <div className="px-4 grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-x-3 gap-y-5">
              {filteredLiked.map((item) => (
                <LikedCard
                  key={item.id}
                  item={item}
                  onClick={() => handleOpenMedia(item.media_id, item.media_type, item.name, item.poster)}
                  onRemove={() => handleRemoveLiked(item)}
                />
              ))}
            </div>
          )}
        </div>

        <div className="mt-10">
          <SectionHeader
            icon={<Calendar size={16} className="text-moonlit-gold" />}
            title="Upcoming"
            count={0}
          />
          <EmptyState icon={<Calendar size={28} />} message="Coming soon" />
        </div>
      </div>
    </div>
  );
}

function SectionHeader({ icon, title, count }: { icon: React.ReactNode; title: string; count: number }) {
  return (
    <div className="flex items-center gap-2.5 px-5 pt-6 pb-3">
      {icon}
      <h2 className="text-[19px] font-bold text-white">{title}</h2>
      <span className="text-[14px] font-semibold text-white/50">{count}</span>
    </div>
  );
}

function EmptyState({ icon, message }: { icon: React.ReactNode; message: string }) {
  return (
    <div className="flex flex-col items-center gap-2 py-8 text-white/40">
      {icon}
      <span className="text-[14px]">{message}</span>
    </div>
  );
}

function WatchlistCard({
  item,
  progress,
  onClick,
  onRemove,
}: {
  item: LibraryItem;
  progress: number;
  onClick: () => void;
  onRemove: () => void;
}) {
  return (
    <div className="group relative">
      <div className="relative overflow-hidden rounded-ml-ctl bg-moonlit-elevated" style={{ aspectRatio: '2/3' }}>
        {item.poster ? (
          <img
            src={item.poster}
            alt={item.name ?? item.media_id}
            className="w-full h-full object-cover"
            onClick={onClick}
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-white/20" onClick={onClick}>
            {item.media_type === 'series' ? (
              <svg className="w-8 h-8" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <rect x="2" y="3" width="20" height="14" rx="2" />
                <path d="M8 21h8M12 17v4" />
              </svg>
            ) : (
              <svg className="w-8 h-8" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" />
              </svg>
            )}
          </div>
        )}

        {progress > 0.02 && (
          <div className="absolute bottom-0 left-0 right-0 h-[3px] bg-white/20">
            <div
              className="h-full bg-white transition-all"
              style={{ width: `${Math.min(progress * 100, 100)}%` }}
            />
          </div>
        )}
      </div>

      <p className="text-[13px] font-medium text-white/85 line-clamp-2 mt-1.5 leading-snug">
        {item.name ?? item.media_id}
      </p>

      <button
        onClick={(e) => { e.stopPropagation(); onRemove(); }}
        className="absolute top-1.5 right-1.5 w-6 h-6 rounded-full bg-black/60 border border-white/10 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity text-white/60 hover:text-white"
        aria-label="Remove from watchlist"
      >
        <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
}

function LikedCard({
  item,
  onClick,
  onRemove,
}: {
  item: LikedItem;
  onClick: () => void;
  onRemove: () => void;
}) {
  return (
    <div className="group relative">
      <div className="relative overflow-hidden rounded-ml-ctl bg-moonlit-elevated" style={{ aspectRatio: '2/3' }}>
        {item.poster ? (
          <img
            src={item.poster}
            alt={item.name}
            className="w-full h-full object-cover"
            onClick={onClick}
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-white/20" onClick={onClick}>
            {item.media_type === 'series' ? (
              <svg className="w-8 h-8" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <rect x="2" y="3" width="20" height="14" rx="2" />
                <path d="M8 21h8M12 17v4" />
              </svg>
            ) : (
              <svg className="w-8 h-8" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" />
              </svg>
            )}
          </div>
        )}
      </div>

      <p className="text-[13px] font-medium text-white/85 line-clamp-2 mt-1.5 leading-snug">
        {item.name}
      </p>

      <button
        onClick={(e) => { e.stopPropagation(); onRemove(); }}
        className="absolute top-1.5 right-1.5 w-6 h-6 rounded-full bg-black/60 border border-white/10 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity text-white/60 hover:text-white"
        aria-label="Remove from liked"
      >
        <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
}
