import type { MediaRailVariant } from '@/components/MediaRow';

export function catalogRailVariant(row: { title: string; viewMode?: string; tileShape?: string }): MediaRailVariant {
  const viewMode = row.viewMode?.toLowerCase().trim();
  const hint = `${viewMode ?? ''} ${row.title}`.toLowerCase();
  if (hint.includes('top 10') || hint.includes('top ten') || hint.includes('top10')) return 'top10';
  if (viewMode === 'cinematic' || hint.includes('cinematic')) return 'cinematic';
  if (viewMode === 'carousel' || hint.includes('carousel')) return 'carousel';
  if (viewMode === 'banner' || hint.includes('banner') || row.tileShape?.toLowerCase() === 'landscape') return 'banner';
  if (viewMode === 'stack' || hint.includes('stack')) return 'stack';
  return 'standard';
}
