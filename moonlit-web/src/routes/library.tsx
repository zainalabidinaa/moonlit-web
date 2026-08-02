import { useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from '@tanstack/react-router';

import { useAuth } from '@/app/AuthProvider';
import { MediaRow } from '@/components/MediaRow';
import { getLikedItems, refreshUpcoming, removeLiked, type LikedItem, type UpcomingInfo } from '@/lib/liked';
import { getUserWatchlist, removeUserWatchlistItem } from '@/lib/services/api';
import type { MetaPreview, UserList, UserListItem } from '@/lib/types';
import { useArtworkPreferences } from './catalog-data';

type MediaFilter = 'all' | 'movie' | 'series';

function asPreview(item: UserListItem): MetaPreview {
  return {
    id: item.media_id,
    type: item.media_type,
    name: item.name || item.media_id,
    poster: item.poster,
  };
}

function likedPreview(item: LikedItem, upcoming?: UpcomingInfo): MetaPreview {
  return {
    id: item.mediaId,
    type: item.mediaType,
    name: item.name,
    poster: item.poster,
    banner: upcoming?.backdrop,
    releaseInfo: upcoming?.badge,
  };
}

export default function LibraryPage() {
  const { currentProfile } = useAuth();
  const queryClient = useQueryClient();
  const artworkPreferences = useArtworkPreferences(currentProfile?.id);
  const [filter, setFilter] = useState<MediaFilter>('all');
  const [likedFilter, setLikedFilter] = useState<MediaFilter>('all');
  const [likedItems, setLikedItems] = useState<LikedItem[]>(() => getLikedItems());
  const [upcoming, setUpcoming] = useState<Record<string, UpcomingInfo>>({});
  const [mutationError, setMutationError] = useState<string | null>(null);
  const [optimisticallyRemoved, setOptimisticallyRemoved] = useState<Set<string>>(() => new Set());
  const queryKey = ['user-watchlist', currentProfile?.id ?? 'guest'] as const;

  useEffect(() => {
    const handleLikedChange = () => setLikedItems(getLikedItems());
    window.addEventListener('moonlit-liked-changed', handleLikedChange);
    return () => window.removeEventListener('moonlit-liked-changed', handleLikedChange);
  }, []);

  useEffect(() => {
    if (likedItems.length === 0) return;
    void refreshUpcoming(likedItems).then(setUpcoming);
  }, [likedItems]);

  const watchlistQuery = useQuery({
    queryKey,
    queryFn: () => getUserWatchlist(currentProfile!.id),
    enabled: Boolean(currentProfile),
    staleTime: 2 * 60 * 1000,
  });

  const removal = useMutation({
    mutationFn: removeUserWatchlistItem,
    onMutate: async itemId => {
      setMutationError(null);
      await queryClient.cancelQueries({ queryKey });
      const previous = queryClient.getQueryData<UserList>(queryKey);
      const removed = previous?.items.find(item => item.id === itemId);
      queryClient.setQueryData<UserList>(queryKey, current => current ? {
        ...current,
        items: current.items.filter(item => item.id !== itemId),
      } : current);
      return { previous, removed };
    },
    onError: (_error, _itemId, context) => {
      if (context?.previous) queryClient.setQueryData(queryKey, context.previous);
      setOptimisticallyRemoved(current => {
        const next = new Set(current);
        next.delete(_itemId);
        return next;
      });
      setMutationError(`${context?.removed?.name || 'That title'} was not removed. Try again.`);
    },
    onSuccess: (_data, itemId) => {
      setOptimisticallyRemoved(current => {
        const next = new Set(current);
        next.delete(itemId);
        return next;
      });
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey }),
  });

  const watchlist = (watchlistQuery.data?.items ?? [])
    .filter(item => !optimisticallyRemoved.has(item.id));
  const visibleItems = filter === 'all'
    ? watchlist
    : watchlist.filter(item => item.media_type === filter);
  const upcomingItems = likedItems.filter(item => upcoming[item.mediaId]);
  const availableLiked = likedItems.filter(item => !upcoming[item.mediaId]);
  const visibleLiked = likedFilter === 'all'
    ? availableLiked
    : availableLiked.filter(item => item.mediaType === likedFilter);

  return (
    <div className="watchlist-page relative mx-auto min-h-[calc(100vh-56px)] max-w-[1600px] overflow-hidden px-4 pb-20 pt-16 sm:px-6 md:px-14">
      <div aria-hidden="true" className="watchlist-warm-ambient" />
      <header className="relative mb-10 max-w-2xl">
        <p className="type-label mb-2 text-moonlit-text-tertiary">Saved for later</p>
        <h1 className="type-title-lg text-white">Watchlist</h1>
        <p className="mt-3 text-sm leading-relaxed text-moonlit-text-secondary">
          Titles saved to this profile stay together across Moonlit devices.
        </p>
      </header>

      {watchlistQuery.isLoading && (
        <div role="status" className="relative flex min-h-64 items-center justify-center gap-3 text-sm text-moonlit-text-secondary">
          <span aria-hidden="true" className="h-6 w-6 animate-spin-arc rounded-full border-2 border-white/15 border-t-white" />
          Loading your watchlist…
        </div>
      )}

      {watchlistQuery.isError && (
        <div role="alert" className="surface-card relative max-w-xl p-6">
          <h2 className="type-title-sm text-white">Your watchlist could not be loaded</h2>
          <p className="mt-2 text-sm text-moonlit-text-secondary">Check your connection, then try the request again.</p>
          <button type="button" onClick={() => watchlistQuery.refetch()} className="btn-primary mt-5 min-h-11">
            Try again
          </button>
        </div>
      )}

      {!watchlistQuery.isLoading && !watchlistQuery.isError && watchlist.length === 0 && (
        <section className="surface-card relative flex min-h-72 max-w-2xl flex-col items-start justify-center p-8 sm:p-10">
          <span aria-hidden="true" className="mb-5 flex h-12 w-12 items-center justify-center rounded-full bg-white/10 text-white/75">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" className="h-6 w-6">
              <path d="M6 4.8A1.8 1.8 0 0 1 7.8 3h8.4A1.8 1.8 0 0 1 18 4.8V21l-6-3-6 3V4.8Z" strokeLinejoin="round" />
            </svg>
          </span>
          <h2 className="type-title-sm text-white">Your watchlist is empty</h2>
          <p className="mt-2 max-w-md text-sm leading-relaxed text-moonlit-text-secondary">
            Save a movie or series from its detail page and it will appear here.
          </p>
          <div className="mt-6 flex flex-wrap gap-3">
            <Link to="/movies" className="btn-primary inline-flex min-h-11 items-center">Browse movies</Link>
            <Link to="/series" className="btn-secondary inline-flex min-h-11 items-center">Browse series</Link>
          </div>
        </section>
      )}

      {!watchlistQuery.isLoading && !watchlistQuery.isError && watchlist.length > 0 && (
        <div className="relative">
          <div role="group" aria-label="Filter watchlist" className="mb-8 flex gap-2 overflow-x-auto py-1 scrollbar-hide">
            {(['all', 'movie', 'series'] as MediaFilter[]).map(value => {
              const label = value === 'all' ? 'All' : value === 'movie' ? 'Movies' : 'Series';
              return (
                <button
                  key={value}
                  type="button"
                  aria-pressed={filter === value}
                  onClick={() => setFilter(value)}
                  className={`category-pill min-h-11 ${filter === value ? 'category-pill-active' : 'category-pill-idle'}`}
                >
                  {label}
                </button>
              );
            })}
          </div>

          {mutationError && (
            <p role="alert" className="glass-panel mb-6 max-w-xl rounded-ml-ctl px-4 py-3 text-sm text-white/80">
              {mutationError}
            </p>
          )}

          {visibleItems.length > 0 ? (
            <MediaRow
              title="Saved titles"
              items={visibleItems.map(asPreview)}
              artworkPreferences={artworkPreferences}
              onRemove={preview => {
                const item = watchlist.find(saved => saved.media_id === preview.id);
                if (item) {
                  setOptimisticallyRemoved(current => new Set(current).add(item.id));
                  removal.mutate(item.id);
                }
              }}
            />
          ) : (
            <div className="surface-card max-w-lg p-6">
              <h2 className="type-title-sm text-white">No {filter === 'movie' ? 'movies' : 'series'} saved</h2>
              <p className="mt-2 text-sm text-moonlit-text-secondary">Choose another filter or save a title from its detail page.</p>
            </div>
          )}
        </div>
      )}

      <section aria-labelledby="liked-heading" className="relative mt-12">
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <h2 id="liked-heading" className="text-xl font-bold text-white">Liked</h2>
          {availableLiked.length > 0 && (
            <div role="group" aria-label="Filter liked titles" className="flex gap-2 overflow-x-auto py-1 scrollbar-hide">
              {(['all', 'movie', 'series'] as MediaFilter[]).map(value => (
                <button
                  key={value}
                  type="button"
                  aria-pressed={likedFilter === value}
                  onClick={() => setLikedFilter(value)}
                  className={`category-pill min-h-11 ${likedFilter === value ? 'category-pill-active' : 'category-pill-idle'}`}
                >
                  {value === 'all' ? 'All' : value === 'movie' ? 'Movies' : 'Series'}
                </button>
              ))}
            </div>
          )}
        </div>
        {availableLiked.length === 0 ? (
          <p className="text-sm text-moonlit-text-tertiary">Titles you like will collect here.</p>
        ) : visibleLiked.length > 0 ? (
          <MediaRow
            title="Liked titles"
            items={visibleLiked.map(item => likedPreview(item))}
            artworkPreferences={artworkPreferences}
            removeFromLabel="liked titles"
            onRemove={preview => removeLiked(preview.id)}
          />
        ) : (
          <p className="surface-card max-w-lg p-6 text-sm text-moonlit-text-secondary">No titles match this filter.</p>
        )}
      </section>

      {upcomingItems.length > 0 && (
        <div className="relative mt-8">
          <MediaRow
            title="Upcoming"
            variant="cinematic"
            items={upcomingItems.map(item => likedPreview(item, upcoming[item.mediaId]))}
            artworkPreferences={artworkPreferences}
            removeFromLabel="upcoming titles"
            onRemove={preview => removeLiked(preview.id)}
          />
        </div>
      )}
    </div>
  );
}
