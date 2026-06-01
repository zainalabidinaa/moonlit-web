import { useQuery } from '@tanstack/react-query';
import { useParams, Link } from '@tanstack/react-router';
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyRouteParams = any;
import { Sidebar } from '@/components/Sidebar';
import { MetaPreview } from '@/lib/types';
import { getFolder, getSystemAddon } from '@/lib/services/api';
import { fetchCatalog } from '@/lib/stremio';

export default function FolderDetailPage() {
  const { folderId } = useParams({ strict: false }) as AnyRouteParams;

  const { data, isLoading, isError } = useQuery({
    queryKey: ['folder', folderId],
    queryFn: async () => {
      const [folderData, addonData] = await Promise.all([
        getFolder(folderId),
        getSystemAddon(),
      ]);

      if (!folderData) throw new Error('Folder not found');
      if (!addonData?.manifest_url) throw new Error('No system addon configured');

      const baseUrl = addonData.manifest_url.replace('/manifest.json', '');
      const catalogs = folderData.folder_catalogs || [];

      const results = await Promise.allSettled(
        catalogs.map(c => fetchCatalog(baseUrl, c.media_type, c.catalog_id))
      );

      const merged: MetaPreview[] = [];
      const seen = new Set<string>();
      for (const result of results) {
        if (result.status === 'fulfilled') {
          for (const item of result.value) {
            if (!seen.has(item.id)) { seen.add(item.id); merged.push(item); }
          }
        }
      }

      return { folder: folderData, items: merged };
    },
    staleTime: 5 * 60 * 1000,
  });

  if (isLoading) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" />
        </div>
      </Sidebar>
    );
  }

  if (isError || !data) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <p className="text-luna-muted text-sm">Failed to load folder.</p>
        </div>
      </Sidebar>
    );
  }

  const { folder, items } = data;

  return (
    <Sidebar>
      <div className="px-6 pt-24 pb-12">
        <div className="mb-8">
          <h1 className="text-2xl font-bold text-white">{folder.name}</h1>
          <p className="text-sm text-luna-muted mt-1">{items.length} titles</p>
        </div>

        {items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-32 text-luna-muted">
            <p className="text-sm">No content in this folder.</p>
            <p className="text-xs mt-1 opacity-60">Check the catalog configuration in the admin panel.</p>
          </div>
        ) : (
          <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-7 gap-3">
            {items.map(item => (
              <Link key={item.id} to="/browse/$type/$id" params={{ type: item.type, id: item.id }}
                className="media-card group">
                <div className="media-card-inner h-52 mb-2">
                  {item.poster ? (
                    <img src={item.poster} alt={item.name}
                      className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                      loading="lazy" />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center">
                      <span className="text-luna-muted text-xs text-center px-2">{item.name}</span>
                    </div>
                  )}
                  <div className="media-card-overlay group-hover:opacity-100" />
                  {item.imdbRating && (
                    <span className="absolute top-2 right-2 bg-black/70 backdrop-blur-sm text-xs font-medium px-1.5 py-0.5 rounded text-white/90">
                      ★ {item.imdbRating}
                    </span>
                  )}
                </div>
                <p className="text-xs text-luna-muted truncate group-hover:text-white transition-colors duration-200">
                  {item.name}
                </p>
              </Link>
            ))}
          </div>
        )}
      </div>
    </Sidebar>
  );
}
