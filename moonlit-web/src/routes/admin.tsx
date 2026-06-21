import { useEffect, useState } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { useNavigate } from '@tanstack/react-router';
import { Sidebar } from '@/components/Sidebar';
import {
  getInviteCodes, generateInviteCode, revokeInviteCode, updateInviteCodeExpiration,
  getCollections, createCollection, deleteCollection,
  createFolder, updateFolder, deleteFolder, setFolderCatalogs,
  getSystemAddon, upsertSystemAddon,
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
  const { currentProfile, isLoading } = useAuth();
  const navigate = useNavigate();
  const [section, setSection] = useState<Section>('collections');

  const [codes, setCodes] = useState<InviteCode[]>([]);
  const [maxUses, setMaxUses] = useState(1);
  const [newCodeExpiresAt, setNewCodeExpiresAt] = useState('');
  const [collections, setCollections] = useState<Collection[]>([]);
  const [systemAddon, setSystemAddon] = useState<SystemAddon | null>(null);
  const [addonUrlInput, setAddonUrlInput] = useState('');
  const [addonSaving, setAddonSaving] = useState(false);
  const [newRowName, setNewRowName] = useState('');
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());
  const [folderModal, setFolderModal] = useState<FolderModalState>({
    open: false, collectionId: '', folder: null, catalogInput: '',
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (isLoading) return;
    if (!currentProfile) return;
    if (currentProfile.role !== 'admin') { navigate({ to: '/home' }); return; }
    loadAll();
  }, [currentProfile, isLoading]);

  async function loadAll() {
    setLoading(true);
    try {
      const [c, cols, addon] = await Promise.all([getInviteCodes(), getCollections(), getSystemAddon()]);
      setCodes(c);
      setCollections(cols);
      setSystemAddon(addon);
      if (addon) setAddonUrlInput(addon.manifest_url);
    } finally {
      setLoading(false);
    }
  }

  async function handleGenerate() {
    await generateInviteCode(currentProfile!.id, maxUses, dateTimeInputToISO(newCodeExpiresAt));
    setCodes(await getInviteCodes());
  }

  async function handleRevoke(code: string) {
    await revokeInviteCode(code);
    setCodes(await getInviteCodes());
  }

  async function handleExpirationChange(code: string, value: string) {
    const expiresAt = dateTimeInputToISO(value);
    await updateInviteCodeExpiration(code, expiresAt);
    setCodes(prev => prev.map(c => c.code === code ? { ...c, expires_at: expiresAt } : c));
  }

  function dateTimeInputToISO(value: string): string | null {
    if (!value) return null;
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }

  function isoToDateTimeInput(value?: string | null): string {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const offsetMs = date.getTimezoneOffset() * 60_000;
    return new Date(date.getTime() - offsetMs).toISOString().slice(0, 16);
  }

  function isExpired(code: InviteCode): boolean {
    return !!code.expires_at && new Date(code.expires_at) <= new Date();
  }

  function codeStatus(code: InviteCode): string {
    if (code.used_by) return 'Used';
    if (!code.is_active) return 'Revoked';
    if (isExpired(code)) return 'Expired';
    return 'Active';
  }

  async function handleSaveAddon() {
    if (!addonUrlInput.trim()) return;
    setAddonSaving(true);
    try {
      const manifest = await fetch(addonUrlInput.trim()).then(r => r.json());
      await upsertSystemAddon(addonUrlInput.trim(), manifest.name || '');
      setSystemAddon(await getSystemAddon());
    } catch { alert('Could not fetch manifest. Check the URL.'); }
    setAddonSaving(false);
  }

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
    setExpandedRows(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n; });
  }

  function openAddFolder(collectionId: string) {
    setFolderModal({ open: true, collectionId, folder: {}, catalogInput: '' });
  }

  function openEditFolder(collectionId: string, folder: Folder) {
    const catalogStr = (folder.folder_catalogs || []).map(c => `${c.catalog_id}:${c.media_type}`).join(', ');
    setFolderModal({ open: true, collectionId, folder, catalogInput: catalogStr });
  }

  async function handleSaveFolder() {
    const { collectionId, folder, catalogInput } = folderModal;
    if (!folder?.name?.trim()) return;
    const catalogs = catalogInput.split(',').map(s => s.trim()).filter(Boolean).map(s => {
      const [catalog_id, media_type] = s.split(':').map(p => p.trim());
      return { catalog_id: catalog_id || s, media_type: media_type || 'movie' };
    });
    if (folder.id) {
      await updateFolder(folder.id, { name: folder.name, cover_image: folder.cover_image || '', focus_gif: folder.focus_gif || '', tile_shape: (folder as any).tile_shape || 'PORTRAIT' });
      await setFolderCatalogs(folder.id, catalogs);
    } else {
      const sortOrder = (collections.find(c => c.id === collectionId)?.folders?.length || 0);
      const newFolder = await createFolder(collectionId, folder.name, folder.cover_image || '', folder.focus_gif || '', sortOrder, (folder as any).tile_shape || 'PORTRAIT');
      await setFolderCatalogs(newFolder.id, catalogs);
    }
    setCollections(await getCollections());
    setFolderModal({ open: false, collectionId: '', folder: null, catalogInput: '' });
  }

  async function handleDeleteFolder(folderId: string) {
    if (!confirm('Delete this folder?')) return;
    await deleteFolder(folderId);
    setCollections(await getCollections());
  }

  if (loading) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-moonlit-accent border-t-transparent" />
        </div>
      </Sidebar>
    );
  }

  return (
    <Sidebar>
      <div className="-mt-14 pt-14 pb-8 bg-gradient-to-b from-moonlit-elevated to-transparent">
        <div className="px-6 pt-8 max-w-4xl">
          <h1 className="text-2xl font-bold text-white mb-6">Admin Panel</h1>
          <div className="inline-flex items-center gap-1 p-1.5 bg-[#1e1e1e]/90 border border-white/10 rounded-full">
            {(['collections', 'codes', 'stats'] as Section[]).map(s => (
              <button key={s} onClick={() => setSection(s)}
                className={`px-4 py-1.5 rounded-full text-xs font-semibold transition-all ${section === s ? 'bg-white/12 text-white' : 'text-white/45 hover:text-white/70'}`}>
                {s === 'codes' ? 'Invite Codes' : s.charAt(0).toUpperCase() + s.slice(1)}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="px-6 pb-12 max-w-4xl">
        {section === 'collections' && (
          <div>
            <div className="bg-moonlit-surface rounded-2xl p-4 mb-8">
              <p className="text-xs text-moonlit-muted uppercase tracking-widest mb-3">System Addon</p>
              <div className="flex gap-2">
                <input value={addonUrlInput} onChange={e => setAddonUrlInput(e.target.value)}
                  placeholder="https://your-addon.xyz/manifest.json"
                  className="flex-1 px-3 py-2 bg-moonlit-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-moonlit-accent" />
                <button onClick={handleSaveAddon} disabled={addonSaving}
                  className="px-4 py-2 bg-moonlit-accent rounded-xl text-sm disabled:opacity-50">
                  {addonSaving ? 'Saving...' : 'Save'}
                </button>
              </div>
              {systemAddon && <p className="text-xs text-green-400 mt-2">● Connected — {systemAddon.name || systemAddon.manifest_url}</p>}
            </div>

            <div className="flex gap-2 mb-4">
              <input value={newRowName} onChange={e => setNewRowName(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleAddRow()}
                placeholder="New collection row name…"
                className="flex-1 px-3 py-2 bg-moonlit-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-moonlit-accent" />
              <button onClick={handleAddRow} className="px-4 py-2 bg-moonlit-accent rounded-xl text-sm">+ Add Row</button>
            </div>

            <div className="space-y-3">
              {collections.map(col => (
                <div key={col.id} className="bg-moonlit-surface rounded-2xl overflow-hidden">
                  <div className="flex items-center justify-between px-4 py-3">
                    <button onClick={() => toggleExpand(col.id)} className="flex items-center gap-2 text-left flex-1">
                      <span className="text-sm font-semibold text-white">{col.name}</span>
                      <span className="text-xs text-moonlit-muted">{col.folders?.length || 0} folders</span>
                      <span className="text-moonlit-muted text-xs ml-1">{expandedRows.has(col.id) ? '▲' : '▼'}</span>
                    </button>
                    <button onClick={() => handleDeleteRow(col.id)} className="text-xs text-red-400 hover:text-red-300 ml-4">Delete</button>
                  </div>
                  {expandedRows.has(col.id) && (
                    <div className="border-t border-white/5 px-4 py-3 bg-moonlit-elevated/30">
                      <div className="flex flex-wrap gap-3 mb-3">
                        {(col.folders || []).map(folder => (
                          <div key={folder.id} className="relative group">
                            <div className="w-28 h-16 rounded-lg overflow-hidden bg-moonlit-elevated cursor-pointer" onClick={() => openEditFolder(col.id, folder)}>
                              {folder.cover_image
                                ? <img src={folder.cover_image} alt={folder.name} className="w-full h-full object-cover" />
                                : <div className="w-full h-full flex items-center justify-center"><span className="text-xs text-moonlit-muted text-center px-1">{folder.name}</span></div>}
                            </div>
                            <p className="text-xs text-moonlit-muted mt-1 truncate w-28">{folder.name}</p>
                            <button onClick={() => handleDeleteFolder(folder.id)}
                              className="absolute -top-1 -right-1 w-4 h-4 bg-red-500 rounded-full text-white text-xs hidden group-hover:flex items-center justify-center">×</button>
                          </div>
                        ))}
                        <button onClick={() => openAddFolder(col.id)}
                          className="w-28 h-16 rounded-lg border-2 border-dashed border-moonlit-muted/30 hover:border-moonlit-accent flex items-center justify-center text-moonlit-muted hover:text-moonlit-accent transition-colors text-xs">
                          + Add Folder
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              ))}
              {collections.length === 0 && <p className="text-sm text-moonlit-muted text-center py-8">No collection rows yet. Add one above.</p>}
            </div>
          </div>
        )}

        {section === 'codes' && (
          <div>
            <div className="flex gap-2 mb-4 items-center">
              <input type="number" value={maxUses} onChange={e => setMaxUses(Number(e.target.value))} min={1} max={100}
                className="w-20 px-3 py-2 bg-moonlit-elevated rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-moonlit-accent text-sm" />
              <span className="text-sm text-moonlit-muted">uses per code</span>
              <input type="datetime-local" value={newCodeExpiresAt} onChange={e => setNewCodeExpiresAt(e.target.value)}
                className="px-3 py-2 bg-moonlit-elevated rounded-xl text-white focus:outline-none focus:ring-2 focus:ring-moonlit-accent text-sm" />
              <button onClick={() => setNewCodeExpiresAt('')} className="text-xs text-moonlit-muted hover:text-white">Never</button>
              <button onClick={handleGenerate} className="ml-auto px-4 py-2 bg-moonlit-accent rounded-xl text-sm">Generate Code</button>
            </div>
            <div className="space-y-2">
              <p className="text-sm text-moonlit-muted mb-2">Active: {codes.filter(c => c.is_active && !c.used_by && !isExpired(c)).length} | Total: {codes.length}</p>
              {codes.map(code => (
                <div key={code.code} className="p-3 bg-moonlit-surface rounded-xl flex items-center justify-between gap-4">
                  <div>
                    <p className="font-mono font-bold">{code.code}</p>
                    <p className="text-xs text-moonlit-muted">Created: {new Date(code.created_at).toLocaleDateString()} • {codeStatus(code)}{code.expires_at && ` • expires ${new Date(code.expires_at).toLocaleString()}`}</p>
                    {code.used_by && (
                      <p className="text-xs text-moonlit-muted">Used by: {code.redeemed_by_label || code.used_by}{code.used_at && ` • ${new Date(code.used_at).toLocaleString()}`}</p>
                    )}
                  </div>
                  <div className="flex gap-2 items-center flex-wrap justify-end">
                    <input type="datetime-local" value={isoToDateTimeInput(code.expires_at)} onChange={e => handleExpirationChange(code.code, e.target.value)}
                      className="px-2 py-1.5 bg-moonlit-elevated rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-moonlit-accent text-xs" />
                    <button onClick={() => handleExpirationChange(code.code, '')} className="text-xs text-moonlit-muted hover:text-white">Never</button>
                    <span className={`w-2 h-2 rounded-full ${code.is_active && !code.used_by && !isExpired(code) ? 'bg-green-500' : code.used_by || isExpired(code) ? 'bg-red-500' : 'bg-gray-500'}`} />
                    {code.is_active && !code.used_by && !isExpired(code) && <button onClick={() => handleRevoke(code.code)} className="text-xs text-red-400 hover:text-red-300">Revoke</button>}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {section === 'stats' && (
          <div className="grid grid-cols-2 gap-4">
            {[
              { label: 'Total Invite Codes', value: codes.length },
              { label: 'Active Codes', value: codes.filter(c => c.is_active && !c.used_by).length },
              { label: 'Used Codes', value: codes.filter(c => c.used_by).length },
              { label: 'Collection Rows', value: collections.length },
            ].map(stat => (
              <div key={stat.label} className="p-4 bg-moonlit-surface rounded-xl text-center">
                <p className="text-2xl font-bold">{stat.value}</p>
                <p className="text-xs text-moonlit-muted">{stat.label}</p>
              </div>
            ))}
          </div>
        )}
      </div>

      {folderModal.open && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4">
          <div className="bg-moonlit-surface rounded-2xl p-6 w-full max-w-md">
            <h2 className="text-lg font-bold mb-4">{folderModal.folder?.id ? 'Edit Folder' : 'Add Folder'}</h2>
            <div className="space-y-3">
              {[
                { label: 'Folder name', key: 'name', placeholder: 'Netflix' },
                { label: 'Cover image URL', key: 'cover_image', placeholder: 'https://cdn.example.com/netflix.png' },
                { label: 'Hover GIF URL', key: 'focus_gif', placeholder: 'https://cdn.example.com/netflix.gif' },
              ].map(({ label, key, placeholder }) => (
                <div key={key}>
                  <label className="text-xs text-moonlit-muted mb-1 block">{label}</label>
                  <input value={(folderModal.folder as any)?.[key] || ''} placeholder={placeholder}
                    onChange={e => setFolderModal(prev => ({ ...prev, folder: { ...prev.folder, [key]: e.target.value } }))}
                    className="w-full px-3 py-2 bg-moonlit-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-moonlit-accent" />
                </div>
              ))}
              <div>
                <label className="text-xs text-moonlit-muted mb-1 block">Tile Shape</label>
                <div className="flex gap-2">
                  {(['PORTRAIT', 'LANDSCAPE'] as const).map(shape => (
                    <button key={shape} type="button"
                      onClick={() => setFolderModal(prev => ({ ...prev, folder: { ...prev.folder, tile_shape: shape } }))}
                      className={`flex-1 py-2 rounded-xl text-sm font-medium transition-all border ${(folderModal.folder?.tile_shape ?? 'PORTRAIT') === shape ? 'bg-moonlit-accent/20 border-moonlit-accent/40 text-moonlit-accent' : 'bg-moonlit-elevated border-transparent text-moonlit-muted hover:text-white'}`}>
                      {shape === 'PORTRAIT' ? '▭ Portrait' : '▬ Landscape'}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label className="text-xs text-moonlit-muted mb-1 block">Catalogs <span className="opacity-50">(catalog_id:media_type, comma-separated)</span></label>
                <input value={folderModal.catalogInput} placeholder="netflix-movies:movie, netflix-series:series"
                  onChange={e => setFolderModal(prev => ({ ...prev, catalogInput: e.target.value }))}
                  className="w-full px-3 py-2 bg-moonlit-elevated rounded-xl text-white text-sm focus:outline-none focus:ring-2 focus:ring-moonlit-accent" />
              </div>
            </div>
            <div className="flex gap-2 mt-5">
              <button onClick={() => setFolderModal({ open: false, collectionId: '', folder: null, catalogInput: '' })}
                className="flex-1 py-2 bg-moonlit-elevated rounded-xl text-sm">Cancel</button>
              <button onClick={handleSaveFolder} className="flex-1 py-2 bg-moonlit-accent rounded-xl text-sm">Save</button>
            </div>
          </div>
        </div>
      )}
    </Sidebar>
  );
}
