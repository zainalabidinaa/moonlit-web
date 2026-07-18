import { useState } from 'react';
import { X } from 'lucide-react';
import type { MpvState, MpvTrack } from '@/lib/platform/mpv';
import type { SubtitleItem } from '@/lib/stremio';
import { loadSubtitlePreferences, saveSubtitlePreferences, type SubtitlePreferences } from '@/lib/subtitle-preferences';

interface SubtitleTrackPanelProps {
  state: MpvState;
  externalSubtitles: SubtitleItem[];
  onSelectExternal: (s: SubtitleItem) => void;
  onDisableExternal: () => void;
  onSelectTrack?: (id: number | null) => void;
  onSubDelay?: (delay: number) => void;
  onClose: () => void;
}

export default function SubtitleTrackPanel({
  state,
  externalSubtitles,
  onSelectExternal,
  onDisableExternal,
  onSelectTrack,
  onSubDelay,
  onClose,
}: SubtitleTrackPanelProps) {
  const [prefs, setPrefs] = useState<SubtitlePreferences>(loadSubtitlePreferences);

  const applyPrefs = (next: SubtitlePreferences) => {
    setPrefs(next);
    saveSubtitlePreferences(next);
  };

  const isOff = !state.tracks.subs.some((s) => s.selected);
  const allTracks = [...state.tracks.subs, ...externalSubtitles.map((s) => ({ ...s }))];

  return (
    <div className="absolute bottom-20 right-6 z-30 w-[360px] max-h-[70vh] overflow-y-auto rounded-ml-lg bg-player-elevated border border-player-edge shadow-ml-panel">
      <div className="flex items-center justify-between px-4 pt-3 pb-2.5">
        <div className="flex items-center gap-1.5">
          <span className="text-[14px] font-semibold text-player-ink">Subtitles</span>
          <span className="text-[11.5px] text-white/50">{allTracks.length}</span>
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

      <div className="p-1.5 space-y-0.5 max-h-[200px] overflow-y-auto">
        <TrackRow
          selected={isOff}
          label="Off"
          onClick={() => {
            onSelectTrack?.(null);
            onDisableExternal();
            onClose();
          }}
        />

        {state.tracks.subs.map((t) => (
          <TrackRow
            key={`emb-${t.id}`}
            selected={t.selected}
            label={t.label}
            badges={['Embedded']}
            onClick={() => {
              onSelectTrack?.(t.id);
              onDisableExternal();
              onClose();
            }}
          />
        ))}

        {externalSubtitles.map((s) => (
          <TrackRow
            key={s.url}
            selected={false}
            label={s.name ?? s.lang}
            badges={['External']}
            onClick={() => {
              onSelectExternal(s);
              onClose();
            }}
          />
        ))}
      </div>

      <div className="border-t border-player-edge" />

      <div className="px-4 py-3 space-y-2">
        <div className="text-[11px] font-bold uppercase tracking-wider text-white/50">Appearance</div>

        <div className="flex gap-1">
          {(['small', 'medium', 'large', 'xlarge'] as const).map((size) => (
            <button
              key={size}
              type="button"
              onClick={() => applyPrefs({ ...prefs, size })}
              className={`rounded-md px-2 py-1 text-[11px] ${
                prefs.size === size ? 'bg-white text-black font-bold' : 'bg-white/10 text-white/70'
              }`}
            >
              {size === 'small' ? 'S' : size === 'medium' ? 'M' : size === 'large' ? 'L' : 'XL'}
            </button>
          ))}
        </div>

        <div className="flex gap-1">
          {(['white', 'yellow', 'cyan', 'green'] as const).map((color) => (
            <button
              key={color}
              type="button"
              aria-label={`Subtitle color ${color}`}
              onClick={() => applyPrefs({ ...prefs, color })}
              className={`h-6 w-6 rounded-full border-2 ${
                prefs.color === color ? 'border-white' : 'border-transparent'
              }`}
              style={{
                background:
                  color === 'white'
                    ? '#FFF'
                    : color === 'yellow'
                      ? '#FFD54A'
                      : color === 'cyan'
                        ? '#4AD8FF'
                        : '#4AFF6A',
              }}
            />
          ))}
        </div>
      </div>

      <div className="border-t border-player-edge" />

      <DelayRow
        title="Subtitle Sync"
        delay={state.subDelay}
        disabled={isOff}
        onDelay={onSubDelay}
      />
    </div>
  );
}

function TrackRow({
  selected,
  label,
  badges,
  onClick,
}: {
  selected: boolean;
  label: string;
  badges?: string[];
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      className={`flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-left text-[12.5px] ${
        selected
          ? 'bg-player-elevated border border-player-edge'
          : 'hover:bg-white/5 border border-transparent'
      }`}
      onClick={onClick}
    >
      <span
        className={`shrink-0 w-4 h-4 rounded-full flex items-center justify-center ${
          selected ? 'bg-white' : 'bg-[#323335]'
        }`}
      >
        {selected && <span className="text-black text-[9px] font-bold">✓</span>}
      </span>
      <span className={`truncate ${selected ? 'text-player-ink font-medium' : 'text-player-ink-muted'}`}>
        {label}
      </span>
      {badges?.map((b) => (
        <span
          key={b}
          className="text-[9px] font-bold tracking-wide px-[5px] py-px rounded bg-[#323335] text-white/60 border border-white/10"
        >
          {b}
        </span>
      ))}
    </button>
  );
}

function DelayRow({
  title,
  delay,
  disabled,
  onDelay,
}: {
  title: string;
  delay: number;
  disabled: boolean;
  onDelay?: (d: number) => void;
}) {
  return (
    <div className="px-4 py-3" style={{ opacity: disabled ? 0.4 : 1 }}>
      <div className="flex items-center justify-between text-[12px]">
        <span className="font-semibold text-player-ink">{title}</span>
        <span
          className={`text-[13px] font-bold font-mono ${
            delay !== 0 ? 'text-white' : 'text-player-ink-muted'
          }`}
        >
          {delay > 0 ? '+' : ''}
          {delay.toFixed(2)}s
        </span>
      </div>
      <div className="flex gap-2 mt-2">
        <button
          type="button"
          className="flex-1 h-[30px] rounded-lg bg-player-elevated text-[12px] font-semibold font-mono text-white/60"
          onClick={() => {
            const next = Math.round((delay - 0.1) * 100) / 100;
            onDelay?.(next);
          }}
          disabled={disabled}
        >
          −0.1s
        </button>
        <button
          type="button"
          className="flex-1 h-[30px] rounded-lg bg-player-elevated text-[12px] font-semibold font-mono text-white/60"
          onClick={() => {
            const next = Math.round((delay + 0.1) * 100) / 100;
            onDelay?.(next);
          }}
          disabled={disabled}
        >
          +0.1s
        </button>
      </div>
    </div>
  );
}
