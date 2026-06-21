import { useEffect, useRef, useState, useCallback, useMemo } from 'react';
import {
  MediaPlayer, MediaProvider, Track,
  PlayButton, MuteButton, FullscreenButton, SeekButton,
  TimeSlider, VolumeSlider, Captions,
  isHLSProvider,
  type MediaPlayerInstance, type MediaProviderAdapter,
} from '@vidstack/react';
import '@vidstack/react/player/styles/base.css';
import {
  Play, Pause, RotateCcw, RotateCw,
  Volume2, Volume1, VolumeX,
  Captions as CaptionsIcon, Maximize, Minimize,
  ChevronLeft, X, Headphones,
} from 'lucide-react';
import { useMediaState } from '@vidstack/react';
import { AddonManifest, StreamItem } from '@/lib/types';
import { SubtitleItem } from '@/lib/stremio';
import { updateWatchProgress } from '@/lib/services/api';
import { useAuth } from '@/app/AuthProvider';
import { browserPlaybackScore, getFallbackSourceType, getInitialSourceType, getPlayableStreamUrl, sortStreamsForBrowserPlayback, streamMatchesUrl, VidstackSourceType } from '@/lib/player-utils';
import { getStreamingServerUrl } from '@/lib/config';
import { buildRemuxUrl } from '@/lib/streaming-server';

interface PlayerProps {
  streamUrl: string;
  streams: StreamItem[];
  currentStream: StreamItem;
  title: string;
  mediaLogo?: string;
  mediaPoster?: string;
  mediaId: string;
  mediaType: string;
  startPosition?: number;
  subtitles?: SubtitleItem[];
  onSwitchStream: (stream: StreamItem) => void;
  onBack: () => void;
}

// ── Stream metadata parser ─────────────────────────────────────────────────

interface StreamMeta {
  resolution: '4K' | '1080p' | '720p' | 'SD';
  resolutionColor: string;
  videoCodec: string | null;
  audioCodec: string | null;
  audioCompatible: boolean;
  hdr: boolean;
  sizeFmt: string | null;
  debrid: string | null;
  indexer: string | null;
  releaseTitle: string;
}

function parseStreamMeta(s: StreamItem): StreamMeta {
  const raw = `${s.name ?? ''} ${s.title ?? ''} ${s.description ?? ''} ${s.behaviorHints?.filename ?? ''}`;
  const t = raw.toLowerCase();

  let resolution: StreamMeta['resolution'] = 'SD';
  let resolutionColor = 'text-slate-400 bg-slate-400/10';
  if (t.includes('2160') || t.includes('4k') || t.includes('uhd')) {
    resolution = '4K'; resolutionColor = 'text-yellow-400 bg-yellow-400/15';
  } else if (t.includes('1080')) {
    resolution = '1080p'; resolutionColor = 'text-blue-400 bg-blue-400/15';
  } else if (t.includes('720')) {
    resolution = '720p'; resolutionColor = 'text-slate-300 bg-slate-400/10';
  }

  let videoCodec: string | null = null;
  if (t.includes('av1')) videoCodec = 'AV1';
  else if (t.includes('hevc') || t.includes('x265') || t.includes('h.265') || t.includes('h265')) videoCodec = 'HEVC';
  else if (t.includes('avc') || t.includes('x264') || t.includes('h.264') || t.includes('h264')) videoCodec = 'AVC';

  let audioCodec: string | null = null;
  let audioCompatible = true;
  if (t.includes('truehd')) { audioCodec = 'TrueHD'; audioCompatible = false; }
  else if (t.includes('atmos')) { audioCodec = 'Atmos'; audioCompatible = false; }
  else if (t.includes('dts:x') || t.includes('dtsx')) { audioCodec = 'DTS-X'; audioCompatible = false; }
  else if (t.includes('dts-hd') || t.includes('dtshd')) { audioCodec = 'DTS-HD'; audioCompatible = false; }
  else if (t.includes('dts')) { audioCodec = 'DTS'; audioCompatible = false; }
  else if (t.includes('eac3') || t.includes('dd+') || t.includes('ddp') || t.includes('e-ac3')) { audioCodec = 'DD+'; audioCompatible = true; }
  else if (t.includes('ac3') || t.includes('dolby digital')) { audioCodec = 'DD'; audioCompatible = true; }
  else if (t.includes('aac')) { audioCodec = 'AAC'; audioCompatible = true; }

  const hdr = t.includes('hdr') || t.includes('dolby vision') || t.includes(' dv ') || t.includes('[dv]');

  const sizeMatch = raw.match(/(\d+\.?\d*)\s*(GB|MB|TB)/i);
  const sizeFmt = sizeMatch ? `${sizeMatch[1]} ${sizeMatch[2].toUpperCase()}` : null;

  let debrid: string | null = null;
  if (t.includes('real-debrid') || t.includes('realdebrid') || t.includes('[rd]') || t.includes('(rd)') || / rd[ \])]/.test(t)) debrid = 'RD';
  else if (t.includes('torbox') || t.includes('[tb]') || t.includes('(tb)')) debrid = 'TB';
  else if (t.includes('premiumize') || t.includes('[pm]') || t.includes('(pm)')) debrid = 'PM';
  else if (t.includes('alldebrid') || t.includes('[ad]') || t.includes('(ad)')) debrid = 'AD';
  else if (t.includes('debrid-link') || t.includes('[dl]') || t.includes('(dl)')) debrid = 'DL';

  const indexers = ['knaben', 'yts', 'yify', '1337x', 'nyaa', 'rutor', 'rarbg', 'eztv', 'thepiratebay', 'tpb', 'zooqle'];
  const indexer = indexers.find(i => t.includes(i)) ?? null;

  const releaseTitle = raw.replace(/\[.*?\]/g, '').replace(/\(.*?\)/g, '').replace(/\s{2,}/g, ' ').trim() || s.name || s.title || 'Unknown';

  return { resolution, resolutionColor, videoCodec, audioCodec, audioCompatible, hdr, sizeFmt, debrid, indexer, releaseTitle };
}

