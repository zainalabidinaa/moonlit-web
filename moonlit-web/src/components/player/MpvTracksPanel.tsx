import { useState } from 'react';
import { X } from 'lucide-react';
import { mpv, type MpvState } from '@/lib/platform/mpv';
import type { SubtitleItem } from '@/lib/stremio';
import { loadSubtitlePreferences, saveSubtitlePreferences, type SubtitlePreferences } from '@/lib/subtitle-preferences';
import { subtitlePrefsToMpvProps } from '@/lib/platform/mpv-subtitle-style';

export function MpvTracksPanel({ state, externalSubtitles, onClose }: {
  state: MpvState;
  externalSubtitles: SubtitleItem[];
  onClose: () => void;
}) {
  const [tab, setTab] = useState<'audio' | 'subtitles'>('subtitles');
  const [prefs, setPrefs] = useState<SubtitlePreferences>(loadSubtitlePreferences);
  const [addedExternal, setAddedExternal] = useState<Set<string>>(new Set());

  const applyPrefs = (next: SubtitlePreferences) => {
    setPrefs(next);
    saveSubtitlePreferences(next);
    for (const [k, v] of Object.entries(subtitlePrefsToMpvProps(next))) {
      mpv.setProp(k, v).catch(() => {});
    }
  };

  const selectAudio = (id: number) => mpv.setProp('aid', id);
  const selectSub = (id: number | 'no') => mpv.setProp('sid', id === 'no' ? 'no' : id);
  const addExternal = (sub: SubtitleItem) => {
    mpv.subAdd(sub.url, { title: sub.name ?? sub.lang, lang: sub.lang, select: true }).catch(() => {});
    setAddedExternal((s) => new Set(s).add(sub.url));
  };

  const Row = ({ selected, label, onClick }: { selected: boolean; label: string; onClick: () => void }) => (
    <button
      type="button" onClick={onClick}
      className={`flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-[13px] ${selected ? 'bg-white/15 text-player-ink font-semibold' : 'text-player-ink-muted hover:bg-white/8'}`}
    >
      <span className={`h-3.5 w-3.5 shrink-0 rounded-full border ${selected ? 'border-white bg-white' : 'border-white/40'}`} />
      <span className="truncate">{label}</span>
    </button>
  );

  const DelaySlider = ({ label, value, prop }: { label: string; value: number; prop: 'sub-delay' | 'audio-delay' }) => (
    <div className="px-3 py-2">
      <div className="flex justify-between text-[11px] text-player-ink-muted"><span>{label}</span><span>{value.toFixed(1)}s</span></div>
      <input type="range" min={-10} max={10} step={0.1} value={value}
        onChange={(e) => mpv.setProp(prop, Number(e.target.value))} className="w-full accent-white" aria-label={label} />
    </div>
  );

  return (
    <div className="absolute bottom-20 right-6 z-30 w-[340px] max-h-[70vh] overflow-y-auto rounded-ml-lg bg-player-elevated border border-player-edge shadow-ml-panel p-3">
      <div className="flex items-center justify-between pb-2">
        <div className="flex rounded-xl bg-white/[0.07] p-1">
          {(['subtitles', 'audio'] as const).map((t) => (
            <button key={t} type="button" onClick={() => setTab(t)}
              className={`rounded-lg px-3 py-1 text-[12px] font-semibold capitalize ${tab === t ? 'bg-white text-black' : 'text-white/60'}`}>
              {t}
            </button>
          ))}
        </div>
        <button type="button" aria-label="Close" onClick={onClose} className="text-white/60 hover:text-white"><X size={16} aria-hidden /></button>
      </div>

      {tab === 'audio' && (
        <>
          {state.tracks.audio.map((t) => <Row key={t.id} selected={t.selected} label={t.label} onClick={() => selectAudio(t.id)} />)}
          {state.tracks.audio.length === 0 && <div className="px-3 py-2 text-[12px] text-player-ink-muted">No audio tracks</div>}
          <DelaySlider label="Audio sync" value={state.audioDelay} prop="audio-delay" />
        </>
      )}

      {tab === 'subtitles' && (
        <>
          <Row selected={!state.tracks.subs.some((s) => s.selected)} label="Off" onClick={() => selectSub('no')} />
          {state.tracks.subs.map((t) => (
            <Row key={t.id} selected={t.selected} label={`${t.label}${t.external ? ' · ext' : ''}`} onClick={() => selectSub(t.id)} />
          ))}
          {externalSubtitles.filter((s) => !addedExternal.has(s.url)).length > 0 && (
            <div className="mt-2 border-t border-player-edge pt-2">
              <div className="px-3 pb-1 text-[11px] font-bold uppercase tracking-wider text-player-ink-muted">From addons</div>
              {externalSubtitles.filter((s) => !addedExternal.has(s.url)).slice(0, 20).map((s) => (
                <Row key={s.id + s.url} selected={false} label={`${s.lang}${s.name ? ` · ${s.name}` : ''}`} onClick={() => addExternal(s)} />
              ))}
            </div>
          )}
          <DelaySlider label="Subtitle sync" value={state.subDelay} prop="sub-delay" />

          <div className="mt-2 border-t border-player-edge pt-2 px-3 space-y-2">
            <div className="text-[11px] font-bold uppercase tracking-wider text-player-ink-muted">Appearance</div>
            <div className="flex gap-1">
              {(['small', 'medium', 'large', 'xlarge'] as const).map((size) => (
                <button key={size} type="button" onClick={() => applyPrefs({ ...prefs, size })}
                  className={`rounded-md px-2 py-1 text-[11px] ${prefs.size === size ? 'bg-white text-black font-bold' : 'bg-white/10 text-white/70'}`}>
                  {size === 'small' ? 'S' : size === 'medium' ? 'M' : size === 'large' ? 'L' : 'XL'}
                </button>
              ))}
            </div>
            <div className="flex gap-1">
              {(['white', 'yellow', 'cyan', 'green'] as const).map((color) => (
                <button key={color} type="button" aria-label={`Subtitle color ${color}`} onClick={() => applyPrefs({ ...prefs, color })}
                  className={`h-6 w-6 rounded-full border-2 ${prefs.color === color ? 'border-white' : 'border-transparent'}`}
                  style={{ background: color === 'white' ? '#FFF' : color === 'yellow' ? '#FFD54A' : color === 'cyan' ? '#4AD8FF' : '#4AFF6A' }} />
              ))}
            </div>
            <div>
              <div className="flex justify-between text-[11px] text-player-ink-muted"><span>Background</span><span>{prefs.backgroundOpacity}%</span></div>
              <input type="range" min={0} max={100} value={prefs.backgroundOpacity}
                onChange={(e) => applyPrefs({ ...prefs, backgroundOpacity: Number(e.target.value) })}
                className="w-full accent-white" aria-label="Subtitle background opacity" />
            </div>
            <div className="flex gap-1">
              {(['low', 'medium', 'high'] as const).map((position) => (
                <button key={position} type="button" onClick={() => applyPrefs({ ...prefs, position })}
                  className={`rounded-md px-2 py-1 text-[11px] capitalize ${prefs.position === position ? 'bg-white text-black font-bold' : 'bg-white/10 text-white/70'}`}>
                  {position}
                </button>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
