import { useEffect, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { AppShell } from '../../components/layout/AppShell';
import { Button } from '../../components/ui/Button';
import { Card } from '../../components/ui/Card';
import {
  wipeCollections,
  importCollections,
  buildDiscoverMapFromAioConfig,
  type ImportResult,
} from '../../lib/importCollections';

interface Template {
  id: string;
  name: string;
  description: string | null;
  is_active: boolean;
  created_at: string;
  nuvio_json: unknown[];
  discover_map: Record<string, string> | null;
}

type ActivateState = 'idle' | 'wiping' | 'importing' | 'done' | 'error';

export default function TemplatesPage() {
  const [templates, setTemplates] = useState<Template[]>([]);
  const [loading, setLoading] = useState(true);

  // New template form
  const [showForm, setShowForm] = useState(false);
  const [newName, setNewName] = useState('');
  const [newDescription, setNewDescription] = useState('');
  const [nuvioFile, setNuvioFile] = useState<File | null>(null);
  const [aioFile, setAioFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // Activate state
  const [activatingId, setActivatingId] = useState<string | null>(null);
  const [activateState, setActivateState] = useState<ActivateState>('idle');
  const [progressLog, setProgressLog] = useState<string[]>([]);
  const [importResult, setImportResult] = useState<ImportResult | null>(null);
  const [activateError, setActivateError] = useState<string | null>(null);
  const logRef = useRef<HTMLDivElement>(null);

  useEffect(() => { loadTemplates(); }, []);

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [progressLog]);

  async function loadTemplates() {
    setLoading(true);
    const { data } = await supabase.from('collection_templates').select('*').order('created_at');
    setTemplates((data as Template[]) ?? []);
    setLoading(false);
  }

  async function handleSave() {
    if (!newName.trim() || !nuvioFile) { setSaveError('Name and Nuvio JSON are required.'); return; }
    setSaving(true);
    setSaveError(null);
    try {
      const nuvioText = await nuvioFile.text();
      const nuvioJson = JSON.parse(nuvioText);
      if (!Array.isArray(nuvioJson)) throw new Error('Nuvio JSON must be an array of collections.');

      let discoverMap: Record<string, string> | null = null;
      if (aioFile) {
        const aioText = await aioFile.text();
        const aioConfig = JSON.parse(aioText);
        discoverMap = buildDiscoverMapFromAioConfig(aioConfig);
      }

      const { error } = await supabase.from('collection_templates').insert({
        name: newName.trim(),
        description: newDescription.trim() || null,
        nuvio_json: nuvioJson,
        discover_map: discoverMap,
        is_active: false,
      });
      if (error) throw error;

      setShowForm(false);
      setNewName('');
      setNewDescription('');
      setNuvioFile(null);
      setAioFile(null);
      await loadTemplates();
    } catch (e) {
      setSaveError((e as Error).message);
    } finally {
      setSaving(false);
    }
  }

  async function handleActivate(template: Template) {
    setActivatingId(template.id);
    setActivateState('wiping');
    setProgressLog(['Wiping existing collections…']);
    setImportResult(null);
    setActivateError(null);

    try {
      await wipeCollections();
      setProgressLog(l => [...l, 'Wipe complete. Starting import…', '']);

      setActivateState('importing');
      const discoverMap = template.discover_map ?? {};
      const result = await importCollections(
        template.nuvio_json as Record<string, unknown>[],
        discoverMap,
        msg => setProgressLog(l => [...l, msg])
      );

      // Mark this template as active, others as inactive
      await supabase.from('collection_templates').update({ is_active: false }).neq('id', template.id);
      await supabase.from('collection_templates').update({ is_active: true }).eq('id', template.id);

      setImportResult(result);
      setActivateState('done');
      setProgressLog(l => [
        ...l,
        '',
        `✅ Done — ${result.collections} collections, ${result.folders} folders, ${result.sources} sources`,
      ]);
      await loadTemplates();
    } catch (e) {
      setActivateError((e as Error).message);
      setActivateState('error');
    }
  }

  async function handleDelete(id: string) {
    if (!confirm('Delete this template?')) return;
    await supabase.from('collection_templates').delete().eq('id', id);
    await loadTemplates();
  }

  function formatDate(iso: string) {
    return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  }

  const isActivating = activateState === 'wiping' || activateState === 'importing';

  return (
    <AppShell>
      <div className="space-y-8">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="font-display text-2xl font-bold text-text">Collection Templates</h1>
            <p className="mt-1 text-sm text-muted">
              Save Nuvio export profiles and switch between them to change what the app shows.
            </p>
          </div>
          <Button onClick={() => { setShowForm(v => !v); setSaveError(null); }}>
            {showForm ? 'Cancel' : '+ New Template'}
          </Button>
        </div>

        {/* New template form */}
        {showForm && (
          <Card className="p-6 space-y-4">
            <h2 className="font-semibold text-text">Upload Template</h2>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1">
                <label className="text-xs text-muted uppercase tracking-wide">Name *</label>
                <input
                  className="w-full rounded-lg border border-border bg-surface-2 px-3 py-2 text-sm text-text focus:outline-none focus:ring-1 focus:ring-accent"
                  placeholder="e.g. Anime Focus"
                  value={newName}
                  onChange={e => setNewName(e.target.value)}
                />
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted uppercase tracking-wide">Description</label>
                <input
                  className="w-full rounded-lg border border-border bg-surface-2 px-3 py-2 text-sm text-text focus:outline-none focus:ring-1 focus:ring-accent"
                  placeholder="Optional note"
                  value={newDescription}
                  onChange={e => setNewDescription(e.target.value)}
                />
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <FileDropZone
                label="Nuvio Collections JSON *"
                accept=".json"
                file={nuvioFile}
                hint="Export from Nuvio → Collections → Export Profile"
                onChange={setNuvioFile}
              />
              <FileDropZone
                label="AIOMetadata Config (optional)"
                accept=".json"
                file={aioFile}
                hint="Enables DISCOVER catalog resolution"
                onChange={setAioFile}
              />
            </div>

            {saveError && <p className="text-sm text-red-400">{saveError}</p>}

            <Button onClick={handleSave} loading={saving} disabled={!newName.trim() || !nuvioFile}>
              Save Template
            </Button>
          </Card>
        )}

        {/* Templates list */}
        {loading ? (
          <p className="text-sm text-muted">Loading…</p>
        ) : templates.length === 0 ? (
          <p className="text-sm text-muted">No templates yet. Upload one above.</p>
        ) : (
          <div className="space-y-3">
            {templates.map(t => (
              <Card key={t.id} className="p-5">
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-semibold text-text">{t.name}</span>
                      {t.is_active && (
                        <span className="inline-flex items-center gap-1.5 rounded-full border border-accent/40 px-2.5 py-0.5 font-mono text-[10px] uppercase tracking-widest text-accent">
                          <span className="h-1.5 w-1.5 rounded-full bg-accent shadow-glow" />
                          Active
                        </span>
                      )}
                    </div>
                    {t.description && <p className="mt-0.5 text-sm text-muted">{t.description}</p>}
                    <p className="mt-1 text-xs text-muted/60">
                      {Array.isArray(t.nuvio_json) ? t.nuvio_json.length : '?'} collections ·{' '}
                      {t.discover_map ? 'DISCOVER catalogs mapped' : 'No DISCOVER map'} ·{' '}
                      Added {formatDate(t.created_at)}
                    </p>
                  </div>

                  <div className="flex flex-none items-center gap-2">
                    <Button
                      variant={t.is_active ? 'secondary' : 'primary'}
                      size="sm"
                      disabled={isActivating}
                      loading={activatingId === t.id && isActivating}
                      onClick={() => handleActivate(t)}
                    >
                      {t.is_active ? 'Reactivate' : 'Activate'}
                    </Button>
                    {!t.is_active && (
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={isActivating}
                        onClick={() => handleDelete(t.id)}
                      >
                        Delete
                      </Button>
                    )}
                  </div>
                </div>

                {/* Progress log shown for the template being activated */}
                {activatingId === t.id && progressLog.length > 0 && (
                  <div className="mt-4 space-y-2">
                    <div
                      ref={logRef}
                      className="h-48 overflow-y-auto rounded-lg bg-[#0d0d0d] border border-border p-3 font-mono text-xs text-muted leading-relaxed"
                    >
                      {progressLog.map((line, i) => (
                        <div key={i} className={line.startsWith('✅') ? 'text-accent' : line.startsWith('  → error') ? 'text-red-400' : undefined}>
                          {line || ' '}
                        </div>
                      ))}
                      {isActivating && <span className="animate-pulse">▌</span>}
                    </div>

                    {activateState === 'done' && importResult && (
                      <div className="flex gap-6 rounded-lg bg-surface-2 border border-border px-4 py-3 text-sm">
                        <Stat label="Collections" value={importResult.collections} />
                        <Stat label="Folders" value={importResult.folders} />
                        <Stat label="Sources" value={importResult.sources} />
                        <Stat label="Skipped" value={importResult.skipped} />
                      </div>
                    )}
                    {activateState === 'error' && activateError && (
                      <p className="text-sm text-red-400">Error: {activateError}</p>
                    )}
                  </div>
                )}
              </Card>
            ))}
          </div>
        )}
      </div>
    </AppShell>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <div className="text-lg font-semibold text-text">{value}</div>
      <div className="text-xs text-muted">{label}</div>
    </div>
  );
}

function FileDropZone({
  label, accept, file, hint, onChange,
}: {
  label: string;
  accept: string;
  file: File | null;
  hint: string;
  onChange: (f: File | null) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);

  function handleDrop(e: React.DragEvent) {
    e.preventDefault();
    setDragging(false);
    const f = e.dataTransfer.files[0];
    if (f) onChange(f);
  }

  return (
    <div
      className={`relative flex flex-col items-center justify-center rounded-lg border-2 border-dashed px-4 py-6 text-center transition-colors cursor-pointer
        ${dragging ? 'border-accent bg-accent/5' : 'border-border hover:border-accent/50'}`}
      onDragOver={e => { e.preventDefault(); setDragging(true); }}
      onDragLeave={() => setDragging(false)}
      onDrop={handleDrop}
      onClick={() => inputRef.current?.click()}
    >
      <input
        ref={inputRef}
        type="file"
        accept={accept}
        className="sr-only"
        onChange={e => onChange(e.target.files?.[0] ?? null)}
      />
      <div className="text-xs font-medium text-muted uppercase tracking-wide mb-1">{label}</div>
      {file ? (
        <div className="text-sm text-accent font-medium truncate max-w-full">{file.name}</div>
      ) : (
        <>
          <div className="text-sm text-text">Drop file or click to browse</div>
          <div className="mt-1 text-xs text-muted/60">{hint}</div>
        </>
      )}
    </div>
  );
}
