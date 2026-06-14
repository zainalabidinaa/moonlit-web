import { useState } from 'react';
import type { Folder, FolderSource } from '../../types';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';

interface Props {
  folder: Folder;
  sources: FolderSource[];
  onAdd: (provider: string) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}

export function SourcesTable({ folder, sources, onAdd, onDelete }: Props) {
  const [provider, setProvider] = useState('');
  const [adding, setAdding] = useState(false);

  async function handleAdd() {
    if (!provider.trim()) return;
    setAdding(true);
    await onAdd(provider.trim());
    setProvider('');
    setAdding(false);
  }

  return (
    <div>
      <div className="mb-4 flex items-end justify-between gap-4">
        <div>
          <p className="font-mono text-[11px] uppercase tracking-widest text-accent">Folder · {folder.name}</p>
          <p className="mt-1 text-sm text-muted">Catalog sources resolved into this folder.</p>
        </div>
        <div className="flex flex-none items-end gap-2">
          <Input id="new-source" value={provider} onChange={(e) => setProvider(e.target.value)} placeholder="Provider / catalog id" className="w-56" />
          <Button size="sm" loading={adding} onClick={handleAdd}>+ Add</Button>
        </div>
      </div>

      {sources.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-border py-12 text-center font-mono text-xs text-faint">
          No sources yet
        </div>
      ) : (
        <table className="w-full border-collapse text-[13px]">
          <thead>
            <tr className="border-b border-border text-left font-mono text-[10px] uppercase tracking-wide text-faint">
              <th className="p-3 font-normal">Title</th>
              <th className="p-3 font-normal">Provider</th>
              <th className="p-3 font-normal">TMDB id</th>
              <th className="p-3 font-normal">Type</th>
              <th className="p-3" />
            </tr>
          </thead>
          <tbody>
            {sources.map((s) => (
              <tr key={s.id} className="border-b border-border hover:bg-surface">
                <td className="p-3 font-medium text-text">{s.title ?? '—'}</td>
                <td className="p-3 font-mono text-[12px] text-muted">{s.provider}</td>
                <td className="p-3 font-mono text-[12px] text-muted">{s.tmdb_id ?? '—'}</td>
                <td className="p-3">
                  {s.media_type && (
                    <span
                      className={`rounded px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-wide ${
                        s.media_type === 'movie' ? 'bg-cyan/10 text-cyan' : 'bg-magenta/10 text-magenta'
                      }`}
                    >
                      {s.media_type}
                    </span>
                  )}
                </td>
                <td className="p-3 text-right">
                  <button onClick={() => onDelete(s.id)} className="font-mono text-[11px] text-faint hover:text-red-400">remove</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
