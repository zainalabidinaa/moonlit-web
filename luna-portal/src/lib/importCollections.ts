import { supabase } from './supabase';

function normalizeMediaType(v?: string): string {
  switch (v?.toUpperCase()) {
    case 'TV': case 'SERIES': return 'series';
    case 'MOVIE': return 'movie';
    case 'ALL': return 'all';
    default: return v?.toLowerCase() ?? 'movie';
  }
}

function normalizeShape(v?: string): string {
  switch (v?.toUpperCase()) {
    case 'LANDSCAPE': return 'landscape';
    case 'SQUARE': return 'square';
    default: return 'poster';
  }
}

function resolveNuvioCatalogId(
  src: Record<string, unknown>,
  discoverMap: Record<string, string>
): string | null {
  if (src.catalogId) return src.catalogId as string;
  if (src.traktListId) return `trakt.list.${src.traktListId}`;
  const tmdbSourceType = (src.tmdbSourceType as string | undefined)?.toUpperCase();
  if (src.tmdbId && tmdbSourceType === 'COLLECTION') return `tmdb.collection.${src.tmdbId}`;
  if (tmdbSourceType === 'DISCOVER') {
    const title = ((src.title as string) ?? '').toLowerCase();
    return discoverMap[title] ?? null;
  }
  return null;
}

export async function wipeCollections(): Promise<void> {
  await supabase.from('folder_catalogs').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  await supabase.from('folders').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  await supabase.from('collections').delete().neq('id', '00000000-0000-0000-0000-000000000000');
}

export interface ImportResult {
  collections: number;
  folders: number;
  sources: number;
  skipped: number;
}

export async function importCollections(
  nuvio: Record<string, unknown>[],
  discoverMap: Record<string, string>,
  onProgress?: (msg: string) => void
): Promise<ImportResult> {
  let totalCollections = 0, totalFolders = 0, totalSources = 0, totalSkipped = 0;

  for (let ci = 0; ci < nuvio.length; ci++) {
    const col = nuvio[ci];
    const colName = (col.title ?? col.name ?? `Collection ${ci + 1}`) as string;
    const nuvioFolders = Array.isArray(col.folders) ? col.folders as Record<string, unknown>[] : [];

    const shapes = nuvioFolders.map(f => normalizeShape((f.tileShape ?? f.tile_shape) as string | undefined));
    const dominantShape = shapes.includes('landscape') ? 'landscape' : 'poster';
    const firstHero = (nuvioFolders[0]?.heroBackdropUrl ?? null) as string | null;

    onProgress?.(`[${ci + 1}/${nuvio.length}] ${colName} (${nuvioFolders.length} folders, ${dominantShape})`);

    const { data: colRow, error: colErr } = await supabase.from('collections').insert({
      name: colName,
      view_mode: col.viewMode ?? 'FOLLOW_LAYOUT',
      show_all_tab: col.showAllTab ?? false,
      pin_to_top: col.pinToTop ?? false,
      backdrop_image: (col.backdropImageUrl ?? firstHero) as string | null,
      sort_order: ci,
    }).select().single();

    if (colErr || !colRow) { onProgress?.(`  → error: ${colErr?.message}`); continue; }
    const collectionId = colRow.id as string;
    totalCollections++;
    const prevFolders = totalFolders;

    for (let fi = 0; fi < nuvioFolders.length; fi++) {
      const f = nuvioFolders[fi];
      const shape = normalizeShape((f.tileShape ?? f.tile_shape) as string | undefined);

      const { data: folderRow, error: folderErr } = await supabase.from('folders').insert({
        collection_id: collectionId,
        name: ((f.title ?? f.name ?? `Folder ${fi + 1}`) as string),
        cover_image: ((f.coverImageUrl ?? f.cover_image ?? null) as string | null),
        hero_backdrop: ((f.heroBackdropUrl ?? f.hero_backdrop ?? null) as string | null),
        focus_gif: ((f.focusGifUrl ?? f.focus_gif ?? null) as string | null),
        title_logo: ((f.titleLogoUrl ?? f.title_logo ?? null) as string | null),
        hero_video_url: ((f.heroVideoUrl ?? f.hero_video_url ?? null) as string | null),
        hide_title: (f.hideTitle ?? f.hide_title ?? false) as boolean,
        tile_shape: shape,
        focus_gif_enabled: (f.focusGifEnabled ?? f.focus_gif_enabled ?? false) as boolean,
        sort_order: fi,
      }).select().single();

      if (folderErr || !folderRow) continue;
      const folderId = folderRow.id as string;
      totalFolders++;

      const sources = Array.isArray(f.sources) ? f.sources as Record<string, unknown>[] : [];
      const resolvedSources: { catalog_id: string; media_type: string; genre: string | null }[] = [];

      for (const src of sources) {
        const catalogId = resolveNuvioCatalogId(src, discoverMap);
        if (!catalogId) { totalSkipped++; continue; }
        const genre = src.genre && (src.genre as string).toLowerCase() !== 'none' ? src.genre as string : null;
        const rawType = normalizeMediaType((src.type ?? src.mediaType) as string | undefined);
        // letterboxd catalogs are tagged 'movie' in aiometadata but contain series content;
        // use 'all' so the app tries both movie and series fetches.
        const mediaType = catalogId.startsWith('letterboxd.') ? 'all' : rawType;
        resolvedSources.push({ catalog_id: catalogId, media_type: mediaType, genre });
      }

      if (resolvedSources.length === 0) {
        await supabase.from('folders').delete().eq('id', folderId);
        totalFolders--;
        totalSkipped += sources.length;
        continue;
      }

      for (const row of resolvedSources) {
        const { error } = await supabase.from('folder_catalogs').insert({ folder_id: folderId, ...row });
        if (!error) totalSources++;
      }
    }

    if (totalFolders === prevFolders) {
      await supabase.from('collections').delete().eq('id', collectionId);
      totalCollections--;
      onProgress?.(`  → skipped (no valid sources)`);
    } else {
      onProgress?.(`  → ok`);
    }
  }

  return { collections: totalCollections, folders: totalFolders, sources: totalSources, skipped: totalSkipped };
}

export function buildDiscoverMapFromAioConfig(aioConfig: { config: { catalogs: { id: string; name: string }[] } }): Record<string, string> {
  const map: Record<string, string> = {};
  for (const c of aioConfig.config.catalogs) {
    if (c.id.startsWith('tmdb.discover.')) map[c.name.toLowerCase()] = c.id;
  }
  return map;
}