// ── Seek icon ─────────────────────────────────────────────────────────────

function SeekIcon({ seconds, direction }: { seconds: number; direction: 'back' | 'fwd' }) {
  return (
    <div className="relative flex items-center justify-center w-12 h-12">
      {direction === 'back'
        ? <RotateCcw size={42} strokeWidth={1.5} className="text-white" />
        : <RotateCw size={42} strokeWidth={1.5} className="text-white" />}
      <span className="absolute text-white font-bold text-[11px] leading-none" style={{ marginTop: 2 }}>
        {seconds}
      </span>
    </div>
  );
}

// ── Addon logo helper ──────────────────────────────────────────────────────

function AddonLogo({ logoUrl, name, size = 20 }: { logoUrl?: string; name?: string; size?: number }) {
  const [failed, setFailed] = useState(false);
  if (logoUrl && !failed) {
    return (
      <img
        src={logoUrl}
        alt={name}
        onError={() => setFailed(true)}
        className="object-contain rounded flex-shrink-0"
        style={{ width: size, height: size }}
      />
    );
  }
  return (
    <span
      className="flex items-center justify-center rounded bg-white/10 text-white/60 font-bold flex-shrink-0"
      style={{ width: size, height: size, fontSize: Math.max(8, size * 0.4) }}
    >
      {(name ?? '?')[0]?.toUpperCase()}
    </span>
  );
}

// ── SourcesPanel ──────────────────────────────────────────────────────────

