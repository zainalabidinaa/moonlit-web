import { X, Check, Monitor, Server, Play } from 'lucide-react';
import StrokeSpinner from '../StrokeSpinner';
import type { StreamItem } from '@/lib/types';

interface SourcePickerPanelProps {
  streams: StreamItem[];
  selected: StreamItem | null;
  onSelect: (s: StreamItem) => void;
  onClose: () => void;
  mode: 'auto' | 'manual';
}

export default function SourcePickerPanel({
  streams,
  selected,
  onSelect,
  onClose,
  mode,
}: SourcePickerPanelProps) {
  const grouped = groupByAddon(streams);

  return (
    <div className="absolute bottom-20 right-6 z-30 w-[400px] max-h-[70vh] overflow-y-auto rounded-ml-lg bg-player-elevated border border-player-edge shadow-ml-panel">
      <div className="flex items-center justify-between px-4 pt-3 pb-2.5">
        <div className="flex items-center gap-1.5">
          <span className="text-[14px] font-semibold text-player-ink">Sources</span>
          <span className="text-[11.5px] text-white/50">{streams.length}</span>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="w-6 h-6 rounded-full bg-white/10 flex items-center justify-center text-white/60 hover:text-white"
          aria-label="Close"
        >
          <X size={11} />
        </button>
      </div>

      <div className="border-t border-player-edge" />

      {mode === 'auto' && streams.length === 0 ? (
        <div className="flex items-center gap-3 px-4 py-5 text-[13px] text-player-ink-muted">
          <StrokeSpinner size={18} />
          <span>Finding the best stream...</span>
        </div>
      ) : (
        <div className="p-2 space-y-3 max-h-[55vh] overflow-y-auto">
          {grouped.map(([addon, items]) => (
            <div key={addon}>
              <p className="text-[10px] font-bold uppercase tracking-wider text-white/40 px-2 mb-1">
                {addon}
              </p>
              <div className="space-y-0.5">
                {items.map((stream, i) => {
                  const label = stream.title ?? stream.name ?? stream.description ?? `Stream ${i + 1}`;
                  const qualityMatch = label.match(/\b(4K|2160p|1440p|1080p|720p|480p)\b/i);
                  const quality = qualityMatch?.[1];
                  const is4K = quality?.toUpperCase() === '4K' || quality === '2160p';
                  const isSelected = selected?.url === stream.url;

                  return (
                    <button
                      key={`${stream.addonName ?? ''}-${i}`}
                      type="button"
                      className={`flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-left text-[12.5px] ${
                        isSelected
                          ? 'bg-player-elevated border border-player-edge'
                          : 'hover:bg-white/5 border border-transparent'
                      }`}
                      onClick={() => onSelect(stream)}
                    >
                      <span
                        className={`shrink-0 w-4 h-4 rounded-full flex items-center justify-center ${
                          isSelected ? 'bg-white' : 'bg-[#323335]'
                        }`}
                      >
                        {isSelected && (
                          <span className="text-black text-[9px] font-bold">✓</span>
                        )}
                      </span>
                      <span className={`truncate ${isSelected ? 'text-player-ink font-medium' : 'text-player-ink-muted'}`}>
                        {label.replace(/\n/g, ' · ')}
                      </span>
                      {quality && (
                        <span
                          className={`shrink-0 text-[9px] font-bold px-1.5 py-0.5 rounded ${
                            is4K
                              ? 'bg-sky-500/20 text-sky-300 border border-sky-500/30'
                              : 'bg-white/10 text-white/60 border border-white/10'
                          }`}
                        >
                          {quality.toUpperCase()}
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function groupByAddon(streams: StreamItem[]): [string, StreamItem[]][] {
  const map = new Map<string, StreamItem[]>();
  for (const s of streams) {
    const key = s.addonName ?? 'Unknown';
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(s);
  }
  return Array.from(map.entries());
}
