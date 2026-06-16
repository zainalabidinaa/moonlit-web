import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';

// Build DISCOVER title → catalogId lookup from aiometadata config
const aioConfig = JSON.parse(readFileSync('/Users/zain/Downloads/aiometadata and nuevio collections/aiometadata-config-2026-06-12.json', 'utf-8'));
const discoverByTitle = new Map();
for (const c of aioConfig.config.catalogs) {
  if (c.id.startsWith('tmdb.discover.')) discoverByTitle.set(c.name.toLowerCase(), c.id);
}

const supabase = createClient(
  'https://hvfsntdyowapjxobtyli.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2ZnNudGR5b3dhcGp4b2J0eWxpIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDE3ODQ5NSwiZXhwIjoyMDk1NzU0NDk1fQ.sB0HwWmcM8c5JQoqNnjvWoM0_Yd7IkXeNcweaGq-CuU'
);

function normalizeMediaType(v) {
  switch (v?.toUpperCase()) {
    case 'TV': case 'SERIES': return 'series';
    case 'MOVIE': return 'movie';
    default: return v?.toLowerCase() ?? 'movie';
  }
}

function normalizeShape(v) {
  switch (v?.toUpperCase()) {
    case 'LANDSCAPE': return 'landscape';
    case 'SQUARE': return 'square';
    default: return 'poster';
  }
}

function resolveNuvioCatalogId(src) {
  if (src.catalogId) return src.catalogId;
  if (src.traktListId) return `trakt.list.${src.traktListId}`;
  if (src.tmdbId && src.tmdbSourceType?.toUpperCase() === 'COLLECTION') return `tmdb.collection.${src.tmdbId}`;
  if (src.tmdbSourceType?.toUpperCase() === 'DISCOVER') {
    const title = (src.title ?? '').toLowerCase();
    return discoverByTitle.get(title) ?? null;
  }
  return null;
}

async function importNuvioPack(nuvio) {
  let totalCollections = 0, totalFolders = 0, totalSources = 0, totalSkipped = 0;

  for (let ci = 0; ci < nuvio.length; ci++) {
    const col = nuvio[ci];
    const colName = col.title ?? col.name ?? `Collection ${ci + 1}`;
    const nuvioFolders = Array.isArray(col.folders) ? col.folders : [];

    const shapes = nuvioFolders.map(f => normalizeShape(f.tileShape ?? f.tile_shape));
    const dominantShape = shapes.includes('landscape') ? 'landscape' : 'poster';
    const firstHero = nuvioFolders[0]?.heroBackdropUrl ?? null;

    const prevFolders = totalFolders;
    process.stdout.write(`[${ci + 1}/${nuvio.length}] ${colName} (${nuvioFolders.length} folders, ${dominantShape}) ... `);

    const { data: colRow, error: colErr } = await supabase.from('collections').insert({
      name: colName,
      view_mode: col.viewMode ?? 'FOLLOW_LAYOUT',
      show_all_tab: col.showAllTab ?? false,
      pin_to_top: col.pinToTop ?? false,
      backdrop_image: col.backdropImageUrl ?? firstHero,
      sort_order: ci,
    }).select().single();

    if (colErr || !colRow) {
      console.log(`ERROR: ${colErr?.message}`);
      continue;
    }
    const collectionId = colRow.id;
    totalCollections++;

    for (let fi = 0; fi < nuvioFolders.length; fi++) {
      const f = nuvioFolders[fi];
      const shape = normalizeShape(f.tileShape ?? f.tile_shape);
      const { data: folderRow, error: folderErr } = await supabase.from('folders').insert({
        collection_id: collectionId,
        name: f.title ?? f.name ?? `Folder ${fi + 1}`,
        cover_image: f.coverImageUrl ?? f.cover_image ?? null,
        hero_backdrop: f.heroBackdropUrl ?? f.hero_backdrop ?? null,
        focus_gif: f.focusGifUrl ?? f.focus_gif ?? null,
        title_logo: f.titleLogoUrl ?? f.title_logo ?? null,
        hero_video_url: f.heroVideoUrl ?? f.hero_video_url ?? null,
        hide_title: f.hideTitle ?? f.hide_title ?? false,
        tile_shape: shape,
        focus_gif_enabled: f.focusGifEnabled ?? f.focus_gif_enabled ?? false,
        sort_order: fi,
      }).select().single();

      if (folderErr || !folderRow) {
        process.stdout.write(`(folder err: ${folderErr?.message}) `);
        continue;
      }
      const folderId = folderRow.id;
      totalFolders++;

      const sources = Array.isArray(f.sources) ? f.sources : [];
      // pre-resolve all sources — skip folder entirely if none are valid
      const resolvedSources = [];
      for (const src of sources) {
        const catalogId = resolveNuvioCatalogId(src);
        if (!catalogId) { totalSkipped++; continue; }
        // letterboxd catalogs are registered as 'movie' in aiometadata but often contain
        // series content (K-drama, J-drama). Use 'all' so the app tries both types.
        const rawType = normalizeMediaType(src.type ?? src.mediaType);
        const mediaType = catalogId.startsWith('letterboxd.') ? 'all' : rawType;
        resolvedSources.push({
          catalog_id: catalogId,
          media_type: mediaType,
          genre: src.genre && src.genre.toLowerCase() !== 'none' ? src.genre : null,
        });
      }
      if (resolvedSources.length === 0) {
        // delete the folder we just inserted — no valid sources
        await supabase.from('folders').delete().eq('id', folderId);
        totalFolders--;
        totalSkipped += sources.length;
        continue;
      }
      for (const row of resolvedSources) {
        const { error } = await supabase.from('folder_catalogs').insert({ folder_id: folderId, ...row });
        if (!error) totalSources++;
        else process.stdout.write(`(src err: ${error.message}) `);
      }
    }
    if (totalFolders === prevFolders) {
      // no folders were added for this collection — remove it
      await supabase.from('collections').delete().eq('id', collectionId);
      totalCollections--;
      console.log('skipped (no valid sources)');
    } else {
      console.log('ok');
    }
  }

  return { totalCollections, totalFolders, totalSources, totalSkipped };
}

const jsonPath = '/Users/zain/Downloads/aiometadata and nuevio collections/nuvio-collections-profile-2-2026-06-14.json';
const nuvio = JSON.parse(readFileSync(jsonPath, 'utf-8'));
console.log(`Importing ${nuvio.length} collections from Nuvio JSON...`);
const result = await importNuvioPack(nuvio);
console.log('\n✅ Import complete:');
console.log(`   Collections: ${result.totalCollections}`);
console.log(`   Folders:     ${result.totalFolders}`);
console.log(`   Sources:     ${result.totalSources}`);
console.log(`   Skipped:     ${result.totalSkipped} (no resolvable catalogId)`);
