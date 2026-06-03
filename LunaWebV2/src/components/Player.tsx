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
  ChevronLeft, X,
} from 'lucide-react';
import { useMediaState } from '@vidstack/react';
import { StreamItem } from '@/lib/types';
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

  if (!audioCompatible && (t.includes('remux') || t.includes('blu-ray') || t.includes('bluray'))) {
    audioCompatible = false;
  }

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

// ── PlayerUI (must live inside <MediaPlayer> to use useMediaState) ─────────

function PlayerUI({
  title, mediaLogo, currentStream, streams, subtitles,
  mediaId, mediaType, onBack, onSwitchStream, onPlaybackStalled, openSources, playerRef,
}: {
  title: string;
  mediaLogo?: string;
  currentStream: StreamItem;
  streams: StreamItem[];
  subtitles: SubtitleItem[];
  mediaId: string;
  mediaType: string;
  onBack: () => void;
  onSwitchStream: (s: StreamItem) => void;
  onPlaybackStalled: () => void;
  openSources?: boolean;
  playerRef: React.RefObject<MediaPlayerInstance | null>;
}) {
  const paused = useMediaState('paused');
  const waiting = useMediaState('waiting');
  const muted = useMediaState('muted');
  const volume = useMediaState('volume');
  const fullscreen = useMediaState('fullscreen');
  const canPlay = useMediaState('canPlay');

  const [showControls, setShowControls] = useState(true);
  const [showSources, setShowSources] = useState(false);
  const [showTracks, setShowTracks] = useState(false);
  const [showSpeed, setShowSpeed] = useState(false);
  const [speed, setSpeed] = useState(1);
  const [selectedSubtitleId, setSelectedSubtitleId] = useState<string>('off');
  const hideTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const speeds = [0.5, 0.75, 1, 1.25, 1.5, 2];

  const resetHide = useCallback(() => {
    setShowControls(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    if (!paused && !showSources && !showTracks && !showSpeed) {
      hideTimer.current = setTimeout(() => setShowControls(false), 3500);
    }
  }, [paused, showSources, showTracks, showSpeed]);

  useEffect(() => {
    if (paused) { setShowControls(true); if (hideTimer.current) clearTimeout(hideTimer.current); }
    else resetHide();
  }, [paused, resetHide]);

  useEffect(() => () => { if (hideTimer.current) clearTimeout(hideTimer.current); }, []);

  useEffect(() => { if (openSources) setShowSources(true); }, [openSources]);

  // Auto-unmute: player starts muted for reliable autoplay, unmute as soon as playback begins
  useEffect(() => {
    if (!paused && playerRef.current?.muted) {
      playerRef.current.muted = false;
    }
  }, [paused]);

  // Stall during buffering: waiting=true for 9s → try next stream
  useEffect(() => {
    if (!waiting) return;
    const timer = setTimeout(onPlaybackStalled, 9000);
    return () => clearTimeout(timer);
  }, [currentStream.url, onPlaybackStalled, waiting]);

  // Hard timeout: if canPlay never fires within 15s the stream is dead
  // (covers the case where waiting stays false but canPlay stays false —
  // e.g. silent HLS load failure, wrong source type, unreachable URL)
  useEffect(() => {
    if (canPlay) return;
    const timer = setTimeout(onPlaybackStalled, 15000);
    return () => clearTimeout(timer);
  }, [currentStream.url, canPlay, onPlaybackStalled]);

  const VolumeIcon = muted || volume === 0 ? VolumeX : volume < 0.5 ? Volume1 : Volume2;
  const currentMeta = parseStreamMeta(currentStream);
  const sourceName = currentStream.addonName && currentStream.addonName !== 'Direct' ? currentStream.addonName : 'Source';
  const sortedStreams = sortStreamsForBrowserPlayback(streams);

  function selectSubtitle(subtitleId: string) {
    setSelectedSubtitleId(subtitleId);
    const tracks = Array.from((playerRef.current?.textTracks ?? []) as Iterable<{ id?: string; label?: string; mode?: string }>);
    tracks.forEach(track => {
      const matches = subtitleId !== 'off' && (track.id === subtitleId || track.label === subtitleId);
      track.mode = matches ? 'showing' : 'disabled';
    });
  }

  return (
    <>
      {/* Subtitle overlay */}
      <Captions className="absolute bottom-24 left-0 right-0 z-10 text-center pointer-events-none" />

      {/* Buffering */}
      {(waiting || !canPlay) && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-5 z-20 pointer-events-none">
          {mediaLogo
            ? <img src={mediaLogo} alt={title} className="max-h-28 max-w-sm object-contain animate-pulse select-none" draggable={false} />
            : <span className="text-white/80 text-4xl font-black tracking-tight animate-pulse">{title}</span>}
          <div className="flex items-center gap-3 rounded-full border border-white/10 bg-black/45 px-4 py-2 backdrop-blur-xl">
            <span className="h-2 w-2 rounded-full bg-luna-accent animate-pulse" />
            <span className="text-sm font-semibold text-white/70">{sourceName}</span>
          </div>
          <div className="h-1 w-72 overflow-hidden rounded-full bg-white/10">
            <div className="h-full w-1/2 rounded-full bg-luna-accent animate-pulse" />
          </div>
        </div>
      )}

      {/* Controls layer */}
      <div
        className={`absolute inset-0 z-10 flex flex-col justify-between transition-opacity duration-300 select-none ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        onMouseMove={resetHide}
        onMouseLeave={() => { if (!paused && !showSources && !showTracks && !showSpeed) setShowControls(false); }}
        onClick={() => { if (!paused) resetHide(); }}
      >
        {/* TOP BAR */}
        <div className="flex items-center justify-between px-8 pt-6 pb-24" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.85) 0%, transparent 100%)' }}>
          <button onClick={onBack} className="flex items-center gap-2 text-white/80 hover:text-white transition-colors font-medium text-base">
            <ChevronLeft size={22} strokeWidth={2} />
            Back
          </button>
          <p className="text-base font-semibold text-white/70 truncate max-w-[45%]">{title}</p>
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
            <span className="text-sm font-medium text-white/65 ml-1">{currentStream.addonName || 'Source'}</span>
          </button>
        </div>

        <div className="flex-1" />

        {/* BOTTOM BAR */}
        <div className="px-6 pb-8 pt-24" style={{ background: 'linear-gradient(to top, rgba(0,0,0,0.88) 0%, transparent 100%)' }}>
          <p className="text-base font-bold text-white mb-4 truncate">{title}</p>

          {/* Scrubber */}
          <TimeSlider.Root className="group relative flex w-full items-center h-5 cursor-pointer mb-3">
            <TimeSlider.Track className="relative h-1 w-full rounded-full bg-white/20 group-hover:h-[5px] transition-all duration-150">
              <TimeSlider.TrackFill className="absolute h-full rounded-full bg-white" style={{ width: 'var(--slider-fill, 0%)' }} />
              <TimeSlider.Progress className="absolute h-full rounded-full bg-white/30" style={{ width: 'var(--slider-progress, 0%)' }} />
            </TimeSlider.Track>
            <TimeSlider.Thumb className="absolute top-1/2 -translate-y-1/2 w-4 h-4 rounded-full bg-white shadow-lg opacity-0 group-hover:opacity-100 -translate-x-1/2" style={{ left: 'var(--slider-fill, 0%)' }} />
            <TimeSlider.Preview className="absolute bottom-full -translate-x-1/2 mb-2 pointer-events-none">
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

            <div className="hidden flex-1 min-w-0 px-4 text-center md:block lg:px-8">
              <p className="truncate text-xl font-bold text-white">{title}</p>
            </div>

            <div className="flex min-w-0 items-center gap-2 justify-end sm:gap-4 md:min-w-[320px] lg:min-w-[360px]">
              <button onClick={() => setShowTracks(true)} className="w-12 h-12 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                <CaptionsIcon size={32} strokeWidth={1.8} className="text-white/90" />
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
        <div className="absolute inset-0 z-40 flex justify-end">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowSources(false)} />
          <div className="relative w-[460px] max-w-[92vw] h-full bg-[radial-gradient(circle_at_top_right,rgba(124,58,237,0.18),rgba(8,8,12,0.98)_42%)] border-l border-white/10 overflow-y-auto shadow-2xl backdrop-blur-2xl">
            <div className="p-6 border-b border-white/8 sticky top-0 bg-[#090910]/90 backdrop-blur-xl z-10">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-luna-accent">Now Playing</p>
                  <h3 className="mt-1 text-2xl font-black text-white">Sources</h3>
                  <p className="text-sm text-white/45 mt-1">Best browser-compatible streams first</p>
                </div>
                <button onClick={() => setShowSources(false)} className="p-2 rounded-full bg-white/5 hover:bg-white/10">
                  <X size={18} className="text-white/60" />
                </button>
              </div>
            </div>

            {sortedStreams.length === 0 ? (
              <div className="px-4 py-12 text-center">
                <p className="text-white/40 text-sm">{streams.length === 0 ? 'No sources found' : 'No browser-playable sources found'}</p>
              </div>
            ) : (
              <div className="p-4 space-y-3">
                {sortedStreams.map((s, i) => {
                  const meta = parseStreamMeta(s);
                  const sUrl = s.url || '';
                  const activeUrl = currentStream.url || currentStream.externalUrl || '';
                  const isActive = sUrl ? streamMatchesUrl(s, activeUrl) : s.title === currentStream.title;
                  const sourceLabel = [meta.debrid, meta.indexer].filter(Boolean).join(' · ') || s.addonName || 'Unknown';
                  const score = browserPlaybackScore(s);

                  return (
                    <button
                      key={sUrl || `stream-${i}`}
                      onClick={() => { setShowSources(false); onSwitchStream(s); }}
                      className={`w-full text-left p-4 rounded-3xl border transition-all duration-200 ${isActive ? 'border-luna-accent/80 bg-luna-accent/15 shadow-[0_0_30px_rgba(139,92,246,0.18)]' : 'border-white/10 bg-white/[0.045] hover:bg-white/[0.08] hover:border-white/20'}`}
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
                        <span className="text-xs text-white/40 font-semibold flex-shrink-0">#{i + 1}</span>
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
          </div>
        </div>
      )}

      {/* AUDIO + SUBTITLES PANEL */}
      {showTracks && (
        <div className="absolute inset-0 z-40 flex items-center justify-center px-6">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowTracks(false)} />
          <div className="relative w-[980px] max-w-[94vw] max-h-[76vh] overflow-hidden rounded-2xl bg-[#242424]/98 shadow-2xl border border-white/8">
            <div className="flex items-center justify-between px-8 py-6 border-b border-white/8">
              <div>
                <h3 className="text-2xl font-bold text-white">Audio & Subtitles</h3>
                <p className="text-sm text-white/45 mt-1">Choose audio tracks and captions for this stream</p>
              </div>
              <button onClick={() => setShowTracks(false)} className="p-2 rounded-full hover:bg-white/10">
                <X size={22} className="text-white/70" />
              </button>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-0 overflow-y-auto max-h-[60vh]">
              <div className="px-8 py-6 border-r border-white/8">
                <h4 className="text-xl font-bold text-white mb-5">Audio</h4>
                <button className="flex w-full items-center gap-4 py-3 text-left text-lg text-white">
                  <span className="w-5 text-white">✓</span>
                  <span>{currentMeta.audioCodec ? `${currentMeta.audioCodec} Audio` : 'Default Audio'}</span>
                </button>
                <p className="mt-4 text-sm leading-relaxed text-white/35">Additional audio tracks appear here when the stream exposes them to the browser.</p>
              </div>
              <div className="px-8 py-6">
                <h4 className="text-xl font-bold text-white mb-5">Subtitles</h4>
                <button onClick={() => selectSubtitle('off')} className={`flex w-full items-center gap-4 py-3 text-left text-lg ${selectedSubtitleId === 'off' ? 'text-white' : 'text-white/55 hover:text-white'}`}>
                  <span className="w-5 text-white">{selectedSubtitleId === 'off' ? '✓' : ''}</span>
                  <span>Off</span>
                </button>
                {subtitles.map(sub => (
                  <button key={sub.id} onClick={() => selectSubtitle(sub.id)} className={`flex w-full items-center gap-4 py-3 text-left text-lg ${selectedSubtitleId === sub.id ? 'text-white' : 'text-white/55 hover:text-white'}`}>
                    <span className="w-5 text-white">{selectedSubtitleId === sub.id ? '✓' : ''}</span>
                    <span>{sub.name || sub.lang || 'Subtitle'}</span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

// ── Main Player shell ──────────────────────────────────────────────────────

export default function Player({
  streamUrl, streams, currentStream, title, mediaLogo,
  mediaId, mediaType, startPosition, subtitles = [],
  onSwitchStream, onBack,
}: PlayerProps) {
  const playerRef = useRef<MediaPlayerInstance>(null);
  const savedFailoverPosition = useRef(0);
  const { currentProfile } = useAuth();

  const [srcType, setSrcType] = useState<VidstackSourceType>(() => getInitialSourceType(streamUrl, currentStream));
  const [playbackError, setPlaybackError] = useState<string | null>(null);
  const [forceOpenSources, setForceOpenSources] = useState(false);

  // Stable, memoized src object — prevents unnecessary Vidstack source updates
  const src = useMemo(() => ({ src: streamUrl, type: srcType }), [streamUrl, srcType]);

  useEffect(() => { setSrcType(getInitialSourceType(streamUrl, currentStream)); }, [currentStream, streamUrl]);
  useEffect(() => { setPlaybackError(null); setForceOpenSources(false); }, [mediaId]);

  const onProviderChange = useCallback((provider: MediaProviderAdapter | null) => {
    console.log('[player] provider:', provider?.constructor?.name ?? 'null', '| src:', streamUrl, '| type:', srcType);
    if (isHLSProvider(provider)) {
      const headers = currentStream.behaviorHints?.proxyHeaders?.request;
      // Mirror Stremio's hlsConfig.js — aggressive retries for slow/unstable debrid CDNs
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
    console.log('[player] error | srcType:', srcType, '| url:', streamUrl);
    // 1. Try flipping HLS ↔ MP4 (cheap, same URL)
    const fallback = getFallbackSourceType(srcType);
    if (fallback) {
      const p = playerRef.current;
      if (p?.currentTime) savedFailoverPosition.current = p.currentTime;
      setSrcType(fallback);
      return;
    }

    // 2. Remux fallback: a direct-play stream failed — retry the SAME stream
    //    through the remux server before giving up on it. Skip if already remuxed.
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

    // Stream failed — let the user pick a different source.
    setPlaybackError('This stream failed to play.');
  }, [onSwitchStream, srcType, streamUrl, currentStream]);

  useEffect(() => {
    if (!currentProfile) return;
    const interval = setInterval(() => {
      const p = playerRef.current;
      if (p && p.currentTime > 0) {
        updateWatchProgress(currentProfile.id, mediaId, mediaType, p.currentTime, p.duration || 0, false, title);
      }
    }, 10000);
    return () => clearInterval(interval);
  }, [currentProfile, mediaId, mediaType, title]);

  const onEnded = useCallback(() => {
    const p = playerRef.current;
    if (!currentProfile || !p) return;
    updateWatchProgress(currentProfile.id, mediaId, mediaType, p.currentTime, p.duration || 0, true, title);
  }, [currentProfile, mediaId, mediaType, title]);

  const onCanPlay = useCallback(() => {
    const resumeAt = savedFailoverPosition.current > 0 ? savedFailoverPosition.current : startPosition;
    if (resumeAt && resumeAt > 0 && playerRef.current) {
      playerRef.current.currentTime = resumeAt;
      savedFailoverPosition.current = 0;
    }
  }, [startPosition]);

  return (
    <div className="fixed inset-0 bg-black z-50">
      {/* Error overlay */}
      {playbackError && (
        <div className="absolute inset-0 z-50 flex flex-col items-center justify-center gap-4 bg-black/90">
          <p className="text-white text-lg font-semibold">Playback Error</p>
          <p className="text-white/50 text-sm">{playbackError}</p>
          <div className="flex gap-3 mt-2">
            <button onClick={onBack} className="px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full text-sm">Back</button>
            <button onClick={() => { setPlaybackError(null); setSrcType(getInitialSourceType(streamUrl, currentStream)); }} className="px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full text-sm">Retry</button>
            <button onClick={() => { setPlaybackError(null); setForceOpenSources(true); }} className="px-6 py-2.5 bg-luna-accent hover:bg-purple-400 text-white font-semibold rounded-full text-sm">Choose source</button>
          </div>
        </div>
      )}

      {/* key only on streamUrl — srcType changes update src prop without remounting */}
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
          <Track key={sub.id} src={sub.url} kind="subtitles" label={sub.name || sub.lang} language={sub.lang} />
        ))}

        <PlayerUI
          title={title}
          mediaLogo={mediaLogo}
          currentStream={currentStream}
          streams={streams}
          subtitles={subtitles}
          mediaId={mediaId}
          mediaType={mediaType}
          onBack={onBack}
          onSwitchStream={onSwitchStream}
          onPlaybackStalled={onError}
          openSources={forceOpenSources}
          playerRef={playerRef}
        />
      </MediaPlayer>
    </div>
  );
}
