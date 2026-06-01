import { useEffect, useRef, useState, useCallback } from 'react';
import {
  MediaPlayer, MediaProvider, Track,
  PlayButton, MuteButton, FullscreenButton, SeekButton, CaptionButton,
  TimeSlider, Captions, Time,
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

interface PlayerProps {
  streamUrl: string;
  streams: StreamItem[];
  currentStream: StreamItem;
  title: string;
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
  const raw = `${s.name ?? ''} ${s.title ?? ''} ${s.description ?? ''}`;
  const t = raw.toLowerCase();

  // Resolution
  let resolution: StreamMeta['resolution'] = 'SD';
  let resolutionColor = 'text-slate-400 bg-slate-400/10';
  if (t.includes('2160') || t.includes('4k') || t.includes('uhd')) {
    resolution = '4K'; resolutionColor = 'text-yellow-400 bg-yellow-400/15';
  } else if (t.includes('1080')) {
    resolution = '1080p'; resolutionColor = 'text-blue-400 bg-blue-400/15';
  } else if (t.includes('720')) {
    resolution = '720p'; resolutionColor = 'text-slate-300 bg-slate-400/10';
  }

  // Video codec
  let videoCodec: string | null = null;
  if (t.includes('av1')) videoCodec = 'AV1';
  else if (t.includes('hevc') || t.includes('x265') || t.includes('h.265') || t.includes('h265')) videoCodec = 'HEVC';
  else if (t.includes('avc') || t.includes('x264') || t.includes('h.264') || t.includes('h264')) videoCodec = 'AVC';

  // Audio codec
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

  // HDR
  const hdr = t.includes('hdr') || t.includes('dolby vision') || t.includes(' dv ') || t.includes('[dv]');

  // File size — match patterns like "5.97 GB" or "1.2GB"
  const sizeMatch = raw.match(/(\d+\.?\d*)\s*(GB|MB|TB)/i);
  const sizeFmt = sizeMatch ? `${sizeMatch[1]} ${sizeMatch[2].toUpperCase()}` : null;

  // Debrid provider
  let debrid: string | null = null;
  if (t.includes('real-debrid') || t.includes('realdebrid') || t.includes('[rd]') || t.includes('(rd)') || / rd[ \])]/.test(t)) debrid = 'RD';
  else if (t.includes('torbox') || t.includes('[tb]') || t.includes('(tb)')) debrid = 'TB';
  else if (t.includes('premiumize') || t.includes('[pm]') || t.includes('(pm)')) debrid = 'PM';
  else if (t.includes('alldebrid') || t.includes('[ad]') || t.includes('(ad)')) debrid = 'AD';
  else if (t.includes('debrid-link') || t.includes('[dl]') || t.includes('(dl)')) debrid = 'DL';

  // Indexer — common names
  const indexers = ['knaben', 'yts', 'yify', '1337x', 'nyaa', 'rutor', 'rarbg', 'eztv', 'thepiratebay', 'tpb', 'zooqle'];
  const indexer = indexers.find(i => t.includes(i)) ?? null;

  // Release title — strip bracketed tokens
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
  title, currentStream, streams, subtitles,
  mediaId, mediaType, onBack, onSwitchStream, playerRef,
}: {
  title: string;
  currentStream: StreamItem;
  streams: StreamItem[];
  subtitles: SubtitleItem[];
  mediaId: string;
  mediaType: string;
  onBack: () => void;
  onSwitchStream: (s: StreamItem) => void;
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
  const [showSpeed, setShowSpeed] = useState(false);
  const [speed, setSpeed] = useState(1);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const speeds = [0.5, 0.75, 1, 1.25, 1.5, 2];

  const resetHide = useCallback(() => {
    setShowControls(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    if (!paused && !showSources && !showSpeed) {
      hideTimer.current = setTimeout(() => setShowControls(false), 3500);
    }
  }, [paused, showSources, showSpeed]);

  useEffect(() => {
    if (paused) { setShowControls(true); if (hideTimer.current) clearTimeout(hideTimer.current); }
    else resetHide();
  }, [paused, resetHide]);

  useEffect(() => () => { if (hideTimer.current) clearTimeout(hideTimer.current); }, []);

  const VolumeIcon = muted || volume === 0 ? VolumeX : volume < 0.5 ? Volume1 : Volume2;
  const currentMeta = parseStreamMeta(currentStream);

  // Source name for buffering overlay — strip generic fallbacks
  const sourceName = currentStream.addonName && currentStream.addonName !== 'Direct'
    ? currentStream.addonName
    : null;

  return (
    <>
      {/* Subtitle overlay */}
      <Captions className="absolute bottom-24 left-0 right-0 z-10 text-center pointer-events-none" />

      {/* Buffering state — show addon name pulsing when loading and controls hidden */}
      {(waiting || !canPlay) && !showControls && sourceName && (
        <div className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none">
          <span className="text-white/70 text-2xl font-bold tracking-wide animate-pulse select-none">
            {sourceName}
          </span>
        </div>
      )}
      {/* Fallback spinner when controls ARE visible or no source name */}
      {(waiting || !canPlay) && (showControls || !sourceName) && (
        <div className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none">
          <div className="w-12 h-12 rounded-full border-2 border-white/20 border-t-white animate-spin" />
        </div>
      )}

      {/* Controls layer */}
      <div
        className={`absolute inset-0 z-10 flex flex-col justify-between transition-opacity duration-300 select-none ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        onMouseMove={resetHide}
        onMouseLeave={() => { if (!paused && !showSources && !showSpeed) setShowControls(false); }}
        onClick={() => { if (!paused) resetHide(); }}
      >
        {/* TOP BAR */}
        <div className="flex items-center justify-between px-8 pt-6 pb-24" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.85) 0%, transparent 100%)' }}>
          <button onClick={onBack} className="flex items-center gap-2 text-white/80 hover:text-white transition-colors font-medium text-base">
            <ChevronLeft size={22} strokeWidth={2} />
            Back
          </button>
          <p className="text-base font-semibold text-white/70 truncate max-w-[45%]">{title}</p>
          {/* Source button shows current stream quality + compatibility warning */}
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

        {/* CENTER — empty, play/pause moved to bottom bar */}
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

          {/* Controls row — Netflix layout: time left | seek+play+seek center | icons right */}
          <div className="flex items-center justify-between">
            {/* Left: time */}
            <div className="flex items-center gap-1.5 text-sm font-medium text-white/50 tabular-nums w-28">
              <Time type="current" />
              <span className="text-white/25">·</span>
              <Time type="duration" />
            </div>

            {/* Center: seek back, play/pause, seek forward */}
            <div className="flex items-center gap-4">
              <SeekButton seconds={-15} className="opacity-75 hover:opacity-100 transition-opacity active:scale-90">
                <SeekIcon seconds={15} direction="back" />
              </SeekButton>

              <PlayButton className="hover:scale-110 active:scale-95 transition-transform">
                {paused
                  ? <Play size={56} strokeWidth={0} fill="white" />
                  : <Pause size={56} strokeWidth={0} fill="white" />}
              </PlayButton>

              <SeekButton seconds={15} className="opacity-75 hover:opacity-100 transition-opacity active:scale-90">
                <SeekIcon seconds={15} direction="fwd" />
              </SeekButton>
            </div>

            {/* Right: volume, captions, speed, fullscreen */}
            <div className="flex items-center gap-0.5 w-28 justify-end">
              <MuteButton className="w-10 h-10 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                <VolumeIcon size={20} strokeWidth={1.8} className="text-white/80" />
              </MuteButton>

              <CaptionButton className="w-10 h-10 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                <CaptionsIcon size={20} strokeWidth={1.8} className="text-white/80" />
              </CaptionButton>

              <div className="relative">
                <button
                  onClick={() => setShowSpeed(p => !p)}
                  className="w-10 h-10 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors text-sm font-bold text-white/55 hover:text-white"
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

              <FullscreenButton className="w-10 h-10 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                {fullscreen
                  ? <Minimize size={18} strokeWidth={1.8} className="text-white/80" />
                  : <Maximize size={18} strokeWidth={1.8} className="text-white/80" />}
              </FullscreenButton>
            </div>
          </div>
        </div>
      </div>

      {/* SOURCES PANEL */}
      {showSources && (
        <div className="absolute inset-0 z-40 flex justify-end">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowSources(false)} />
          <div className="relative w-84 max-w-[90vw] h-full bg-[#0e0e0e] border-l border-white/8 overflow-y-auto">
            <div className="p-4 border-b border-white/8 flex items-center justify-between sticky top-0 bg-[#0e0e0e] z-10">
              <div>
                <h3 className="text-sm font-semibold text-white">Sources</h3>
                <p className="text-[11px] text-white/30 mt-0.5">{streams.length} available</p>
              </div>
              <button onClick={() => setShowSources(false)} className="p-2 rounded-full hover:bg-white/10">
                <X size={14} className="text-white/50" />
              </button>
            </div>

            {streams.length === 0 ? (
              <div className="px-4 py-12 text-center">
                <p className="text-white/40 text-sm">No sources found</p>
              </div>
            ) : (
              <div className="p-2 space-y-1.5">
                {streams.map((s, i) => {
                  const meta = parseStreamMeta(s);
                  const isActive = (s.url && s.url === currentStream.url) || (s.url === undefined && s.title === currentStream.title);
                  const sourceLabel = [meta.debrid, meta.indexer].filter(Boolean).join(' · ') || s.addonName || 'Unknown';

                  return (
                    <button
                      key={s.url || `stream-${i}`}
                      onClick={() => { setShowSources(false); onSwitchStream(s); }}
                      className={`w-full text-left px-3.5 py-3 rounded-xl hover:bg-white/5 transition-colors ${isActive ? 'ring-1 ring-white/40 bg-white/5' : ''}`}
                    >
                      {/* Top row: badges + size */}
                      <div className="flex items-center justify-between gap-2 mb-1.5">
                        <div className="flex items-center gap-1 flex-wrap">
                          <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${meta.resolutionColor}`}>
                            {meta.resolution}
                          </span>
                          {meta.videoCodec && (
                            <span className="text-[10px] font-semibold text-white/50 bg-white/8 px-1.5 py-0.5 rounded">
                              {meta.videoCodec}
                            </span>
                          )}
                          {meta.audioCodec && (
                            <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded ${meta.audioCompatible ? 'text-emerald-400 bg-emerald-400/10' : 'text-red-400 bg-red-400/10'}`}>
                              {meta.audioCodec}
                            </span>
                          )}
                          {meta.hdr && (
                            <span className="text-[10px] font-semibold text-purple-400 bg-purple-400/10 px-1.5 py-0.5 rounded">
                              HDR
                            </span>
                          )}
                        </div>
                        {meta.sizeFmt && (
                          <span className="text-[11px] text-white/35 font-medium flex-shrink-0">{meta.sizeFmt}</span>
                        )}
                      </div>

                      {/* Source line */}
                      <p className="text-xs text-white/50 mb-0.5">{sourceLabel}</p>

                      {/* Release title */}
                      <p className="text-[11px] text-white/25 truncate leading-relaxed">{meta.releaseTitle}</p>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}

// ── Main Player shell ──────────────────────────────────────────────────────

export default function Player({
  streamUrl, streams, currentStream, title,
  mediaId, mediaType, startPosition, subtitles = [],
  onSwitchStream, onBack,
}: PlayerProps) {
  const playerRef = useRef<MediaPlayerInstance>(null);
  const { currentProfile } = useAuth();

  const [srcType, setSrcType] = useState<'application/x-mpegurl' | 'video/mp4'>('application/x-mpegurl');
  const src = { src: streamUrl, type: srcType };

  useEffect(() => { setSrcType('application/x-mpegurl'); }, [streamUrl]);

  const onProviderChange = useCallback((provider: MediaProviderAdapter | null) => {
    if (isHLSProvider(provider)) {
      const headers = currentStream.behaviorHints?.proxyHeaders?.request;
      provider.config = {
        renderTextTracksNatively: false,
        startLevel: -1,
        ...(headers && {
          xhrSetup: (xhr: XMLHttpRequest) => {
            for (const [k, v] of Object.entries(headers)) xhr.setRequestHeader(k, v);
          },
        }),
      };
    }
  }, [currentStream]);

  const onError = useCallback(() => {
    if (srcType === 'application/x-mpegurl') setSrcType('video/mp4');
  }, [srcType]);

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
    if (startPosition && startPosition > 0 && playerRef.current) {
      playerRef.current.currentTime = startPosition;
    }
  }, [startPosition]);

  return (
    <div className="fixed inset-0 bg-black z-50">
      <MediaPlayer
        ref={playerRef}
        src={src}
        autoPlay
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
          currentStream={currentStream}
          streams={streams}
          subtitles={subtitles}
          mediaId={mediaId}
          mediaType={mediaType}
          onBack={onBack}
          onSwitchStream={onSwitchStream}
          playerRef={playerRef}
        />
      </MediaPlayer>
    </div>
  );
}
