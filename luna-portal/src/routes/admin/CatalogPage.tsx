import { useEffect, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { AppShell } from '../../components/layout/AppShell';
import { Button } from '../../components/ui/Button';
import { FolderGrid } from '../../components/catalog/FolderGrid';
import { ArtworkGallery } from '../../components/catalog/ArtworkGallery';
import { SourcesTable } from '../../components/catalog/SourcesTable';
import { JsonImport } from '../../components/catalog/JsonImport';
import type { Collection, Folder, FolderSource, FolderCatalog } from '../../types';

type Tab = 'folders' | 'artwork' | 'sources' | 'json';
const TABS: { id: Tab; label: string }[] = [
  { id: 'folders', label: 'Folders' },
  { id: 'artwork', label: 'Folder artwork' },
  { id: 'sources', label: 'Sources' },
  { id: 'json', label: 'JSON' },
];

export default function CatalogPage() {
  const [collections, setCollections] = useState<Collection[]>([]);
  const [folderCounts, setFolderCounts] = useState<Record<string, number>>({});
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [folders, setFolders] = useState<Folder[]>([]);
  const [selectedFolder, setSelectedFolder] = useState<Folder | null>(null);
  const [sources, setSources] = useState<FolderSource[]>([]);
  const [catalogs, setCatalogs] = useState<FolderCatalog[]>([]);
  const [tab, setTab] = useState<Tab>('folders');
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const colDrag = useRef<number | null>(null);
  const folderDrag = useRef<number | null>(null);

  useEffect(() => {
    loadCollections();

    // Real-time: re-fetch when collections or folders change in Supabase
    const colSub = supabase
      .channel('collections-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'collections' }, () => loadCollections())
      .subscribe();

    return () => { supabase.removeChannel(colSub); };
  }, []);

  useEffect(() => {
    if (!selectedId) return;
    loadFolders(selectedId);

    const folderSub = supabase
      .channel(`folders-changes-${selectedId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'folders', filter: `collection_id=eq.${selectedId}` }, () => loadFolders(selectedId))
      .subscribe();

    return () => { supabase.removeChannel(folderSub); };
  }, [selectedId]);
  useEffect(() => {
    if (!selectedFolder) { setSources([]); setCatalogs([]); return; }
    const fid = selectedFolder.id;
    supabase.from('folder_sources').select('*').eq('folder_id', fid).order('sort_order')
      .then(({ data, error }) => {
        if (error) console.error('folder_sources error:', error);
        setSources((data ?? []) as FolderSource[]);
      });
    supabase.from('folder_catalogs').select('*').eq('folder_id', fid)
      .then(({ data, error }) => {
        if (error) console.error('folder_catalogs error:', error);
        setCatalogs((data ?? []) as FolderCatalog[]);
      });
  }, [selectedFolder]);

  async function loadCollections() {
    setLoadError(null);
    const { data, error } = await supabase.from('collections').select('*').order('sort_order');
    if (error) {
      setLoadError(`Failed to load collections: ${error.message}`);
      setLoading(false);
      return;
    }
    const rows = (data ?? []) as Collection[];
    setCollections(rows);
    if (rows.length) {
      const { data: f } = await supabase.from('folders').select('collection_id').in('collection_id', rows.map((c) => c.id));
      const counts: Record<string, number> = {};
      for (const row of (f ?? []) as { collection_id: string }[]) counts[row.collection_id] = (counts[row.collection_id] ?? 0) + 1;
      setFolderCounts(counts);
      setSelectedId((cur) => cur ?? rows[0].id);
    }
    setLoading(false);
  }

  async function loadFolders(collectionId: string) {
    const { data } = await supabase.from('folders').select('*').eq('collection_id', collectionId).order('sort_order');
    setFolders((data ?? []) as Folder[]);
    setSelectedFolder(null);
  }

  // ---- collections ----
  async function addCollection() {
    const name = prompt('Collection name')?.trim();
    if (!name) return;
    const { data } = await supabase.from('collections').insert({
      name, view_mode: 'FOLLOW_LAYOUT', sort_order: collections.length,
    }).select().single();
    if (data) { setCollections((p) => [...p, data as Collection]); setSelectedId((data as Collection).id); }
  }
  async function deleteCollection(id: string) {
    if (!confirm('Delete this collection and its folders?')) return;
    await supabase.from('collections').delete().eq('id', id);
    setCollections((p) => p.filter((c) => c.id !== id));
    if (selectedId === id) setSelectedId(collections.find((c) => c.id !== id)?.id ?? null);
  }
  async function reorderCollections(to: number) {
    if (colDrag.current === null || colDrag.current === to) return;
    const next = [...collections];
    const [moved] = next.splice(colDrag.current, 1);
    next.splice(to, 0, moved);
    setCollections(next);
    colDrag.current = null;
    await Promise.all(next.map((c, i) => supabase.from('collections').update({ sort_order: i }).eq('id', c.id)));
  }

  // ---- folders ----
  async function addFolder() {
    if (!selectedId) return;
    const name = prompt('Folder name')?.trim();
    if (!name) return;
    const { data } = await supabase.from('folders').insert({
      collection_id: selectedId, name, sort_order: folders.length, tile_shape: 'POSTER',
    }).select().single();
    if (data) { setFolders((p) => [...p, data as Folder]); setFolderCounts((c) => ({ ...c, [selectedId]: (c[selectedId] ?? 0) + 1 })); }
  }
  async function reorderFolders(to: number) {
    if (folderDrag.current === null || folderDrag.current === to) return;
    const next = [...folders];
    const [moved] = next.splice(folderDrag.current, 1);
    next.splice(to, 0, moved);
    setFolders(next);
    folderDrag.current = null;
    await Promise.all(next.map((f, i) => supabase.from('folders').update({ sort_order: i }).eq('id', f.id)));
  }
  async function moveFolderUp(i: number) {
    if (i === 0) return;
    folderDrag.current = i;
    await reorderFolders(i - 1);
  }
  async function moveFolderDown(i: number) {
    if (i === folders.length - 1) return;
    folderDrag.current = i;
    await reorderFolders(i + 1);
  }
  async function saveFolderArtwork(patch: Partial<Folder>) {
    if (!selectedFolder) return;
    await supabase.from('folders').update(patch).eq('id', selectedFolder.id);
    const updated = { ...selectedFolder, ...patch } as Folder;
    setSelectedFolder(updated);
    setFolders((p) => p.map((f) => (f.id === updated.id ? updated : f)));
  }

  // ---- folder_sources (TMDB/provider) ----
  async function addSource(provider: string) {
    if (!selectedFolder) return;
    const { data } = await supabase.from('folder_sources').insert({
      folder_id: selectedFolder.id, provider, sort_order: sources.length,
    }).select().single();
    if (data) setSources((p) => [...p, data as FolderSource]);
  }
  async function deleteSource(id: string) {
    await supabase.from('folder_sources').delete().eq('id', id);
    setSources((p) => p.filter((s) => s.id !== id));
  }

  // ---- folder_catalogs (Stremio catalog) ----
  async function addCatalog(catalogId: string, mediaType: string, genre: string | null) {
    if (!selectedFolder) return;
    const { data } = await supabase.from('folder_catalogs').insert({
      folder_id: selectedFolder.id, catalog_id: catalogId, media_type: mediaType,
      genre: genre ?? null,
    }).select().single();
    if (data) setCatalogs((p) => [...p, data as FolderCatalog]);
  }
  async function deleteCatalog(id: string) {
    await supabase.from('folder_catalogs').delete().eq('id', id);
    setCatalogs((p) => p.filter((c) => c.id !== id));
  }

  // ---- JSON pack import ----
  async function importPack(pack: Record<string, unknown>) {
    const p = pack as any;

    // Detect format: Nuvio = top-level array of collections with nested folders+sources
    if (Array.isArray(p)) {
      return importNuvioPack(p);
    }
    // BEST format: object with flat collections[], folders[], folder_catalogs[] arrays
    return importBESTPack(p);
  }

  // ---- Nuvio format import ----
  // Top-level array: [{ id, title, folders: [{ id, title, sources: [...], heroBackdropUrl, tileShape }] }]
  async function importNuvioPack(nuvio: any[]) {
    let totalCollections = 0, totalFolders = 0, totalSources = 0;

    for (let ci = 0; ci < nuvio.length; ci++) {
      const col = nuvio[ci];
      const colName: string = col.title ?? col.name ?? `Collection ${ci + 1}`;
      const nuvioFolders: any[] = Array.isArray(col.folders) ? col.folders : [];

      // Use first folder's heroBackdropUrl as collection backdrop if none set
      const firstHero = nuvioFolders[0]?.heroBackdropUrl ?? null;

      const { data: colRow, error: colErr } = await supabase.from('collections').insert({
        name: colName,
        view_mode: col.viewMode ?? 'FOLLOW_LAYOUT',
        show_all_tab: col.showAllTab ?? false,
        pin_to_top: col.pinToTop ?? false,
        backdrop_image: col.backdropImageUrl ?? firstHero,
        sort_order: collections.length + ci,
      }).select().single();
      if (colErr || !colRow) continue;
      const collectionId = (colRow as Collection).id;
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
        if (folderErr || !folderRow) continue;
        const folderId = (folderRow as Folder).id;
        totalFolders++;

        // Import sources as folder_catalogs
        const sources: any[] = Array.isArray(f.sources) ? f.sources : [];
        const seenCatalogIds = new Set<string>();
        for (let si = 0; si < sources.length; si++) {
          const src = sources[si];
          const catalogId = resolveNuvioCatalogId(src);
          if (!catalogId) continue;
          const dedupeKey = `${folderId}:${catalogId}`;
          if (seenCatalogIds.has(dedupeKey)) continue;
          seenCatalogIds.add(dedupeKey);

          const mediaType = normalizeMediaType(src.type ?? src.mediaType);
          const genre = src.genre && src.genre.toLowerCase() !== 'none' ? src.genre : null;

          const { error } = await supabase.from('folder_catalogs').insert({
            folder_id: folderId,
            catalog_id: catalogId,
            media_type: mediaType,
            genre,
          });
          if (!error) totalSources++;
        }
      }
    }

    await loadCollections();
    return { collections: totalCollections, folders: totalFolders, sources: totalSources };
  }

  function resolveNuvioCatalogId(src: any): string | null {
    if (src.catalogId) return src.catalogId;
    if (src.traktListId) return `trakt.list.${src.traktListId}`;
    if (src.tmdbId && src.tmdbSourceType?.toUpperCase() === 'COLLECTION') return `tmdb.collection.${src.tmdbId}`;
    if (src.tmdbSourceType?.toUpperCase() === 'DISCOVER') {
      const mt = normalizeMediaType(src.type ?? src.mediaType);
      const title = (src.title ?? '').toLowerCase();
      const known: Record<string, string> = {
        'movie:new movies': 'tmdb.discover.movie.new-movies.069d5312',
        'movie:popular movies': 'tmdb.discover.movie.popular-movies.29727d26',
        'movie:top all time movies': 'tmdb.discover.movie.top-all-time-movies.39f5a0c4',
        'series:new series': 'tmdb.discover.series.new-series.76fc7ade',
        'series:popular series': 'tmdb.discover.series.popular-series.20af3ad9',
        'series:top all time series': 'tmdb.discover.series.top-all-time-series.53046f30',
      };
      return known[`${mt}:${title}`] ?? null;
    }
    return null;
  }

  function normalizeMediaType(v?: string): string {
    switch (v?.toUpperCase()) { case 'TV': case 'SERIES': return 'series'; case 'MOVIE': return 'movie'; default: return v?.toLowerCase() ?? 'movie'; }
  }

  function normalizeShape(v?: string): string {
    switch (v?.toUpperCase()) { case 'LANDSCAPE': return 'landscape'; case 'SQUARE': return 'square'; default: return 'poster'; }
  }

  // ---- BEST format import (existing logic) ----
  async function importBESTPack(p: any) {
    const col = p.collections?.[0] ?? { name: p.pack?.title ?? 'Imported pack' };
    const { data: colRow, error: colErr } = await supabase.from('collections').insert({
      name: col.name ?? 'Imported pack',
      view_mode: col.view_mode ?? 'FOLLOW_LAYOUT',
      backdrop_image: col.backdrop_image ?? null,
      sort_order: collections.length,
    }).select().single();
    if (colErr || !colRow) throw new Error(colErr?.message ?? 'collection insert failed');
    const collectionId = (colRow as Collection).id;

    const nameToId: Record<string, string> = {};
    let folderCount = 0;
    const folderList: any[] = Array.isArray(p.folders) ? p.folders : [];
    for (let i = 0; i < folderList.length; i++) {
      const f = folderList[i];
      const { data } = await supabase.from('folders').insert({
        collection_id: collectionId,
        name: f.name ?? `Folder ${i + 1}`,
        cover_image: f.cover_image ?? null,
        hero_backdrop: f.hero_backdrop ?? null,
        focus_gif: f.focus_gif ?? null,
        title_logo: f.title_logo ?? null,
        hero_video_url: f.hero_video_url ?? null,
        hide_title: f.hide_title ?? false,
        tile_shape: f.tile_shape ?? 'POSTER',
        focus_gif_enabled: f.focus_gif_enabled ?? true,
        sort_order: i,
      }).select().single();
      if (data) { nameToId[(data as Folder).name] = (data as Folder).id; folderCount++; }
    }

    let sourceCount = 0;
    const perFolder: Record<string, number> = {};

    const cats: any[] = Array.isArray(p.folder_catalogs) ? p.folder_catalogs : [];
    for (const c of cats) {
      const fid = nameToId[c.folder_name ?? c.folder];
      if (!fid) continue;
      const idx = perFolder[fid] ?? 0;
      const { error } = await supabase.from('folder_catalogs').insert({
        folder_id: fid,
        catalog_id: c.catalog_id ?? c.provider ?? 'unknown',
        media_type: c.media_type ?? 'movie',
        genre: c.genre ?? null,
        extras: c.extras ?? null,
      });
      if (!error) { sourceCount++; perFolder[fid] = idx + 1; }
    }

    const srcs: any[] = Array.isArray(p.folder_sources) ? p.folder_sources : [];
    for (const s of srcs) {
      const fid = nameToId[s.folder_name ?? s.folder];
      if (!fid) continue;
      const idx = perFolder[fid] ?? 0;
      const { error } = await supabase.from('folder_sources').insert({
        folder_id: fid, provider: s.provider ?? 'unknown',
        title: s.title ?? null, tmdb_id: s.tmdb_id ?? null,
        media_type: s.media_type ?? null, sort_order: idx,
      });
      if (!error) { sourceCount++; perFolder[fid] = idx + 1; }
    }

    await loadCollections();
    setSelectedId(collectionId);
    return { collections: 1, folders: folderCount, sources: sourceCount };
  }

  const selected = collections.find((c) => c.id === selectedId) ?? null;

  return (
    <AppShell>
      <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="font-mono text-[11px] uppercase tracking-[0.28em] text-accent">Admin · Catalog</p>
          <h1 className="font-display text-[clamp(30px,4vw,46px)] font-extrabold uppercase">Collection manager</h1>
          <p className="mt-1 text-sm text-muted">
            Edit collections, folders, sources and <span className="text-accent">every artwork slot</span> — with live previews.
          </p>
        </div>
        <div className="flex gap-2.5">
          <Button variant="ghost" size="sm" onClick={() => { setLoading(true); loadCollections(); }}>↺ Refresh</Button>
          <Button variant="ghost" size="sm" onClick={() => setTab('json')}>⤵ Import pack JSON</Button>
          <Button size="sm" onClick={addCollection}>+ New collection</Button>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-[280px_1fr]">
        {/* sidebar */}
        <aside className="h-fit rounded-2xl border border-border bg-surface p-3.5 lg:sticky lg:top-20">
          <div className="px-2 pb-3 pt-1.5 font-mono text-[11px] uppercase tracking-wide text-muted">
            Collections · {collections.length}
          </div>
          {loadError && (
            <div className="mb-2 rounded-xl border border-red-400/30 bg-red-400/10 px-3 py-2 font-mono text-[11px] text-red-400">
              {loadError}
            </div>
          )}
          {loading ? (
            <div className="flex flex-col gap-2">{[0, 1, 2].map((i) => <div key={i} className="h-12 animate-pulse rounded-xl bg-surface-2" />)}</div>
          ) : collections.length === 0 ? (
            <p className="px-2 py-4 font-mono text-[11px] text-faint">No collections found.</p>
          ) : (
            collections.map((c, i) => (
              <div
                key={c.id}
                draggable
                onDragStart={() => (colDrag.current = i)}
                onDragOver={(e) => e.preventDefault()}
                onDrop={() => reorderCollections(i)}
                onClick={() => setSelectedId(c.id)}
                className={`group flex cursor-pointer items-center gap-2.5 rounded-xl border p-2.5 transition-colors ${
                  selectedId === c.id ? 'border-accent/30 bg-accent-light' : 'border-transparent hover:bg-surface-2'
                }`}
              >
                <div className="h-9 w-9 flex-none overflow-hidden rounded-lg bg-surface-2">
                  {c.backdrop_image && <img src={c.backdrop_image} alt="" className="h-full w-full object-cover" />}
                </div>
                <div className="min-w-0 flex-1">
                  <b className="block truncate text-[13px] font-semibold">{c.name}</b>
                  <small className="font-mono text-[10px] text-faint">{folderCounts[c.id] ?? 0} folders</small>
                </div>
                <button
                  onClick={(e) => { e.stopPropagation(); deleteCollection(c.id); }}
                  className="font-mono text-[10px] text-faint opacity-0 transition-opacity hover:text-red-400 group-hover:opacity-100"
                >
                  del
                </button>
              </div>
            ))
          )}
        </aside>

        {/* main */}
        <div className="overflow-hidden rounded-2xl border border-border bg-surface">
          <div className="flex gap-0.5 border-b border-border px-4 pt-3.5">
            {TABS.map((t) => (
              <button
                key={t.id}
                onClick={() => setTab(t.id)}
                className={`-mb-px border-b-2 px-4 py-2.5 text-[13px] transition-colors ${
                  tab === t.id ? 'border-accent text-accent' : 'border-transparent text-muted hover:text-text'
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>

          <div className="p-6">
            {!selected ? (
              <div className="py-16 text-center text-sm text-muted">Select or create a collection to begin.</div>
            ) : tab === 'folders' ? (
              <FolderGrid
                collection={selected}
                folders={folders}
                onSelectFolder={(f) => { setSelectedFolder(f); setTab('artwork'); }}
                onAddFolder={addFolder}
                onDragStart={(i) => (folderDrag.current = i)}
                onDrop={reorderFolders}
                onMoveUp={moveFolderUp}
                onMoveDown={moveFolderDown}
              />
            ) : tab === 'artwork' ? (
              selectedFolder ? (
                <ArtworkGallery folder={selectedFolder} onBack={() => setTab('folders')} onSave={saveFolderArtwork} />
              ) : (
                <div className="py-16 text-center text-sm text-muted">Pick a folder from the Folders tab to edit its artwork.</div>
              )
            ) : tab === 'sources' ? (
              selectedFolder ? (
                <SourcesTable
                  folder={selectedFolder}
                  sources={sources}
                  catalogs={catalogs}
                  onAddSource={addSource}
                  onDeleteSource={deleteSource}
                  onAddCatalog={addCatalog}
                  onDeleteCatalog={deleteCatalog}
                />
              ) : (
                <div className="py-16 text-center text-sm text-muted">Pick a folder from the Folders tab to edit its sources.</div>
              )
            ) : (
              <JsonImport onImport={importPack} />
            )}
          </div>
        </div>
      </div>
    </AppShell>
  );
}