function SourcesPanel({
  sortedStreams, streams, currentStream, addonLogos, onClose, onSwitchStream,
}: {
  sortedStreams: StreamItem[];
  streams: StreamItem[];
  currentStream: StreamItem;
  addonLogos: Record<string, string>;
  onClose: () => void;
  onSwitchStream: (s: StreamItem) => void;
}) {
  const allMetas = useMemo(() => sortedStreams.map(s => ({ stream: s, meta: parseStreamMeta(s) })), [sortedStreams]);
  const goodStreams = useMemo(
    () => allMetas.filter(({ meta }) => meta.audioCompatible && meta.debrid !== null).map(({ stream }) => stream),
    [allMetas]
  );
  const hasGoodStreams = goodStreams.length > 0;

  const [showAll, setShowAll] = useState(false);
  const [activeAddon, setActiveAddon] = useState<string | null>(null);

  const baseList = showAll || !hasGoodStreams ? sortedStreams : goodStreams;
  const addonNames = useMemo(
    () => [...new Set(baseList.map(s => s.addonName).filter(Boolean))] as string[],
    [baseList]
  );
  const filtered = activeAddon ? baseList.filter(s => s.addonName === activeAddon) : baseList;
  const hiddenCount = sortedStreams.length - goodStreams.length;

  const activeUrl = currentStream.url || currentStream.externalUrl || '';

  return (
    <div className="absolute inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-black/60" onClick={onClose} />
      <div className="relative w-[460px] max-w-[92vw] h-full bg-[radial-gradient(circle_at_top_right,rgba(124,58,237,0.18),rgba(8,8,12,0.98)_42%)] border-l border-white/10 flex flex-col shadow-2xl backdrop-blur-2xl">
        {/* Header */}
        <div className="p-6 border-b border-white/8 bg-[#090910]/90 backdrop-blur-xl shrink-0">
          <div className="flex items-start justify-between gap-4 mb-4">
            <div>
              <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-moonlit-accent">Now Playing</p>
              <h3 className="mt-1 text-2xl font-black text-white">Sources</h3>
            </div>
            <button onClick={onClose} className="p-2 rounded-full bg-white/5 hover:bg-white/10">
              <X size={18} className="text-white/60" />
            </button>
          </div>

          {addonNames.length > 1 && (
            <div className="flex gap-2 flex-wrap">
              <button
                onClick={() => setActiveAddon(null)}
                className={`px-3 py-1 rounded-full text-xs font-semibold transition-colors ${activeAddon === null ? 'bg-moonlit-accent text-white' : 'bg-white/8 text-white/50 hover:text-white hover:bg-white/12'}`}
              >
                All ({baseList.length})
              </button>
              {addonNames.map(name => (
                <button
                  key={name}
                  onClick={() => setActiveAddon(name)}
                  className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-colors ${activeAddon === name ? 'bg-moonlit-accent text-white' : 'bg-white/8 text-white/50 hover:text-white hover:bg-white/12'}`}
                >
                  {(addonLogos[name] || addonLogos[baseList.find(s => s.addonName === name)?.addonId ?? '']) && (
                    <AddonLogo logoUrl={addonLogos[name] || addonLogos[baseList.find(s => s.addonName === name)?.addonId ?? '']} name={name} size={14} />
                  )}
                  {name} ({baseList.filter(s => s.addonName === name).length})
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Stream list */}
        <div className="overflow-y-auto flex-1">
          {filtered.length === 0 ? (
            <div className="px-4 py-12 text-center">
              <p className="text-white/40 text-sm">
                {streams.length === 0 ? 'No sources found' : 'No sources found for this addon'}
              </p>
            </div>
          ) : (
            <div className="p-4 space-y-3">
              {filtered.map((s, i) => {
                const meta = parseStreamMeta(s);
                const sUrl = s.url || '';
                const isActive = sUrl ? streamMatchesUrl(s, activeUrl) : s.title === currentStream.title;
                const sourceLabel = [meta.debrid, meta.indexer].filter(Boolean).join(' · ') || s.addonName || 'Unknown';
                const score = browserPlaybackScore(s);
                const addonLogo = addonLogos[s.addonId ?? ''] || addonLogos[s.addonName ?? ''];

                return (
                  <button
                    key={sUrl || `stream-${i}`}
                    onClick={() => onSwitchStream(s)}
                    className={`w-full text-left p-4 rounded-3xl border transition-all duration-200 ${isActive ? 'border-moonlit-accent/80 bg-moonlit-accent/15 shadow-[0_0_30px_rgba(139,92,246,0.18)]' : 'border-white/10 bg-white/[0.045] hover:bg-white/[0.08] hover:border-white/20'}`}
                  >
                    <div className="flex items-center justify-between gap-3 mb-3">
                      <div className="flex items-center gap-1 flex-wrap">
                        <span className={`text-[11px] font-black px-2 py-1 rounded-lg ${meta.resolutionColor}`}>{meta.resolution}</span>
                        {meta.videoCodec && <span className="text-[10px] font-semibold text-white/50 bg-white/8 px-1.5 py-0.5 rounded">{meta.videoCodec}</span>}
                        {meta.audioCodec && (
                          <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded ${meta.audioCompatible ? 'text-emerald-400 bg-emerald-400/10' : 'text-red-400 bg-red-400/10'}`}>
                            {meta.audioCodec}
                          </span>
                        )}
                        {meta.hdr && <span className="text-[10px] font-semibold text-purple-400 bg-purple-400/10 px-1.5 py-0.5 rounded">HDR</span>}
                      </div>
                      {/* Addon logo + name */}
                      {s.addonName && activeAddon === null && (
                        <div className="flex items-center gap-1.5 flex-shrink-0">
                          <AddonLogo logoUrl={addonLogo} name={s.addonName} size={16} />
                          <span className="text-[10px] font-semibold text-white/35">{s.addonName}</span>
                        </div>
                      )}
                    </div>
                    <div className="flex items-center justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-base font-bold text-white/85 truncate">{sourceLabel}</p>
                        <p className="mt-1 text-xs text-white/35 truncate leading-relaxed">{meta.releaseTitle}</p>
                      </div>
                      <div className="flex-shrink-0 text-right">
                        {meta.sizeFmt && <p className="text-xs font-semibold text-white/45">{meta.sizeFmt}</p>}
                        <p className={`mt-1 text-[10px] font-bold uppercase ${score > 120 ? 'text-emerald-400' : score > 60 ? 'text-yellow-300' : 'text-red-300'}`}>
                          {score > 120 ? 'Best' : score > 60 ? 'OK' : 'Risky'}
                        </p>
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>
          )}

          {hasGoodStreams && hiddenCount > 0 && (
            <button
              onClick={() => { setShowAll(v => !v); setActiveAddon(null); }}
              className="w-full py-4 text-xs font-semibold text-white/35 hover:text-white/60 transition-colors border-t border-white/[0.06]"
            >
              {showAll ? `Show compatible only (${goodStreams.length})` : `Show all sources (${sortedStreams.length})`}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ── Netflix-style Audio / Subtitles panel ─────────────────────────────────

type TracksTab = 'audio' | 'subtitles';

function TracksPanel({
  tab: initialTab,
  audioTracks,
  selectedAudioIdx,
  subtitles,
  selectedSubtitleId,
  onSelectAudio,
  onSelectSubtitle,
  onClose,
}: {
  tab: TracksTab;
  audioTracks: { id: string; label: string; language: string; selected: boolean }[];
  selectedAudioIdx: number | null;
  subtitles: SubtitleItem[];
  selectedSubtitleId: string;
  onSelectAudio: (idx: number) => void;
  onSelectSubtitle: (sub: SubtitleItem | null) => void;
  onClose: () => void;
}) {
  const [tab, setTab] = useState<TracksTab>(initialTab);

  return (
    <div className="absolute inset-0 z-40 flex items-end sm:items-center justify-center">
      <div className="absolute inset-0 bg-black/75 backdrop-blur-sm" onClick={onClose} />
      <div className="relative w-full sm:w-[540px] max-h-[82vh] sm:max-h-[72vh] overflow-hidden rounded-t-2xl sm:rounded-2xl bg-[#141414] shadow-2xl border border-white/[0.08] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-6 pb-4 shrink-0">
          <div className="flex gap-1 bg-white/[0.07] rounded-xl p-1">
            <button
              onClick={() => setTab('audio')}
              className={`px-5 py-2 rounded-lg text-sm font-semibold transition-all ${tab === 'audio' ? 'bg-white text-black' : 'text-white/50 hover:text-white'}`}
            >
              Audio
            </button>
            <button
              onClick={() => setTab('subtitles')}
              className={`px-5 py-2 rounded-lg text-sm font-semibold transition-all ${tab === 'subtitles' ? 'bg-white text-black' : 'text-white/50 hover:text-white'}`}
            >
              Subtitles
            </button>
          </div>
          <button onClick={onClose} className="p-2 rounded-full hover:bg-white/10 transition-colors">
            <X size={20} className="text-white/60" />
          </button>
        </div>

        {/* Content */}
        <div className="overflow-y-auto flex-1 px-2 pb-6">
          {tab === 'audio' ? (
            audioTracks.length > 0 ? (
              <div className="space-y-0.5">
                {audioTracks.map((track, i) => {
                  const isSelected = selectedAudioIdx !== null ? selectedAudioIdx === i : track.selected;
                  const langNames = new Intl.DisplayNames(['en'], { type: 'language' });
                  let label = track.label || track.language || `Track ${i + 1}`;
                  try { if (track.language) label = langNames.of(track.language) || label; } catch {}
                  return (
                    <button
                      key={track.id || i}
                      onClick={() => onSelectAudio(i)}
                      className="w-full flex items-center gap-4 px-4 py-3.5 rounded-xl hover:bg-white/[0.06] transition-colors text-left group"
                    >
                      <div className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-colors ${isSelected ? 'border-white bg-white' : 'border-white/25 group-hover:border-white/40'}`}>
                        {isSelected && <div className="w-2 h-2 rounded-full bg-black" />}
                      </div>
                      <span className={`text-base transition-colors ${isSelected ? 'text-white font-semibold' : 'text-white/60'}`}>{label}</span>
                    </button>
                  );
                })}
              </div>
            ) : (
              <div className="px-4 py-8 text-center">
                <p className="text-white/35 text-sm">No alternate audio tracks for this stream</p>
              </div>
            )
          ) : (
            <div className="space-y-0.5">
              {/* Off option */}
              <button
                onClick={() => onSelectSubtitle(null)}
                className="w-full flex items-center gap-4 px-4 py-3.5 rounded-xl hover:bg-white/[0.06] transition-colors text-left group"
              >
                <div className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-colors ${selectedSubtitleId === 'off' ? 'border-white bg-white' : 'border-white/25 group-hover:border-white/40'}`}>
                  {selectedSubtitleId === 'off' && <div className="w-2 h-2 rounded-full bg-black" />}
                </div>
                <span className={`text-base transition-colors ${selectedSubtitleId === 'off' ? 'text-white font-semibold' : 'text-white/60'}`}>Off</span>
              </button>

              {subtitles.map(sub => {
                const isSelected = selectedSubtitleId === sub.id;
                return (
                  <button
                    key={sub.id}
                    onClick={() => onSelectSubtitle(sub)}
                    className="w-full flex items-center gap-4 px-4 py-3.5 rounded-xl hover:bg-white/[0.06] transition-colors text-left group"
                  >
                    <div className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-colors ${isSelected ? 'border-white bg-white' : 'border-white/25 group-hover:border-white/40'}`}>
                      {isSelected && <div className="w-2 h-2 rounded-full bg-black" />}
                    </div>
                    <div className="flex-1 min-w-0">
                      <span className={`text-base transition-colors ${isSelected ? 'text-white font-semibold' : 'text-white/60'}`}>
                        {sub.name || sub.lang || 'Subtitle'}
                      </span>
                    </div>
                    <span className="text-[10px] uppercase font-bold tracking-widest text-white/20 flex-shrink-0">{sub.lang}</span>
                  </button>
                );
              })}

              {subtitles.length === 0 && (
                <div className="px-4 py-8 text-center">
                  <p className="text-white/35 text-sm">No subtitles available</p>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ── PlayerUI (must live inside <MediaPlayer> to use useMediaState) ─────────

function PlayerUI({
  title, mediaLogo, currentStream, streams, subtitles, addonLogos,
  mediaId, mediaType, onBack, onSwitchStream, onPlaybackStalled, openSources, showControlsRef, playerRef, suppressErrorRef,
}: {
  title: string;
  mediaLogo?: string;
  currentStream: StreamItem;
  streams: StreamItem[];
  subtitles: SubtitleItem[];
  addonLogos: Record<string, string>;
  mediaId: string;
  mediaType: string;
  onBack: () => void;
  onSwitchStream: (s: StreamItem) => void;
  onPlaybackStalled: () => void;
  openSources?: boolean;
  showControlsRef?: React.MutableRefObject<(() => void) | null>;
  playerRef: React.RefObject<MediaPlayerInstance | null>;
  suppressErrorRef: React.MutableRefObject<boolean>;
}) {
  const paused = useMediaState('paused');
  const waiting = useMediaState('waiting');
  const muted = useMediaState('muted');
  const volume = useMediaState('volume');
  const fullscreen = useMediaState('fullscreen');
  const canPlay = useMediaState('canPlay');
  const audioTracks = useMediaState('audioTracks');
  const [selectedAudioIdx, setSelectedAudioIdx] = useState<number | null>(null);

  const [showControls, setShowControls] = useState(true);
  const [showSources, setShowSources] = useState(false);
  const [showTracksTab, setShowTracksTab] = useState<'audio' | 'subtitles' | null>(null);
  const [showSpeed, setShowSpeed] = useState(false);
  const [speed, setSpeed] = useState(1);
  const [selectedSubtitleId, setSelectedSubtitleId] = useState<string>('off');
  const hideTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const speeds = [0.5, 0.75, 1, 1.25, 1.5, 2];

  const resetHide = useCallback(() => {
    setShowControls(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    if (!paused && !showSources && !showTracksTab && !showSpeed) {
      hideTimer.current = setTimeout(() => setShowControls(false), 3500);
    }
  }, [paused, showSources, showTracksTab, showSpeed]);

  useEffect(() => {
    if (paused) { setShowControls(true); if (hideTimer.current) clearTimeout(hideTimer.current); }
    else resetHide();
  }, [paused, resetHide]);

  useEffect(() => () => { if (hideTimer.current) clearTimeout(hideTimer.current); }, []);

  useEffect(() => { if (openSources) setShowSources(true); }, [openSources]);

  useEffect(() => { if (showControlsRef) showControlsRef.current = resetHide; }, [showControlsRef, resetHide]);

  useEffect(() => {
    if (!paused && playerRef.current?.muted) {
      playerRef.current.muted = false;
    }
  }, [paused]);

  useEffect(() => {
    if (!waiting) return;
    const timer = setTimeout(onPlaybackStalled, 9000);
    return () => clearTimeout(timer);
  }, [currentStream.url, onPlaybackStalled, waiting]);

  useEffect(() => {
    if (canPlay) return;
    const timer = setTimeout(onPlaybackStalled, 15000);
    return () => clearTimeout(timer);
  }, [currentStream.url, canPlay, onPlaybackStalled]);

  function selectSubtitle(sub: SubtitleItem | null) {
    const id = sub?.id ?? 'off';
    setSelectedSubtitleId(id);
    try {
      const player = playerRef.current;
      if (!player) return;

      // Vidstack TextTrackList — use toArray() which is always safe,
      // fall back to index-based access if toArray is not present
      const tl = player.textTracks as any;
      const tracks: any[] = typeof tl?.toArray === 'function'
        ? tl.toArray()
        : Array.from({ length: tl?.length ?? 0 }, (_: unknown, i: number) => tl[i]).filter(Boolean);

      const targetLabel = sub ? (sub.name || sub.lang || '') : '';
      for (const track of tracks) {
        track.mode = (id !== 'off' && track.label === targetLabel) ? 'showing' : 'disabled';
      }
    } catch (e) {
      console.error('[subtitles] selectSubtitle error:', e);
    }
  }

  function selectAudioTrack(idx: number) {
    setSelectedAudioIdx(idx);
    suppressErrorRef.current = true;
    setTimeout(() => { suppressErrorRef.current = false; }, 2000);
    try {
      const list = [...(playerRef.current?.audioTracks ?? [])];
      const t = list[idx];
      if (t) (t as any).selected = true;
    } catch {}
  }

  const VolumeIcon = muted || volume === 0 ? VolumeX : volume < 0.5 ? Volume1 : Volume2;
  const currentMeta = parseStreamMeta(currentStream);
  const sortedStreams = sortStreamsForBrowserPlayback(streams);
  const hasMultipleAudioTracks = audioTracks.length > 1;

  const audioTrackItems = useMemo(() => audioTracks.map((t: any, i: number) => ({
    id: t.id || String(i),
    label: t.label || '',
    language: t.language || '',
    selected: !!t.selected,
  })), [audioTracks]);

  return (
    <>
      {/* Subtitle captions overlay — z-30 so it sits above the controls (z-10) */}
      <Captions className="absolute bottom-28 left-0 right-0 z-30 text-center pointer-events-none [&_*]:!text-white [&_*]:![text-shadow:0_2px_6px_rgba(0,0,0,1),0_0_2px_rgba(0,0,0,1)] [&_[data-media-cue]]:bg-black/70 [&_[data-media-cue]]:px-2 [&_[data-media-cue]]:py-0.5 [&_[data-media-cue]]:rounded" />

      {/* Buffering */}
      {(waiting || !canPlay) && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-5 z-20 pointer-events-none">
          {mediaLogo
            ? <img src={mediaLogo} alt={title} className="max-h-28 max-w-sm object-contain animate-pulse select-none" draggable={false} />
            : <span className="text-white/80 text-4xl font-black tracking-tight animate-pulse">{title}</span>}
          <div className="h-1 w-72 overflow-hidden rounded-full bg-white/10">
            <div className="h-full w-1/2 rounded-full bg-moonlit-accent animate-pulse" />
          </div>
        </div>
      )}

      {/* Unmute overlay */}
      {muted && !paused && (
        <button
          className="absolute bottom-20 right-6 z-30 flex items-center gap-2 rounded-full bg-black/70 backdrop-blur-md border border-white/15 px-4 py-2.5 text-white text-sm font-semibold hover:bg-black/90 transition-colors"
          onClick={() => { if (playerRef.current) playerRef.current.muted = false; }}
        >
          <svg viewBox="0 0 24 24" fill="currentColor" className="w-4 h-4"><path d="M16.5 12A4.5 4.5 0 0014 7.97v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51A8.796 8.796 0 0021 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06A8.99 8.99 0 0017.73 18l1.99 1.99L21 18.72l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"/></svg>
          Tap to unmute
        </button>
      )}

      {/* Controls layer */}
      <div
        className={`absolute inset-0 z-10 flex flex-col justify-between transition-opacity duration-300 select-none ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        onMouseMove={resetHide}
        onMouseLeave={() => { if (!paused && !showSources && !showTracksTab && !showSpeed) setShowControls(false); }}
        onClick={() => { if (!paused) resetHide(); }}
      >
        {/* TOP BAR — back + source badge only, no title */}
        <div className="flex items-center justify-between px-8 pt-6 pb-24" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.85) 0%, transparent 100%)' }}>
          <button onClick={onBack} className="flex items-center gap-2 text-white/80 hover:text-white transition-colors font-medium text-base">
            <ChevronLeft size={22} strokeWidth={2} />
            Back
          </button>
          <button
            onClick={() => setShowSources(true)}
            className="flex items-center gap-1.5 bg-white/10 hover:bg-white/15 border border-white/10 rounded-xl px-3 py-2 transition-colors"
          >
            <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${currentMeta.resolutionColor}`}>
              {currentMeta.resolution}
            </span>
            {!currentMeta.audioCompatible && (
              <span className="text-[10px] font-bold text-red-400 bg-red-400/15 px-1.5 py-0.5 rounded">
                {currentMeta.audioCodec ?? '!'}
              </span>
            )}
            <AddonLogo
              logoUrl={addonLogos[currentStream.addonId ?? ''] || addonLogos[currentStream.addonName ?? '']}
              name={currentStream.addonName}
              size={18}
            />
            <span className="text-sm font-medium text-white/65 ml-0.5">{currentStream.addonName || 'Source'}</span>
          </button>
        </div>

        <div className="flex-1" />

        {/* BOTTOM BAR */}
        <div className="px-6 pb-8 pt-24" style={{ background: 'linear-gradient(to top, rgba(0,0,0,0.88) 0%, transparent 100%)' }}>

          {/* Scrubber — time preview only shows on hover via data-[visible] */}
          <TimeSlider.Root className="group relative flex w-full items-center h-5 cursor-pointer mb-3">
            <TimeSlider.Track className="relative h-1 w-full rounded-full bg-white/20 group-hover:h-[5px] transition-all duration-150">
              <TimeSlider.TrackFill className="absolute h-full rounded-full bg-white" style={{ width: 'var(--slider-fill, 0%)' }} />
              <TimeSlider.Progress className="absolute h-full rounded-full bg-white/30" style={{ width: 'var(--slider-progress, 0%)' }} />
            </TimeSlider.Track>
            <TimeSlider.Thumb className="absolute top-1/2 -translate-y-1/2 w-4 h-4 rounded-full bg-white shadow-lg opacity-0 group-hover:opacity-100 -translate-x-1/2" style={{ left: 'var(--slider-fill, 0%)' }} />
            <TimeSlider.Preview
              className="absolute bottom-full -translate-x-1/2 mb-2 pointer-events-none opacity-0 data-[visible]:opacity-100 transition-opacity"
            >
              <TimeSlider.Value className="text-sm text-white bg-black/85 px-2 py-1 rounded-lg font-semibold whitespace-nowrap" type="pointer" format="time" />
            </TimeSlider.Preview>
          </TimeSlider.Root>

          {/* Controls row */}
          <div className="flex flex-wrap items-center justify-between gap-3 md:flex-nowrap md:gap-6">
            <div className="flex min-w-0 items-center gap-2 sm:gap-4 md:min-w-[320px] lg:min-w-[360px]">
              <PlayButton className="hover:scale-110 active:scale-95 transition-transform">
                {paused
                  ? <Play className="h-12 w-12 sm:h-16 sm:w-16" strokeWidth={0} fill="white" />
                  : <Pause className="h-12 w-12 sm:h-16 sm:w-16" strokeWidth={0} fill="white" />}
              </PlayButton>
              <SeekButton seconds={-15} className="opacity-75 hover:opacity-100 transition-opacity active:scale-90">
                <SeekIcon seconds={15} direction="back" />
              </SeekButton>
              <SeekButton seconds={15} className="opacity-75 hover:opacity-100 transition-opacity active:scale-90">
                <SeekIcon seconds={15} direction="fwd" />
              </SeekButton>
              <MuteButton className="w-12 h-12 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                <VolumeIcon size={32} strokeWidth={1.8} className="text-white/90" />
              </MuteButton>
              <VolumeSlider.Root className="group relative hidden w-28 items-center h-8 cursor-pointer sm:flex">
                <VolumeSlider.Track className="relative h-1 w-full rounded-full bg-white/20 group-hover:h-[5px] transition-all duration-150">
                  <VolumeSlider.TrackFill className="absolute h-full rounded-full bg-white" style={{ width: 'var(--slider-fill, 0%)' }} />
                </VolumeSlider.Track>
                <VolumeSlider.Thumb className="absolute top-1/2 -translate-y-1/2 w-3.5 h-3.5 rounded-full bg-white shadow-lg -translate-x-1/2" style={{ left: 'var(--slider-fill, 0%)' }} />
              </VolumeSlider.Root>
            </div>

            {/* Center: show logo when available, title text as fallback */}
            <div className="hidden flex-1 min-w-0 px-4 text-center md:flex md:items-center md:justify-center">
              {mediaLogo
                ? <img src={mediaLogo} alt={title} className="max-h-10 max-w-[200px] object-contain drop-shadow-lg" draggable={false} />
                : <p className="truncate text-base font-bold text-white/80">{title}</p>}
            </div>

            <div className="flex min-w-0 items-center gap-2 justify-end sm:gap-4 md:min-w-[320px] lg:min-w-[360px]">
              {/* Audio track button — only shown when multiple tracks exist */}
              {hasMultipleAudioTracks && (
                <button
                  onClick={() => setShowTracksTab('audio')}
                  className="w-12 h-12 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95"
                >
                  <Headphones size={28} strokeWidth={1.8} className="text-white/90" />
                </button>
              )}

              {/* Subtitles button */}
              <button
                onClick={() => setShowTracksTab('subtitles')}
                className="w-12 h-12 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95"
              >
                <CaptionsIcon
                  size={32}
                  strokeWidth={1.8}
                  className={selectedSubtitleId !== 'off' ? 'text-white' : 'text-white/90'}
                />
              </button>

              <div className="relative">
                <button
                  onClick={() => setShowSpeed(p => !p)}
                  className="w-12 h-12 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors text-base font-bold text-white/65 hover:text-white"
                >
                  {speed === 1 ? '1×' : `${speed}×`}
                </button>
                {showSpeed && (
                  <div className="absolute bottom-full right-0 mb-3 bg-[#141414] border border-white/10 rounded-2xl p-1.5 min-w-[130px] z-30 shadow-xl">
                    {speeds.map(s => (
                      <button key={s} onClick={() => { if (playerRef.current) playerRef.current.playbackRate = s; setSpeed(s); setShowSpeed(false); }}
                        className={`w-full text-left px-4 py-2.5 rounded-xl text-sm font-medium transition-colors ${s === speed ? 'text-white' : 'text-white/60 hover:bg-white/10 hover:text-white'}`}>
                        {s === 1 ? 'Normal' : `${s}×`}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <FullscreenButton className="w-12 h-12 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                {fullscreen
                  ? <Minimize size={32} strokeWidth={1.8} className="text-white/90" />
                  : <Maximize size={32} strokeWidth={1.8} className="text-white/90" />}
              </FullscreenButton>
            </div>
          </div>
        </div>
      </div>

      {/* SOURCES PANEL */}
      {showSources && (
        <SourcesPanel
          sortedStreams={sortedStreams}
          streams={streams}
          currentStream={currentStream}
          addonLogos={addonLogos}
          onClose={() => setShowSources(false)}
          onSwitchStream={(s) => { setShowSources(false); onSwitchStream(s); }}
        />
      )}

      {/* AUDIO + SUBTITLES PANEL */}
      {showTracksTab && (
        <TracksPanel
          tab={showTracksTab}
          audioTracks={audioTrackItems}
          selectedAudioIdx={selectedAudioIdx}
          subtitles={subtitles}
          selectedSubtitleId={selectedSubtitleId}
          onSelectAudio={selectAudioTrack}
          onSelectSubtitle={selectSubtitle}
          onClose={() => setShowTracksTab(null)}
        />
      )}
    </>
  );
}

// ── Main Player shell ──────────────────────────────────────────────────────

export default function Player({
  streamUrl, streams, currentStream, title, mediaLogo, mediaPoster,
  mediaId, mediaType, startPosition, subtitles = [],
  onSwitchStream, onBack,
}: PlayerProps) {
  const playerRef = useRef<MediaPlayerInstance>(null);
  const savedFailoverPosition = useRef(0);
  const suppressErrorRef = useRef(false);
  const { currentProfile, addons } = useAuth();

  // Build a logo lookup keyed by both addonId and addonName for flexible matching
  const addonLogos = useMemo(() => {
    const map: Record<string, string> = {};
    for (const a of (addons as AddonManifest[])) {
      if (a.logo) {
        if (a.id) map[a.id] = a.logo;
        if (a.name) map[a.name] = a.logo;
      }
    }
    return map;
  }, [addons]);

  const [srcType, setSrcType] = useState<VidstackSourceType>(() => getInitialSourceType(streamUrl, currentStream));
  const [playbackError, setPlaybackError] = useState<string | null>(null);
  const [forceOpenSources, setForceOpenSources] = useState(false);

  const src = useMemo(() => ({ src: streamUrl, type: srcType }), [streamUrl, srcType]);

  useEffect(() => { setSrcType(getInitialSourceType(streamUrl, currentStream)); }, [currentStream, streamUrl]);
  useEffect(() => { setPlaybackError(null); setForceOpenSources(false); }, [mediaId]);

  const onProviderChange = useCallback((provider: MediaProviderAdapter | null) => {
    console.log('[player] provider:', provider?.constructor?.name ?? 'null', '| src:', streamUrl, '| type:', srcType);
    if (isHLSProvider(provider)) {
      const headers = currentStream.behaviorHints?.proxyHeaders?.request;
      provider.config = {
        renderTextTracksNatively: false,
        startLevel: -1,
        enableWorker: true,
        backBufferLength: 30,
        maxBufferLength: 50,
        maxMaxBufferLength: 80,
        maxBufferHole: 0,
        manifestLoadingTimeOut: 30000,
        manifestLoadingMaxRetry: 10,
        fragLoadPolicy: {
          default: {
            maxTimeToFirstByteMs: 10000,
            maxLoadTimeMs: 120000,
            timeoutRetry: { maxNumRetry: 20, retryDelayMs: 0, maxRetryDelayMs: 15000 },
            errorRetry: { maxNumRetry: 6, retryDelayMs: 1000, maxRetryDelayMs: 15000 },
          },
        },
        ...(headers && {
          xhrSetup: (xhr: XMLHttpRequest) => {
            for (const [k, v] of Object.entries(headers)) xhr.setRequestHeader(k, v);
          },
        }),
      };
    }
  }, [currentStream]);

  const onError = useCallback(() => {
    if (suppressErrorRef.current) return;
    console.log('[player] error | srcType:', srcType, '| url:', streamUrl);
    const fallback = getFallbackSourceType(srcType);
    if (fallback) {
      const p = playerRef.current;
      if (p?.currentTime) savedFailoverPosition.current = p.currentTime;
      setSrcType(fallback);
      return;
    }

    const serverUrl = getStreamingServerUrl();
    const rawUrl = currentStream.url || '';
    if (serverUrl && rawUrl && !streamUrl.startsWith(serverUrl)) {
      console.log('[player] direct play failed → retrying via remux server');
      const p = playerRef.current;
      if (p?.currentTime) savedFailoverPosition.current = p.currentTime;
      onSwitchStream({
        ...currentStream,
        url: buildRemuxUrl(serverUrl, rawUrl, 'transcode'),
        behaviorHints: { ...currentStream.behaviorHints, webPlayableType: 'application/x-mpegurl' },
      });
      return;
    }

    setPlaybackError('This stream failed to play.');
  }, [onSwitchStream, srcType, streamUrl, currentStream]);

  useEffect(() => {
    if (!currentProfile) return;
    const interval = setInterval(() => {
      const p = playerRef.current;
      if (p && p.currentTime > 0) {
        updateWatchProgress(currentProfile.id, mediaId, mediaType, p.currentTime, p.duration || 0, false, title, mediaPoster);
      }
    }, 10000);
    return () => clearInterval(interval);
  }, [currentProfile, mediaId, mediaType, title, mediaPoster]);

  const onEnded = useCallback(() => {
    const p = playerRef.current;
    if (!currentProfile || !p) return;
    updateWatchProgress(currentProfile.id, mediaId, mediaType, p.currentTime, p.duration || 0, true, title, mediaPoster);
  }, [currentProfile, mediaId, mediaType, title, mediaPoster]);

  const onCanPlay = useCallback(() => {
    const resumeAt = savedFailoverPosition.current > 0 ? savedFailoverPosition.current : startPosition;
    if (resumeAt && resumeAt > 0 && playerRef.current) {
      playerRef.current.currentTime = resumeAt;
      savedFailoverPosition.current = 0;
    }
  }, [startPosition]);

  const showControlsRef = useRef<(() => void) | null>(null);

  return (
    <div className="fixed inset-0 bg-black z-50" onMouseMove={() => showControlsRef.current?.()}>
      {playbackError && (
        <div className="absolute inset-0 z-50 flex flex-col items-center justify-center gap-4 bg-black/90">
          <p className="text-white text-lg font-semibold">Playback Error</p>
          <p className="text-white/50 text-sm">{playbackError}</p>
          <div className="flex gap-3 mt-2">
            <button onClick={onBack} className="px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full text-sm">Back</button>
            <button onClick={() => { setPlaybackError(null); setSrcType(getInitialSourceType(streamUrl, currentStream)); }} className="px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full text-sm">Retry</button>
            <button onClick={() => { setPlaybackError(null); setForceOpenSources(true); }} className="px-6 py-2.5 bg-moonlit-accent hover:bg-moonlit-accent-dim text-white font-semibold rounded-full text-sm">Choose source</button>
          </div>
        </div>
      )}

      <MediaPlayer
        ref={playerRef}
        key={streamUrl}
        src={src}
        autoPlay
        muted
        playsInline
        style={{ width: '100%', height: '100%', position: 'absolute', inset: 0 }}
        onProviderChange={onProviderChange}
        onError={onError}
        onEnded={onEnded}
        onCanPlay={onCanPlay}
        title={title}
        keyShortcuts={{
          togglePaused: 'k Space',
          toggleMuted: 'm',
          toggleFullscreen: 'f',
          seekBackward: 'ArrowLeft',
          seekForward: 'ArrowRight',
          volumeUp: 'ArrowUp',
          volumeDown: 'ArrowDown',
        }}
      >
        <MediaProvider style={{ width: '100%', height: '100%' }} />

        {subtitles.map(sub => (
          <Track
            key={sub.id}
            src={sub.url}
            kind="subtitles"
            label={sub.name || sub.lang}
            language={sub.lang}
          />
        ))}

        <PlayerUI
          title={title}
          mediaLogo={mediaLogo}
          currentStream={currentStream}
          streams={streams}
          subtitles={subtitles}
          addonLogos={addonLogos}
          mediaId={mediaId}
          mediaType={mediaType}
          onBack={onBack}
          onSwitchStream={onSwitchStream}
          onPlaybackStalled={onError}
          openSources={forceOpenSources}
          showControlsRef={showControlsRef}
          suppressErrorRef={suppressErrorRef}
          playerRef={playerRef}
        />
      </MediaPlayer>
    </div>
  );
}
