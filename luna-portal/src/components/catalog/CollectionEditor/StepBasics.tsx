import { Input } from '../../../components/ui/Input';
import type { Collection } from '../../../types';

type Draft = Partial<Collection> & { name: string };

export function StepBasics({ draft, onChange }: { draft: Draft; onChange: (d: Draft) => void }) {
  return (
    <div className="flex flex-col gap-4">
      <Input id="coll-name" label="Name" value={draft.name} onChange={e => onChange({ ...draft, name: e.target.value })} required />
      <div className="flex gap-4 flex-wrap">
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={!!draft.pin_to_top} onChange={e => onChange({ ...draft, pin_to_top: e.target.checked })} className="accent-accent w-4 h-4" />
          <span className="text-sm text-text">Pin to top</span>
        </label>
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={!!draft.show_all_tab} onChange={e => onChange({ ...draft, show_all_tab: e.target.checked })} className="accent-accent w-4 h-4" />
          <span className="text-sm text-text">Show "All" tab</span>
        </label>
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={draft.focus_glow_enabled !== false} onChange={e => onChange({ ...draft, focus_glow_enabled: e.target.checked })} className="accent-accent w-4 h-4" />
          <span className="text-sm text-text">Focus glow</span>
        </label>
      </div>
    </div>
  );
}
