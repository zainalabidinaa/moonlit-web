import { useState } from 'react';
import { useParams, useNavigate } from '@tanstack/react-router';
import { useQuery } from '@tanstack/react-query';

import { useAuth } from '@/app/AuthProvider';
import { MediaRow } from '@/components/MediaRow';
import { FolderTile } from '@/components/FolderTile';
import { getCurrentOrganized, loadCollections } from '@/lib/collections/repository';
import { browseRails, genres, sections, type LoadedBrowseRail } from '@/lib/collections/genre-catalog';
import { resolveBrowseRails } from '@/lib/collections/genre-hub-resolver';
import { discoverCreativeRails, discoverGenreRails } from '@/lib/collections/tmdb-discover';
import { TMDB_API_KEY } from '@/lib/supabase';
import { useArtworkPreferences } from './catalog-data';
import type { Folder } from '@/lib/types';

type MediaKind = 'movie' | 'series';

function toFolder(id: string, name: string, sortOrder: number, coverImage?: string, tileShape?: string): Folder {
  return {
    id, name, collection_id: '', sort_order: sortOrder,
    cover_image: coverImage || '',
    focus_gif: null,
    focus_gif_enabled: false,
    tile_shape: (tileShape?.toUpperCase() as 'LANDSCAPE' | 'PORTRAIT' | null) || null,
    created_at: '',
  };
}

export default function GenreHubPage() {
  const { genreName } = useParams({ strict: false }) as { genreName: string };
  const navigate = useNavigate();
  const { addons, currentProfile } = useAuth();
  const artworkPreferences = useArtworkPreferences(currentProfile?.id);
  const [mediaKind, setMediaKind] = useState<MediaKind>('movie');

  const decodedGenre = decodeURIComponent(genreName ?? '');

  const { data: organized } = useQuery({
    queryKey: ['genre-hub-organizer', addons.map(a => a.id).join(',')],
    queryFn: async () => {
      await loadCollections(addons, TMDB_API_KEY);
      return getCurrentOrganized();
    },
    enabled: addons.length > 0,
    staleTime: 5 * 60 * 1000,
  });

  const availableGenreNames = organized ? genres(organized).map(g => g.name) : [];

  const { data: hubSections = [] } = useQuery({
    queryKey: ['genre-hub-sections', decodedGenre, organized ? 'ready' : 'pending'],
    queryFn: () => (organized ? sections(decodedGenre, organized) : []),
    enabled: Boolean(organized) && Boolean(decodedGenre),
  });

  const { data: organizerRails = [] } = useQuery({
    queryKey: ['genre-hub-browse', decodedGenre, addons.map(a => a.id).join(','), organized ? 'ready' : 'pending'],
    queryFn: () => (organized ? resolveBrowseRails(browseRails(decodedGenre, organized), addons) : []),
    enabled: Boolean(organized) && Boolean(decodedGenre),
  });

  const { data: tmdbRails = [] } = useQuery({
    queryKey: ['genre-hub-tmdb', decodedGenre, mediaKind],
    queryFn: async () => {
      const [discover, creative] = await Promise.all([
        discoverGenreRails(decodedGenre, mediaKind, TMDB_API_KEY),
        discoverCreativeRails(decodedGenre, mediaKind, TMDB_API_KEY),
      ]);
      return [...discover, ...creative];
    },
    enabled: Boolean(decodedGenre),
    staleTime: 10 * 60 * 1000,
  });

  const browseRows: LoadedBrowseRail[] = [...tmdbRails, ...organizerRails];

  return (
    <div className="min-h-[calc(100vh-56px)] pb-16 px-4 pt-10 sm:px-6 md:px-14">
      <header className="mb-8">
        <p className="type-label mb-2 text-moonlit-text-tertiary">Genre</p>
        <h1 className="type-title-lg text-white">{decodedGenre}</h1>
      </header>

      <div className="mb-8 flex flex-wrap items-center gap-4">
        <div role="group" aria-label="Media kind" className="flex gap-2">
          {(['movie', 'series'] as MediaKind[]).map(kind => (
            <button
              key={kind}
              type="button"
              aria-pressed={mediaKind === kind}
              onClick={() => setMediaKind(kind)}
              className={`category-pill min-h-11 ${mediaKind === kind ? 'category-pill-active' : 'category-pill-idle'}`}
            >
              {kind === 'movie' ? 'Movies' : 'Series'}
            </button>
          ))}
        </div>

        {availableGenreNames.length > 0 && (
          <div role="group" aria-label="Other genres" className="flex max-w-full gap-2 overflow-x-auto py-2 scrollbar-hide">
            {availableGenreNames.map(name => (
              <button
                key={name}
                type="button"
                aria-pressed={name === decodedGenre}
                onClick={() => navigate({ to: '/genre/$genreName', params: { genreName: encodeURIComponent(name) } })}
                className={`category-pill min-h-11 whitespace-nowrap ${name === decodedGenre ? 'category-pill-active' : 'category-pill-idle'}`}
              >
                {name}
              </button>
            ))}
          </div>
        )}
      </div>

      {hubSections.map(section => (
        <section key={section.id} className="mb-10">
          <h2 className="text-[21px] font-bold text-white mb-4">{section.title}</h2>
          <div className="flex gap-3 overflow-x-auto py-3 -my-3 scrollbar-hide">
            {section.folders.map((folder, index) => (
              <FolderTile
                key={folder.id}
                folder={toFolder(folder.id, folder.name, index, folder.coverImage, folder.tileShape)}
              />
            ))}
          </div>
        </section>
      ))}

      {browseRows.map(rail => (
        <MediaRow
          key={rail.id}
          title={rail.title}
          items={rail.items}
          artworkPreferences={artworkPreferences}
        />
      ))}

      {hubSections.length === 0 && browseRows.length === 0 && (
        <div className="surface-card max-w-xl p-6">
          <h2 className="type-title-sm text-white">No {decodedGenre.toLowerCase()} content yet</h2>
          <p className="mt-2 text-sm text-moonlit-text-secondary">Check back once catalogs finish loading, or try another genre.</p>
        </div>
      )}
    </div>
  );
}
