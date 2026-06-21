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
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-moonlit-accent border-t-transparent" />
        </div>
      </Sidebar>
    );
  }

  if (isError || !data) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <p className="text-moonlit-muted text-sm">Failed to load folder.</p>
        </div>
      </Sidebar>
    );
  }

  const { folder, items } = data;
  const heroImage = folder.cover_image || null;

  return (
    <Sidebar>
      {/* Hero backdrop — matches iOS FolderScreen top image */}
      {heroImage && (
        <div className="-mt-14 relative overflow-hidden" style={{ height: '220px' }}>
          <img
            src={heroImage}
            alt=""
            className="absolute inset-0 w-full h-full object-cover object-center"
          />
          <div className="absolute inset-0 bg-gradient-to-b from-black/20 via-transparent to-[#080808]" />
        </div>
      )}

      <div className={`px-4 pb-12 max-w-screen-xl mx-auto ${heroImage ? 'pt-4' : 'pt-24'}`}>
        <div className="mb-5">
          <h1 className="text-2xl font-bold text-white">{folder.name}</h1>
          <p className="text-sm text-moonlit-muted mt-1">{items.length} titles</p>
        </div>

        {items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-32 text-moonlit-muted">
            <p className="text-sm">No content in this folder.</p>
            <p className="text-xs mt-1 opacity-60">Check the catalog configuration in the admin panel.</p>
          </div>
        ) : (
          <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))' }}>
            {items.map(item => (
              <Link key={item.id} to="/browse/$type/$id" params={{ type: item.type, id: item.id }}
                className="group cursor-pointer">
                <div className="relative rounded-xl overflow-hidden bg-moonlit-elevated mb-1.5" style={{ aspectRatio: '2/3' }}>
                  {item.poster ? (
                    <img src={item.poster} alt={item.name}
                      className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                      loading="lazy" />
                  ) : (
                    <div className="absolute inset-0 flex items-center justify-center">
                      <span className="text-moonlit-muted text-xs text-center px-2">{item.name}</span>
                    </div>
                  )}
                  <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                    <div className="w-9 h-9 rounded-full bg-white/20 backdrop-blur-sm flex items-center justify-center">
                      <svg viewBox="0 0 24 24" fill="white" className="w-4 h-4 ml-0.5">
                        <polygon points="6,4 20,12 6,20" />
                      </svg>
                    </div>
                  </div>
                  {item.imdbRating && (
                    <span className="absolute top-1.5 right-1.5 bg-black/70 backdrop-blur-sm text-[10px] font-medium px-1.5 py-0.5 rounded text-white/90">
                      ★ {item.imdbRating}
                    </span>
                  )}
                </div>
                <p className="text-xs font-medium text-white/80 truncate group-hover:text-white transition-colors">
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
