import { useQuery } from '@tanstack/react-query';

import { useAuth } from '@/app/AuthProvider';
import { MediaRow } from '@/components/MediaRow';
import { loadCollections } from '@/lib/collections/repository';
import { TMDB_API_KEY } from '@/lib/supabase';

export function CatalogDestination({ mediaType, title }: { mediaType: 'movie' | 'series'; title: string }) {
  const { addons, currentProfile } = useAuth();
  const { data: rows = [], isLoading, isError } = useQuery({
    queryKey: ['catalog-destination', mediaType, currentProfile?.id ?? 'guest', addons.map(addon => addon.id).join(',')],
    queryFn: () => loadCollections(addons, TMDB_API_KEY),
    enabled: addons.length > 0,
    staleTime: 5 * 60 * 1000,
  });

  const matchingRows = rows
    .map(row => ({ ...row, items: row.items.filter(item => item.type === mediaType) }))
    .filter(row => row.items.length > 0);

  return (
    <div className="mx-auto min-h-[calc(100vh-56px)] max-w-[1600px] px-4 pb-16 pt-10 sm:px-6 md:px-14">
      <header className="mb-10">
        <p className="type-label mb-2 text-moonlit-text-tertiary">Browse</p>
        <h1 className="type-title-lg text-white">{title}</h1>
      </header>

      {isLoading && (
        <div role="status" className="flex items-center gap-3 text-sm text-moonlit-text-secondary">
          <span className="h-5 w-5 animate-spin-arc rounded-full border-2 border-white/15 border-t-white" />
          Loading {title.toLowerCase()}…
        </div>
      )}
      {isError && <p role="alert" className="text-sm text-moonlit-text-secondary">This catalog could not be loaded. Try again shortly.</p>}
      {!isLoading && !isError && matchingRows.length === 0 && (
        <div className="surface-card max-w-xl p-6">
          <h2 className="type-title-sm text-white">No {title.toLowerCase()} available</h2>
          <p className="mt-2 text-sm text-moonlit-text-secondary">Install or enable a catalog addon to populate this page.</p>
        </div>
      )}
      {matchingRows.map(row => (
        <MediaRow key={row.id} title={row.title} titleLogo={row.titleLogo} items={row.items} />
      ))}
    </div>
  );
}
