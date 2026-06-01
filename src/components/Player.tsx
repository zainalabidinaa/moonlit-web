'use client';

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
  ChevronLeft, X, AlertTriangle,
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

function parseQuality(s: StreamItem): { label: string; color: string } {
  const t = `${s.name ?? ''} ${s.title ?? ''} ${s.description ?? ''}`.toLowerCase();
  if (t.includes('2160') || t.includes('4k') || t.includes('uhd')) return { label: '4K', color: 'text-yellow-400 bg-yellow-400/10' };
  if (t.includes('1080')) return { label: '1080p', color: 'text-blue-400 bg-blue-400/10' };
  if (t.includes('720')) return { label: '720p', color: 'text-slate-400 bg-slate-400/10' };
  return { label: 'SD', color: 'text-slate-500 bg-slate-500/10' };
}

const BAD_AUDIO = ['dts', 'truehd', 'atmos', 'remux', 'blu-ray', 'bluray'];
function isWebCompatAudio(s: StreamItem): boolean {
  const t = `${s.name ?? ''} ${s.title ?? ''} ${s.description ?? ''}`.toLowerCase();
  return !BAD_AUDIO.some(k => t.includes(k));
}

// Seek icon with number overlay (mimics SF Symbol gobackward/goforward)
function SeekIcon({ seconds, direction }: { seconds: number; direction: 'back' | 'fwd' }) {
  return (
    <div className="relative flex items-center justify-center w-14 h-14">
      {direction === 'back'
        ? <RotateCcw size={48} strokeWidth={1.5} className="text-white" />
        : <RotateCw size={48} strokeWidth={1.5} className="text-white" />}
      <span className="absolute text-white font-bold text-[13px] leading-none" style={{ marginTop: 2 }}>
        {seconds}
      </span>
    </div>
  );
}

