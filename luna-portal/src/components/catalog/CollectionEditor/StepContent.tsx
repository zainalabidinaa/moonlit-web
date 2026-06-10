import { useEffect, useRef, useState } from 'react';
import { supabase } from '../../../lib/supabase';
import { Input } from '../../../components/ui/Input';
import { Button } from '../../../components/ui/Button';
import { DragHandle } from '../../../components/ui/DragHandle';
import type { Folder, FolderSource } from '../../../types';

interface Props {
  collectionId: string | null;
  hasGroups: boolean;
  onHasGroupsChange: (v: boolean) => void;
}

export function StepContent({ collectionId, hasGroups, onHasGroupsChange }: Props) {
  const [folders, setFolders] = useState<Folder[]>([]);
  const [selectedFolder, setSelectedFolder] = useState<Folder | null>(null);
  const [sources, setSources] = useState<FolderSource[]>([]);
  const [newFolderName, setNewFolderName] = useState('');
  const [newSourceProvider, setNewSourceProvider] = useState('');
  const dragIndex = useRef<number | null>(null);

  useEffect(() => {
    if (!collectionId) return;
    supabase.from('folders').select('*').eq('collection_id', collectionId).order('sort_order').then(({ data }) => {
      const rows = data ?? [];
      setFolders(rows as Folder[]);
      if (rows.length > 0) onHasGroupsChange(true);
    });
  }, [collectionId]);

  useEffect(() => {
    if (!selectedFolder) return;
    supabase.from('folder_sources').select('*').eq('folder_id', selectedFolder.id).order('sort_order').then(({ data }) => setSources((data ?? []) as FolderSource[]));
  }, [selectedFolder]);

  async function addFolder() {
    if (!newFolderName.trim() || !collectionId) return;
    const { data } = await supabase.from('folders').insert({ collection_id: collectionId, name: newFolderName.trim(), sort_order: folders.length }).select().single();
    if (data) { setFolders(prev => [...prev, data as Folder]); setNewFolderName(''); onHasGroupsChange(true); }
  }

  async function addSource() {
    if (!newSourceProvider.trim() || !selectedFolder) return;
    const { data } = await supabase.from('folder_sources').insert({ folder_id: selectedFolder.id, provider: newSourceProvider.trim(), sort_order: sources.length }).select().single();
    if (data) { setSources(prev => [...prev, data as FolderSource]); setNewSourceProvider(''); }
  }

  function handleFolderDragStart(i: number) { dragIndex.current = i; }
  async function handleFolderDrop(i: number) {
    if (dragIndex.current === null || dragIndex.current === i) return;
    const reordered = [...folders];
    const [moved] = reordered.splice(dragIndex.current, 1);
    reordered.splice(i, 0, moved);
    setFolders(reordered);
    dragIndex.current = null;
    await Promise.all(reordered.map((f, idx) => supabase.from('folders').update({ sort_order: idx }).eq('id', f.id)));
  }

  return (
    <div className="flex flex-col gap-5">
      <div className="flex gap-3">
        {([false, true] as const).map(g => (
          <button key={String(g)} onClick={() => onHasGroupsChange(g)} className={`flex-1 py-2 rounded-lg border text-sm transition-colors ${hasGroups === g ? 'border-accent bg-accent-light text-accent' : 'border-border text-muted'}`}>
            {g ? 'With Groups' : 'Flat List'}
          </button>
        ))}
      </div>

      {hasGroups ? (
        <div className="grid grid-cols-2 gap-4">
          <div>
            <p className="text-xs font-medium text-muted mb-2 uppercase tracking-wide">Groups</p>
            <div className="flex flex-col gap-1 mb-3">
              {folders.map((f, i) => (
                <div
                  key={f.id}
                  className={`flex items-center gap-2 px-3 py-2 rounded-lg border cursor-pointer transition-colors ${selectedFolder?.id === f.id ? 'border-accent bg-accent-light' : 'border-border hover:border-accent/40'}`}
                  draggable
                  onDragStart={() => handleFolderDragStart(i)}
                  onDragOver={e => e.preventDefault()}
                  onDrop={() => handleFolderDrop(i)}
                  onClick={() => setSelectedFolder(f)}
                >
                  <DragHandle />
                  <span className="text-sm text-text truncate">{f.name}</span>
                </div>
              ))}
            </div>
            <div className="flex gap-2">
              <Input id="new-folder" value={newFolderName} onChange={e => setNewFolderName(e.target.value)} placeholder="Group name" className="flex-1" />
              <Button size="sm" onClick={addFolder}>Add</Button>
            </div>
          </div>
          <div>
            <p className="text-xs font-medium text-muted mb-2 uppercase tracking-wide">{selectedFolder ? `Sources — ${selectedFolder.name}` : 'Select a group'}</p>
            {selectedFolder && (
              <>
                <div className="flex flex-col gap-1 mb-3">
                  {sources.map(s => (
                    <div key={s.id} className="px-3 py-2 rounded-lg border border-border text-sm text-text truncate">{s.title ?? s.provider}</div>
                  ))}
                </div>
                <div className="flex gap-2">
                  <Input id="new-source" value={newSourceProvider} onChange={e => setNewSourceProvider(e.target.value)} placeholder="Provider / catalog ID" className="flex-1" />
                  <Button size="sm" onClick={addSource}>Add</Button>
                </div>
              </>
            )}
          </div>
        </div>
      ) : (
        <p className="text-sm text-muted">Use flat mode for a single source list. Switch to "With Groups" to add folder-based grouping.</p>
      )}
    </div>
  );
}
