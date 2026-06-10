import { Input } from '../../../components/ui/Input';
import type { Collection } from '../../../types';

type Draft = Partial<Collection> & { name: string };

export function StepArtwork({ draft, onChange }: { draft: Draft; onChange: (d: Draft) => void }) {
  return (
    <div className="flex flex-col gap-4">
      <Input
        id="backdrop"
        label="Backdrop Image URL"
        type="url"
        value={draft.backdrop_image ?? ''}
        onChange={e => onChange({ ...draft, backdrop_image: e.target.value || null })}
        placeholder="https://..."
      />
      <div>
        <p className="text-sm font-medium text-text mb-2">View Mode</p>
        <div className="flex gap-2 flex-wrap">
          {['FOLLOW_LAYOUT', 'GRID', 'LIST'].map(mode => (
            <button
              key={mode}
              onClick={() => onChange({ ...draft, view_mode: mode })}
              className={`px-3 py-1.5 text-xs rounded-lg border transition-colors ${draft.view_mode === mode ? 'border-accent bg-accent-light text-accent' : 'border-border text-muted'}`}
            >
              {mode}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
