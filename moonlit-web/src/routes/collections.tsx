import { useQuery } from '@tanstack/react-query';
import { useParams, Link } from '@tanstack/react-router';
import { useAuth } from '@/app/AuthProvider';
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyRouteParams = any;
import { Sidebar } from '@/components/Sidebar';
import { MetaPreview } from '@/lib/types';
import { getFolder, getSystemAddon } from '@/lib/services/api';
import { fetchCatalog } from '@/lib/stremio';
import { TMDB_API_KEY } from '@/lib/supabase';
import { resolveFolderFromOrganizer, getCurrentOrganized, loadCollections } from '@/lib/collections/repository';
import { resolveRawSource, deduplicateItems } from '@/lib/collections/builder';
import { fetchCatalog as fetchCollectionCatalog } from '@/lib/collections/fetcher';
import { useState } from 'react';

export default function FolderDetailPage() {
  const { folderId } = useParams({ strict: false }) as AnyRouteParams;
  const { addons } = useAuth();
  const [imgError, setImgError] = useState<Record<string, boolean>>({});

  const { data, isLoading, isError } = useQuery({
    queryKey: ['folder', folderId, addons.map(a => a.id).join(',')],
    queryFn: async () => {
      // Ensure organizer engine is loaded
      let resolved = resolveFolderFromOrganizer(folderId);
      if (!resolved && !getCurrentOrganized()) {
        await loadCollections(addons, TMDB_API_KEY);
        resolved = resolveFolderFromOrganizer(folderId);
      }

      if (resolved) {
        let allItems: MetaPreview[] = [];

        // Fetch raw sources first (TMDB, Trakt, etc.)
        for (const src of resolved.sources) {
          const items = await resolveRawSource(src, addons, TMDB_API_KEY);
          allItems = deduplicateItems([...allItems, ...items]);
        }

        // Fetch addon catalog sources
        for (const cat of resolved.catalogs) {
          // Try exact catalog ID match first
          let baseURL: string | undefined;
          let addon = addons.find(a =>
            a.transportUrl && a.catalogs?.some(ac => ac.id === cat.catalogId || ac.type === cat.catalogId)
          );
          baseURL = addon?.transportUrl;

          // Fallback: use first addon with catalog resource
          if (!baseURL) {
            addon = addons.find(a =>
              a.transportUrl && a.resources?.some(r => (typeof r === 'string' ? r : r.name) === 'catalog')
            );
            baseURL = addon?.transportUrl;
          }

          if (!baseURL) continue;

          const mediaTypes = cat.mediaType === 'all' ? ['movie', 'series'] : [cat.mediaType || 'movie'];
          for (const mt of mediaTypes) {
            const items = await fetchCollectionCatalog({
              baseURL,
              type: mt,
              id: cat.catalogId,
              extras: cat.extras,
            });
            allItems = deduplicateItems([...allItems, ...items]);
          }
        }

        return {
          folder: {
            id: resolved.id,
            name: resolved.name,
            cover_image: resolved.coverImage || null,
            title_logo: resolved.titleLogo || null,
            hero_backdrop: resolved.heroBackdrop || null,
            hero_video_url: resolved.heroVideoUrl || null,
            hide_title: resolved.hideTitle || false,
            tile_shape: resolved.tileShape || null,
          } as ResolvedFolderData,
          items: allItems,
          source: 'organizer' as const,
        };
      }

      // Fall back to legacy Supabase folder
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

      return {
        folder: folderData,
        items: merged,
        source: 'legacy' as const,
      };
    },
    staleTime: 5 * 60 * 1000,
    enabled: addons.length > 0,
  });

  if (isLoading) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <div className="flex gap-2">
            {[1, 2, 3].map(i => (
              <div key={i} className="w-2.5 h-2.5 rounded-full bg-white/20 animate-pulse" style={{ animationDelay: `${i * 150}ms` }} />
            ))}
          </div>
        </div>
      </Sidebar>
    );
  }

  if (isError || !data) {
    return (
      <Sidebar>
        <div className="flex flex-col items-center justify-center min-h-screen text-moonlit-muted px-4">
          <p className="text-sm font-medium">This folder is no longer available</p>
          <p className="text-xs mt-1 opacity-60">The collection configuration may have changed.</p>
        </div>
      </Sidebar>
    );
  }

  const { folder, items } = data;
  const heroImage = folder.hero_backdrop || folder.cover_image || null;

  const isLandscapeFolder = items.filter(i => i.banner || i.poster).length > 0
    ? items.filter(i => (i.posterShape || 'poster') === 'landscape' || i.type === 'folder').length > items.length * 0.5
    : false;

  return (
    <Sidebar>
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
          {folder.title_logo ? (
            <img
              src={folder.title_logo}
              alt={folder.name}
              className="h-8 object-contain object-left"
              onError={(e) => { (e.target as HTMLElement).style.display = 'none'; }}
            />
          ) : !folder.hide_title ? (
            <h1 className="text-2xl font-bold text-white">{folder.name}</h1>
          ) : null}
          {items.length > 0 && (
            <p className="text-xs text-moonlit-muted mt-1">{items.length} titles</p>
          )}
        </div>

        {items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-32 text-moonlit-muted">
            <p className="text-sm">The provider returned no items</p>
            <p className="text-xs mt-1 opacity-60">This folder may need additional addons configured.</p>
          </div>
        ) : (
          <div
            className="grid gap-3"
            style={{
              gridTemplateColumns: isLandscapeFolder
                ? 'repeat(auto-fill, minmax(290px, 1fr))'
                : 'repeat(auto-fill, minmax(172px, 1fr))',
            }}
          >
            {items.map(item => {
              const isFolderItem = item.type === 'folder';
              const showLandscape = isLandscapeFolder || isFolderItem;
              const aspectRatio = showLandscape ? '16/9' : '2/3';

              return (
                <Link
                  key={item.id}
                  to={isFolderItem ? '/collections/$folderId' : '/browse/$type/$id'}
                  params={isFolderItem ? { folderId: item.id } : { type: item.type, id: item.id }}
                  className="group cursor-pointer"
                >
                  <div className="relative rounded-ml-card overflow-hidden bg-moonlit-elevated mb-1.5 transition-shadow duration-300 group-hover:shadow-lg group-hover:shadow-black/30 group-hover:ring-1 group-hover:ring-white/10"
                    style={{ aspectRatio }}
                  >
                    {(isFolderItem ? (item.banner || item.poster) : item.poster) && !imgError[item.id] ? (
                      <img
                        src={isFolderItem ? (item.banner || item.poster) : item.poster}
                        alt={item.name}
                        className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-[1.025]"
                        loading="lazy"
                        onError={() => setImgError(prev => ({ ...prev, [item.id]: true }))}
                      />
                    ) : (
                      <div className="absolute inset-0 flex items-center justify-center">
                        <span className="text-xs text-white/20 text-center px-2 line-clamp-2">{item.name}</span>
                      </div>
                    )}
                    {item.imdbRating && (
                      <span className="rating-badge absolute top-1.5 right-1.5">
                        ★ {item.imdbRating}
                      </span>
                    )}
                  </div>
                  <p className="text-[13px] font-medium text-white/80 truncate group-hover:text-white transition-colors leading-tight">
                    {item.name}
                  </p>
                  {item.releaseInfo && (
                    <p className="text-[11px] text-white/30 mt-0.5 leading-tight">{item.releaseInfo}</p>
                  )}
                </Link>
              );
            })}
          </div>
        )}
      </div>
    </Sidebar>
  );
}

interface ResolvedFolderData {
  id: string;
  name: string;
  cover_image: string | null;
  title_logo: string | null;
  hero_backdrop: string | null;
  hero_video_url: string | null;
  hide_title: boolean;
  tile_shape: string | null;
}
