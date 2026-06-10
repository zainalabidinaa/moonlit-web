import { Badge } from '../../../components/ui/Badge';
import type { Collection } from '../../../types';

type Draft = Partial<Collection> & { name: string };

export function StepReview({ draft, hasGroups }: { draft: Draft; hasGroups: boolean }) {
  const rows: [string, string][] = [
    ['Name', draft.name],
    ['Structure', hasGroups ? 'With Groups' : 'Flat List'],
    ['View Mode', draft.view_mode ?? 'FOLLOW_LAYOUT'],
    ['Pin to Top', draft.pin_to_top ? 'Yes' : 'No'],
    ['Show All Tab', draft.show_all_tab ? 'Yes' : 'No'],
    ['Focus Glow', draft.focus_glow_enabled !== false ? 'On' : 'Off'],
    ['Backdrop', draft.backdrop_image ?? '(none)'],
  ];

  return (
    <div className="flex flex-col gap-3">
      {rows.map(([label, value]) => (
        <div key={label} className="flex items-start justify-between gap-4">
          <p className="text-sm text-muted shrink-0">{label}</p>
          <p className="text-sm text-text text-right truncate max-w-xs">{value}</p>
        </div>
      ))}
      <div className="pt-2">
        <Badge variant="success">Ready to save</Badge>
      </div>
    </div>
  );
}
