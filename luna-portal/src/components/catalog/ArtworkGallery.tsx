import { useEffect, useState } from 'react';
import type { Folder } from '../../types';
import { Button } from '../ui/Button';

type SlotKind = 'image' | 'logo' | 'video';
type ImageField = 'cover_image' | 'hero_backdrop' | 'title_logo' | 'focus_gif' | 'hero_video_url';

interface Slot {
  field: ImageField;
  label: string;
  kind: SlotKind;
  hint: string;
}

const SLOTS: Slot[] = [
  { field: 'cover_image', label: 'Cover', kind: 'image', hint: 'Tile artwork in the catalog grid' },
  { field: 'hero_backdrop', label: 'Hero backdrop', kind: 'image', hint: 'Full-width header behind the folder' },
  { field: 'title_logo', label: 'Title logo', kind: 'logo', hint: 'Transparent PNG shown over the hero' },
  { field: 'focus_gif', label: 'Focus GIF', kind: 'image', hint: 'Animated preview when the tile is focused' },
  { field: 'hero_video_url', label: 'Hero video', kind: 'video', hint: 'Looping background clip (mp4)' },
];

const TILE_SHAPES = ['POSTER', 'LANDSCAPE', 'SQUARE'];

interface Props {
  folder: Folder;
  onBack: () => void;
  onSave: (patch: Partial<Folder>) => Promise<void>;
}

/** Live-preview editor for every image + display field Luna renders for a folder. */
export function ArtworkGallery({ folder, onBack, onSave }: Props) {
  const [draft, setDraft] = useState<Folder>(folder);
  const [saving, setSaving] = useState(false);

  useEffect(() => setDraft(folder), [folder]);

  const dirty = SLOTS.some((s) => (draft[s.field] ?? '') !== (folder[s.field] ?? ''))
    || draft.hide_title !== folder.hide_title
    || draft.tile_shape !== folder.tile_shape
    || draft.focus_gif_enabled !== folder.focus_gif_enabled;

  function set<K extends keyof Folder>(key: K, value: Folder[K]) {
    setDraft((d) => ({ ...d, [key]: value }));
  }

  async function handleSave() {
    setSaving(true);
    await onSave({
      cover_image: draft.cover_image || null,
      hero_backdrop: draft.hero_backdrop || null,
      title_logo: draft.title_logo || null,
      focus_gif: draft.focus_gif || null,
      hero_video_url: draft.hero_video_url || null,
      hide_title: draft.hide_title,
      tile_shape: draft.tile_shape,
      focus_gif_enabled: draft.focus_gif_enabled,
    });
    setSaving(false);
  }

  return (
    <div>
      <div className="mb-5 flex items-center justify-between gap-4">
        <div>
          <p className="font-mono text-[11px] uppercase tracking-widest text-accent">Folder · {folder.name}</p>
          <p className="mt-1 text-sm text-muted">Every image slot Luna renders for this folder — set a URL and preview instantly.</p>
        </div>
        <div className="flex flex-none gap-2">
          <Button variant="ghost" size="sm" onClick={onBack}>‹ Folders</Button>
          <Button size="sm" loading={saving} disabled={!dirty} onClick={handleSave}>
            {dirty ? 'Save artwork' : 'Saved'}
          </Button>
        </div>
      </div>

      <div className="grid gap-4 [grid-template-columns:repeat(auto-fill,minmax(220px,1fr))]">
        {SLOTS.map((slot) => (
          <ArtworkSlot
            key={slot.field}
            slot={slot}
            value={(draft[slot.field] as string | null) ?? ''}
            onChange={(v) => set(slot.field, (v || null) as Folder[ImageField])}
          />
        ))}

        {/* Display flags */}
        <div className="overflow-hidden rounded-2xl border border-border bg-bg2">
          <div className="flex h-[130px] flex-wrap content-center items-center justify-center gap-5 bg-surface-2 p-4">
            <Toggle label="Hide title" on={!!draft.hide_title} onClick={() => set('hide_title', !draft.hide_title)} />
            <Toggle label="Focus glow" on={!!draft.focus_gif_enabled} onClick={() => set('focus_gif_enabled', !draft.focus_gif_enabled)} />
          </div>
          <div className="p-3.5">
            <div className="mb-2 flex items-center justify-between">
              <span className="text-[13px] font-semibold text-text">Display</span>
              <span className="rounded border border-accent/30 px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-wide text-accent">tile_shape</span>
            </div>
            <div className="flex gap-1.5">
              {TILE_SHAPES.map((shape) => (
                <button
                  key={shape}
                  onClick={() => set('tile_shape', shape)}
                  className={`flex-1 rounded-md border px-1 py-1.5 font-mono text-[9px] uppercase tracking-wide transition-colors ${
                    draft.tile_shape === shape ? 'border-accent bg-accent-light text-accent' : 'border-border text-muted hover:border-accent/40'
                  }`}
                >
                  {shape.slice(0, 4)}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function ArtworkSlot({ slot, value, onChange }: { slot: Slot; value: string; onChange: (v: string) => void }) {
  return (
    <div className="overflow-hidden rounded-2xl border border-border bg-bg2">
      <div
        className={`relative flex h-[130px] items-center justify-center overflow-hidden ${
          slot.kind === 'logo' ? 'bg-gradient-to-br from-[#10151b] to-[#0a0d12]' : 'bg-surface-2'
        }`}
      >
        {value ? (
          slot.kind === 'video' ? (
            <video src={value} muted loop autoPlay playsInline className="h-full w-full object-cover" />
          ) : (
            <img
              src={value}
              alt=""
              className={slot.kind === 'logo' ? 'max-h-full max-w-full object-contain p-4' : 'h-full w-full object-cover'}
            />
          )
        ) : (
          <div className="flex flex-col items-center gap-2 font-mono text-[11px] text-faint">
            <svg className="h-6 w-6 opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
              <path strokeLinecap="round" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            not set
          </div>
        )}
      </div>
      <div className="p-3.5">
        <div className="mb-2 flex items-center justify-between gap-2">
          <span className="text-[13px] font-semibold text-text">{slot.label}</span>
          <span className="flex-none rounded border border-accent/30 px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-wide text-accent">{slot.field}</span>
        </div>
        <input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="https://…"
          className="w-full rounded-lg border border-border bg-bg px-2.5 py-1.5 font-mono text-[10.5px] text-muted outline-none focus:border-accent"
        />
        <p className="mt-1.5 text-[11px] text-faint">{slot.hint}</p>
      </div>
    </div>
  );
}

function Toggle({ label, on, onClick }: { label: string; on: boolean; onClick: () => void }) {
  return (
    <label className="flex cursor-pointer flex-col items-center gap-1.5 text-xs text-muted" onClick={onClick}>
      <span className={`relative h-6 w-11 flex-none rounded-full border transition-colors ${on ? 'border-transparent bg-accent' : 'border-border bg-surface-2'}`}>
        <span className={`absolute top-0.5 h-[18px] w-[18px] rounded-full transition-all ${on ? 'left-[22px] bg-[#2a1206]' : 'left-0.5 bg-white'}`} />
      </span>
      {label}
    </label>
  );
}
