import { X } from 'lucide-react';
import type { MpvState } from '@/lib/platform/mpv';

interface AudioTrackPanelProps {
  state: MpvState;
  onClose: () => void;
  onSelectTrack?: (id: number) => void;
  onAudioDelay?: (delay: number) => void;
  audioDelay?: number;
}

export default function AudioTrackPanel({
  state,
  onClose,
  onSelectTrack,
  onAudioDelay,
  audioDelay = 0,
}: AudioTrackPanelProps) {
  const tracks = state.tracks.audio;

  return (
    <div className="absolute bottom-20 right-6 z-30 w-[360px] max-h-[70vh] overflow-y-auto rounded-ml-lg bg-player-elevated border border-player-edge shadow-ml-panel">
      <div className="flex items-center justify-between px-4 pt-3 pb-2.5">
        <div className="flex items-center gap-1.5">
          <span className="text-[14px] font-semibold text-player-ink">Audio</span>
          {tracks.length > 0 && (
            <span className="text-[11.5px] text-white/50">{tracks.length}</span>
          )}
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

      {tracks.length === 0 ? (
        <p className="px-4 py-3.5 text-[12.5px] text-white/50">No audio tracks available</p>
      ) : (
        <div className="p-1.5 space-y-0.5 max-h-[260px] overflow-y-auto">
          {tracks.map((t) => (
            <button
              key={t.id}
              type="button"
              className={`flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-left text-[12.5px] ${
                t.selected
                  ? 'bg-player-elevated border border-player-edge'
                  : 'hover:bg-white/5 border border-transparent'
              }`}
              onClick={() => {
                onSelectTrack?.(t.id);
                onClose();
              }}
            >
              <span
                className={`shrink-0 w-4 h-4 rounded-full flex items-center justify-center ${
                  t.selected ? 'bg-white' : 'bg-[#323335]'
                }`}
              >
                {t.selected && (
                  <span className="text-black text-[9px] font-bold">✓</span>
                )}
              </span>
              <span
                className={`truncate ${
                  t.selected ? 'text-player-ink font-medium' : 'text-player-ink-muted'
                }`}
              >
                {t.label}
              </span>
            </button>
          ))}
        </div>
      )}

      <div className="border-t border-player-edge" />

      <DelayRow
        title="Sync Offset"
        delay={audioDelay}
        disabled={tracks.length < 2}
        onDelay={onAudioDelay}
      />
    </div>
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
        {delay !== 0 && (
          <button
            type="button"
            className="w-6 h-6 rounded-md bg-[#323335] flex items-center justify-center text-white/60"
            onClick={() => onDelay?.(0)}
            aria-label="Reset delay"
          >
            ↺
          </button>
        )}
      </div>
      <div className="flex gap-2 mt-2">
        <button
          type="button"
          className="flex-1 h-[30px] rounded-lg bg-player-elevated text-[12px] font-semibold font-mono text-white/60 hover:text-white/90"
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
          className="flex-1 h-[30px] rounded-lg bg-player-elevated text-[12px] font-semibold font-mono text-white/60 hover:text-white/90"
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