// Inner component — must live inside <MediaPlayer> to call useMediaState
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
  playerRef: React.RefObject<MediaPlayerInstance>;
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
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
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

  return (
    <>
      {/* Vidstack subtitle overlay */}
      <Captions className="absolute bottom-24 left-0 right-0 z-10 text-center pointer-events-none" />

      {/* Buffering spinner */}
      {(waiting || !canPlay) && (
        <div className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none">
          <div className="w-14 h-14 rounded-full border-2 border-white/20 border-t-white animate-spin" />
        </div>
      )}

      {/* Controls layer */}
      <div
        className={`absolute inset-0 z-10 flex flex-col justify-between transition-opacity duration-300 select-none ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        onMouseMove={resetHide}
        onMouseLeave={() => { if (!paused && !showSources && !showSpeed) setShowControls(false); }}
        onClick={() => { if (!paused) resetHide(); }}
      >
        {/* TOP */}
        <div className="flex items-center justify-between px-8 pt-6 pb-20" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.8) 0%, transparent 100%)' }}>
          <button onClick={onBack} className="flex items-center gap-2 text-white/80 hover:text-white transition-colors font-medium text-base">
            <ChevronLeft size={22} strokeWidth={2} />
            Back
          </button>
          <p className="text-base font-semibold text-white/70 truncate max-w-[45%]">{title}</p>
          <button onClick={() => setShowSources(true)} className="flex items-center gap-2 bg-white/10 hover:bg-white/15 border border-white/10 rounded-xl px-4 py-2 transition-colors">
            {!isWebCompatAudio(currentStream) && <AlertTriangle size={13} className="text-yellow-400" />}
            <span className="text-sm font-medium text-white/65">{currentStream.addonName || 'Source'}</span>
          </button>
        </div>

        {/* CENTER */}
        <div className="flex items-center justify-center gap-16 pointer-events-auto">
          <SeekButton seconds={-15} className="opacity-75 hover:opacity-100 transition-opacity active:scale-90">
            <SeekIcon seconds={15} direction="back" />
          </SeekButton>

          <PlayButton className="hover:scale-110 active:scale-95 transition-transform pointer-events-auto">
            {paused
              ? <Play size={76} strokeWidth={0} fill="white" />
              : <Pause size={76} strokeWidth={0} fill="white" />}
          </PlayButton>

          <SeekButton seconds={15} className="opacity-75 hover:opacity-100 transition-opacity active:scale-90">
            <SeekIcon seconds={15} direction="fwd" />
          </SeekButton>
        </div>

        {/* BOTTOM */}
        <div className="px-8 pb-8 pt-20" style={{ background: 'linear-gradient(to top, rgba(0,0,0,0.88) 0%, transparent 100%)' }}>
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
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5 text-sm font-medium text-white/50 tabular-nums">
              <Time type="current" />
              <span className="text-white/25">·</span>
              <Time type="duration" />
            </div>

            <div className="flex items-center gap-0.5">
              <MuteButton className="w-11 h-11 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                <VolumeIcon size={22} strokeWidth={1.8} className="text-white/80" />
              </MuteButton>

              <CaptionButton className="w-11 h-11 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                <CaptionsIcon size={22} strokeWidth={1.8} className="text-white/80" />
              </CaptionButton>

              {/* Speed */}
              <div className="relative">
                <button
                  onClick={() => setShowSpeed(p => !p)}
                  className="w-11 h-11 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors text-sm font-bold text-white/55 hover:text-white"
                >
                  {speed === 1 ? '1×' : `${speed}×`}
                </button>
                {showSpeed && (
                  <div className="absolute bottom-full right-0 mb-3 bg-[#141414] border border-white/10 rounded-2xl p-1.5 min-w-[130px] z-30 shadow-xl">
                    {speeds.map(s => (
                      <button
                        key={s}
                        onClick={() => {
                          if (playerRef.current) playerRef.current.playbackRate = s;
                          setSpeed(s); setShowSpeed(false);
                        }}
                        className={`w-full text-left px-4 py-2.5 rounded-xl text-sm font-medium transition-colors ${s === speed ? 'text-white' : 'text-white/60 hover:bg-white/10 hover:text-white'}`}
                      >
                        {s === 1 ? 'Normal' : `${s}×`}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <FullscreenButton className="w-11 h-11 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                {fullscreen
                  ? <Minimize size={20} strokeWidth={1.8} className="text-white/80" />
                  : <Maximize size={20} strokeWidth={1.8} className="text-white/80" />}
              </FullscreenButton>
            </div>
          </div>
        </div>
      </div>

      {/* SOURCES PANEL */}
      {showSources && (
        <div className="absolute inset-0 z-40 flex justify-end">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowSources(false)} />
          <div className="relative w-80 max-w-[85vw] h-full bg-neutral-950 border-l border-white/10 overflow-y-auto">
            <div className="p-4 border-b border-white/10 flex items-center justify-between sticky top-0 bg-neutral-950 z-10">
              <h3 className="text-sm font-semibold text-white">Sources</h3>
              <button onClick={() => setShowSources(false)} className="p-2 rounded-full hover:bg-white/10">
                <X size={14} className="text-white/50" />
              </button>
            </div>
            {(() => {
              const compatible = streams.filter(isWebCompatAudio);
              if (compatible.length === 0) return (
                <div className="px-4 py-10 text-center">
                  <p className="text-white/40 text-sm">No web-compatible streams</p>
                  <p className="text-white/25 text-xs mt-1">All have DTS/TrueHD audio</p>
                </div>
              );
              const grp: Record<string, StreamItem[]> = {};
              for (const s of compatible) { const k = s.addonName || 'Unknown'; (grp[k] ??= []).push(s); }
              return Object.entries(grp).map(([name, items]) => (
                <div key={name} className="border-b border-white/5 last:border-b-0">
                  <p className="text-[10px] font-semibold text-white/25 uppercase tracking-wider px-4 pt-3 pb-1">{name}</p>
                  {items.map((s, i) => {
                    const isActive = s.url === currentStream.url;
                    const q = parseQuality(s);
                    const info = s.description?.replace(/\[.*?\]/g, '').trim() || s.title || s.name || 'Unknown';
                    return (
                      <button
                        key={s.url || `${name}-${i}`}
                        onClick={() => { setShowSources(false); onSwitchStream(s); }}
                        className={`w-full text-left px-4 py-3 hover:bg-white/5 flex items-center gap-3 transition-colors ${isActive ? 'border-l-2 border-white bg-white/5' : ''}`}
                      >
                        <span className={`text-[10px] font-bold px-2 py-0.5 rounded flex-shrink-0 ${q.color}`}>{q.label}</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm text-white/85 truncate">{info}</p>
                          {s.description && <p className="text-xs text-white/30 mt-0.5 truncate">{s.description}</p>}
                        </div>
                        {isActive && <div className="w-1.5 h-1.5 rounded-full bg-white flex-shrink-0" />}
                      </button>
                    );
                  })}
                </div>
              ));
            })()}
          </div>
        </div>
      )}
    </>
  );
}

export default function Player({
  streamUrl, streams, currentStream, title,
  mediaId, mediaType, startPosition, subtitles = [],
  onSwitchStream, onBack,
}: PlayerProps) {
  const playerRef = useRef<MediaPlayerInstance>(null);
  const { currentProfile } = useAuth();

  // Always try HLS.js first — many streams (Real-Debrid, AlOStreams etc.) are HLS
  // without .m3u8 in the URL. If HLS.js fails to parse the manifest, fall back to native.
  const [srcType, setSrcType] = useState<'application/x-mpegurl' | 'video/mp4'>('application/x-mpegurl');
  const src = { src: streamUrl, type: srcType };

  // Reset src type when stream changes
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
    // HLS.js failed (not an HLS stream) — retry with native video
    if (srcType === 'application/x-mpegurl') {
      setSrcType('video/mp4');
    }
  }, [srcType]);

  useEffect(() => {
    if (!currentProfile) return;
    const interval = setInterval(() => {
      const p = playerRef.current;
      if (p && p.currentTime > 0) {
        updateWatchProgress(currentProfile.id, mediaId, mediaType, p.currentTime, p.duration || 0, false);
      }
    }, 10000);
    return () => clearInterval(interval);
  }, [currentProfile, mediaId, mediaType]);

  const onEnded = useCallback(() => {
    const p = playerRef.current;
    if (!currentProfile || !p) return;
    updateWatchProgress(currentProfile.id, mediaId, mediaType, p.currentTime, p.duration || 0, true);
  }, [currentProfile, mediaId, mediaType]);

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
