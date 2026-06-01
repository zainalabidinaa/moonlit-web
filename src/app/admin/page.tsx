'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '../AuthProvider';
import { useRouter } from 'next/navigation';
import { Sidebar } from '@/components/Sidebar';
import {
  getInviteCodes, generateInviteCode, revokeInviteCode,
  getCollections, createCollection, updateCollection, deleteCollection,
  createFolder, updateFolder, deleteFolder, setFolderCatalogs,
  getSystemAddon, upsertSystemAddon
} from '@/lib/services/api';
import { InviteCode, Collection, Folder, SystemAddon } from '@/lib/types';

type Section = 'codes' | 'collections' | 'stats';

interface FolderModalState {
  open: boolean;
  collectionId: string;
  folder: Partial<Folder> | null;
  catalogInput: string;
}

export default function AdminPage() {
  const { currentProfile, user, isLoading } = useAuth();
  const router = useRouter();
  const [section, setSection] = useState<Section>('collections');

  // Invite codes state
  const [codes, setCodes] = useState<InviteCode[]>([]);
  const [maxUses, setMaxUses] = useState(1);

  // Collections state
  const [collections, setCollections] = useState<Collection[]>([]);
  const [systemAddon, setSystemAddon] = useState<SystemAddon | null>(null);
  const [addonUrlInput, setAddonUrlInput] = useState('');
  const [addonSaving, setAddonSaving] = useState(false);
  const [newRowName, setNewRowName] = useState('');
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());
  const [folderModal, setFolderModal] = useState<FolderModalState>({
    open: false, collectionId: '', folder: null, catalogInput: ''
  });

  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    if (!currentProfile) { router.replace('/profiles'); return; }
    if (currentProfile.role !== 'admin') { router.replace('/home'); return; }
    loadAll();
  }, [currentProfile, isLoading]);

  async function loadAll() {
    setLoading(true);
    try {
      const [c, cols, addon] = await Promise.all([
        getInviteCodes(),
        getCollections(),
        getSystemAddon()
      ]);
      setCodes(c);
      setCollections(cols);
      setSystemAddon(addon);
      if (addon) setAddonUrlInput(addon.manifest_url);
    } finally {
      setLoading(false);
    }
  }

  // ---- Invite code handlers ----
  async function handleGenerate() {
    if (!user) return;
    await generateInviteCode(user.id, maxUses);
    const c = await getInviteCodes();
    setCodes(c);
  }

  async function handleRevoke(code: string) {
    await revokeInviteCode(code);
    const c = await getInviteCodes();
    setCodes(c);
  }

  // ---- System addon handlers ----
  async function handleSaveAddon() {
    if (!addonUrlInput.trim()) return;
    setAddonSaving(true);
    try {
      const manifest = await fetch(addonUrlInput.trim()).then(r => r.json());
      await upsertSystemAddon(addonUrlInput.trim(), manifest.name || '');
      const addon = await getSystemAddon();
      setSystemAddon(addon);
    } catch {
      alert('Could not fetch manifest. Check the URL.');
    }
    setAddonSaving(false);
  }

  // ---- Collection row handlers ----
  async function handleAddRow() {
    if (!newRowName.trim()) return;
    const next = collections.length === 0 ? 0 : Math.max(...collections.map(c => c.sort_order)) + 1;
    const col = await createCollection(newRowName.trim(), next);
    setCollections(prev => [...prev, { ...col, folders: [] }]);
    setNewRowName('');
  }

  async function handleDeleteRow(id: string) {
    if (!confirm('Delete this collection row and all its folders?')) return;
    await deleteCollection(id);
    setCollections(prev => prev.filter(c => c.id !== id));
  }

  function toggleExpand(id: string) {
    setExpandedRows(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }

  // ---- Folder modal handlers ----
  function openAddFolder(collectionId: string) {
    setFolderModal({ open: true, collectionId, folder: {}, catalogInput: '' });
  }

  function openEditFolder(collectionId: string, folder: Folder) {
    const catalogStr = (folder.folder_catalogs || [])
      .map(c => `${c.catalog_id}:${c.media_type}`)
      .join(', ');
    setFolderModal({ open: true, collectionId, folder, catalogInput: catalogStr });
  }

  async function handleSaveFolder() {
    const { collectionId, folder, catalogInput } = folderModal;
    if (!folder?.name?.trim()) return;

    const catalogs = catalogInput
      .split(',')
      .map(s => s.trim())
      .filter(Boolean)
      .map(s => {
        const [catalog_id, media_type] = s.split(':').map(p => p.trim());
        return { catalog_id: catalog_id || s, media_type: media_type || 'movie' };
      });

    if (folder.id) {
      await updateFolder(folder.id, {
        name: folder.name,
        cover_image: folder.cover_image || '',
        focus_gif: folder.focus_gif || '',
        tile_shape: (folder as any).tile_shape || 'PORTRAIT',
      });
      await setFolderCatalogs(folder.id, catalogs);
    } else {
      const sortOrder = (collections.find(c => c.id === collectionId)?.folders?.length || 0);
      const newFolder = await createFolder(
        collectionId,
        folder.name,
        folder.cover_image || '',
        folder.focus_gif || '',
        sortOrder,
        (folder as any).tile_shape || 'PORTRAIT'
      );
      await setFolderCatalogs(newFolder.id, catalogs);
    }

    const cols = await getCollections();
    setCollections(cols);
    setFolderModal({ open: false, collectionId: '', folder: null, catalogInput: '' });
  }

  async function handleDeleteFolder(folderId: string) {
    if (!confirm('Delete this folder?')) return;
    await deleteFolder(folderId);
    const cols = await getCollections();
    setCollections(cols);
  }

  if (loading) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" />
        </div>
      </Sidebar>
    );
  }

  return (
    <Sidebar>
      {/* Gradient header band */}
      <div className="-mt-14 pt-14 pb-8 bg-gradient-to-b from-luna-elevated to-transparent">
        <div className="px-6 pt-8 max-w-4xl">
          <h1 className="text-2xl font-bold text-white mb-6">Admin Panel</h1>
          {/* Pill tab bar */}
          <div className="inline-flex items-center gap-1 p-1.5 bg-[#1e1e1e]/90 border border-white/10 rounded-full">
            {(['collections', 'codes', 'stats'] as Section[]).map(s => (
              <button
                key={s}
                onClick={() => setSection(s)}
                className={`px-4 py-1.5 rounded-full text-xs font-semibold transition-all ${
                  section === s ? 'bg-white/12 text-white' : 'text-white/45 hover:text-white/70'
                }`}
              >
                {s === 'codes' ? 'Invite Codes' : s.charAt(0).toUpperCase() + s.slice(1)}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="px-6 pb-12 max-w-4xl">

        {/* ===== COLLECTIONS ===== */}
        {section === 'collections' && (
          <div>
            {/* System Addon */}
            <div className="bg-luna-surface rounded-2xl p-4 mb-8">
              <p className="text-xs text-luna-muted uppercase tracking-widest mb-3">System Addon</p>
              <div className="flex gap-2">
                <input
                  value={addonUrlInput}
                  onChange={e => setAddonUrlInput(e.target.value)}
                  placeholder="https://your-addon.xyz/manifest.json"
                  className="flex-1 px-3 py-2 bg-luna-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-luna-accent"
                />
                <button
                  onClick={handleSaveAddon}
                  disabled={addonSaving}
                  className="px-4 py-2 bg-luna-accent rounded-xl text-sm disabled:opacity-50"
                >
                  {addonSaving ? 'Saving...' : 'Save'}
                </button>
              </div>
              {systemAddon && (
                <p className="text-xs text-green-400 mt-2">
                  ● Connected — {systemAddon.name || systemAddon.manifest_url}
                </p>
              )}
            </div>

            {/* Add new row */}
            <div className="flex gap-2 mb-4">
              <input
                value={newRowName}
                onChange={e => setNewRowName(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleAddRow()}
                placeholder="New collection row name…"
                className="flex-1 px-3 py-2 bg-luna-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-luna-accent"
              />
              <button
                onClick={handleAddRow}
                className="px-4 py-2 bg-luna-accent rounded-xl text-sm"
              >
                + Add Row
              </button>
            </div>

            {/* Collection rows */}
            <div className="space-y-3">
              {collections.map(col => (
                <div key={col.id} className="bg-luna-surface rounded-2xl overflow-hidden">
                  {/* Row header */}
                  <div className="flex items-center justify-between px-4 py-3">
                    <button
                      onClick={() => toggleExpand(col.id)}
                      className="flex items-center gap-2 text-left flex-1"
                    >
                      <span className="text-sm font-semibold text-white">{col.name}</span>
                      <span className="text-xs text-luna-muted">
                        {col.folders?.length || 0} folders
                      </span>
                      <span className="text-luna-muted text-xs ml-1">
                        {expandedRows.has(col.id) ? '▲' : '▼'}
                      </span>
                    </button>
                    <button
                      onClick={() => handleDeleteRow(col.id)}
                      className="text-xs text-red-400 hover:text-red-300 ml-4"
                    >
                      Delete
                    </button>
                  </div>

                  {/* Expanded folders */}
                  {expandedRows.has(col.id) && (
                    <div className="border-t border-white/5 px-4 py-3 bg-luna-elevated/30">
                      <div className="flex flex-wrap gap-3 mb-3">
                        {(col.folders || []).map(folder => (
                          <div key={folder.id} className="relative group">
                            <div
                              className="w-28 h-16 rounded-lg overflow-hidden bg-luna-elevated cursor-pointer"
                              onClick={() => openEditFolder(col.id, folder)}
                            >
                              {folder.cover_image ? (
                                <img src={folder.cover_image} alt={folder.name} className="w-full h-full object-cover" />
                              ) : (
                                <div className="w-full h-full flex items-center justify-center">
                                  <span className="text-xs text-luna-muted text-center px-1">{folder.name}</span>
                                </div>
                              )}
                            </div>
                            <p className="text-xs text-luna-muted mt-1 truncate w-28">{folder.name}</p>
                            <button
                              onClick={() => handleDeleteFolder(folder.id)}
                              className="absolute -top-1 -right-1 w-4 h-4 bg-red-500 rounded-full text-white text-xs hidden group-hover:flex items-center justify-center"
                            >
                              ×
                            </button>
                          </div>
                        ))}
                        {/* Add folder tile */}
                        <button
                          onClick={() => openAddFolder(col.id)}
                          className="w-28 h-16 rounded-lg border-2 border-dashed border-luna-muted/30 hover:border-luna-accent flex items-center justify-center text-luna-muted hover:text-luna-accent transition-colors text-xs"
                        >
                          + Add Folder
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              ))}

              {collections.length === 0 && (
                <p className="text-sm text-luna-muted text-center py-8">
                  No collection rows yet. Add one above.
                </p>
              )}
            </div>
          </div>
        )}

        {/* ===== INVITE CODES ===== */}
        {section === 'codes' && (
          <div>
            <div className="flex gap-2 mb-4 items-center">
              <input
                type="number"
                value={maxUses}
                onChange={e => setMaxUses(Number(e.target.value))}
                min={1}
                max={100}
                className="w-20 px-3 py-2 bg-luna-elevated rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-luna-accent text-sm"
              />
              <span className="text-sm text-luna-muted">uses per code</span>
              <button onClick={handleGenerate} className="ml-auto px-4 py-2 bg-luna-accent rounded-xl text-sm">
                Generate Code
              </button>
            </div>
            <div className="space-y-2">
              <p className="text-sm text-luna-muted mb-2">
                Active: {codes.filter(c => c.is_active && !c.used_by).length} | Total: {codes.length}
              </p>
              {codes.map(code => (
                <div key={code.code} className="p-3 bg-luna-surface rounded-xl flex items-center justify-between">
                  <div>
                    <p className="font-mono font-bold">{code.code}</p>
                    <p className="text-xs text-luna-muted">
                      Created: {new Date(code.created_at).toLocaleDateString()}
                      {code.used_by && ' • Used'}
                      {!code.is_active && ' • Revoked'}
                    </p>
                  </div>
                  <div className="flex gap-2 items-center">
                    <span className={`w-2 h-2 rounded-full ${
                      code.is_active && !code.used_by ? 'bg-green-500' :
                      code.used_by ? 'bg-red-500' : 'bg-gray-500'
                    }`} />
                    {code.is_active && !code.used_by && (
                      <button onClick={() => handleRevoke(code.code)} className="text-xs text-red-400 hover:text-red-300">
                        Revoke
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ===== STATS ===== */}
        {section === 'stats' && (
          <div className="grid grid-cols-2 gap-4">
            {[
              { label: 'Total Invite Codes', value: codes.length },
              { label: 'Active Codes', value: codes.filter(c => c.is_active && !c.used_by).length },
              { label: 'Used Codes', value: codes.filter(c => c.used_by).length },
              { label: 'Collection Rows', value: collections.length },
            ].map(stat => (
              <div key={stat.label} className="p-4 bg-luna-surface rounded-xl text-center">
                <p className="text-2xl font-bold">{stat.value}</p>
                <p className="text-xs text-luna-muted">{stat.label}</p>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* ===== FOLDER MODAL ===== */}
      {folderModal.open && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4">
          <div className="bg-luna-surface rounded-2xl p-6 w-full max-w-md">
            <h2 className="text-lg font-bold mb-4">
              {folderModal.folder?.id ? 'Edit Folder' : 'Add Folder'}
            </h2>
            <div className="space-y-3">
              <div>
                <label className="text-xs text-luna-muted mb-1 block">Folder name</label>
                <input
                  value={folderModal.folder?.name || ''}
                  onChange={e => setFolderModal(prev => ({ ...prev, folder: { ...prev.folder, name: e.target.value } }))}
                  className="w-full px-3 py-2 bg-luna-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-luna-accent"
                  placeholder="Netflix"
                />
              </div>
              <div>
                <label className="text-xs text-luna-muted mb-1 block">Cover image URL</label>
                <input
                  value={folderModal.folder?.cover_image || ''}
                  onChange={e => setFolderModal(prev => ({ ...prev, folder: { ...prev.folder, cover_image: e.target.value } }))}
                  className="w-full px-3 py-2 bg-luna-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-luna-accent"
                  placeholder="https://cdn.example.com/netflix.png"
                />
              </div>
              <div>
                <label className="text-xs text-luna-muted mb-1 block">Tile Shape</label>
                <div className="flex gap-2">
                  {(['PORTRAIT', 'LANDSCAPE'] as const).map(shape => (
                    <button
                      key={shape}
                      type="button"
                      onClick={() => setFolderModal(prev => ({ ...prev, folder: { ...prev.folder, tile_shape: shape } }))}
                      className={`flex-1 py-2 rounded-xl text-sm font-medium transition-all border ${
                        (folderModal.folder?.tile_shape ?? 'PORTRAIT') === shape
                          ? 'bg-luna-accent/20 border-luna-accent/40 text-luna-accent'
                          : 'bg-luna-elevated border-transparent text-luna-muted hover:text-white'
                      }`}
                    >
                      {shape === 'PORTRAIT' ? '▭ Portrait' : '▬ Landscape'}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label className="text-xs text-luna-muted mb-1 block">Hover GIF URL</label>
                <input
                  value={folderModal.folder?.focus_gif || ''}
                  onChange={e => setFolderModal(prev => ({ ...prev, folder: { ...prev.folder, focus_gif: e.target.value } }))}
                  className="w-full px-3 py-2 bg-luna-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-luna-accent"
                  placeholder="https://cdn.example.com/netflix.gif"
                />
              </div>
              <div>
                <label className="text-xs text-luna-muted mb-1 block">
                  Catalogs <span className="opacity-50">(comma-separated, format: catalog_id:media_type)</span>
                </label>
                <input
                  value={folderModal.catalogInput}
                  onChange={e => setFolderModal(prev => ({ ...prev, catalogInput: e.target.value }))}
                  className="w-full px-3 py-2 bg-luna-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-luna-accent"
                  placeholder="netflix-movies:movie, netflix-series:series"
                />
              </div>
            </div>
            <div className="flex gap-2 mt-5">
              <button
                onClick={() => setFolderModal({ open: false, collectionId: '', folder: null, catalogInput: '' })}
                className="flex-1 py-2 bg-luna-elevated rounded-xl text-sm"
              >
                Cancel
              </button>
              <button
                onClick={handleSaveFolder}
                className="flex-1 py-2 bg-luna-accent rounded-xl text-sm"
              >
                Save
              </button>
            </div>
          </div>
        </div>
      )}
    </Sidebar>
  );
}
