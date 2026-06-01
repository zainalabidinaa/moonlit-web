'use client';

import { useEffect, useRef, useState, useCallback } from 'react';
import Hls from 'hls.js';
import { StreamItem } from '@/lib/types';
import { updateWatchProgress } from '@/lib/services/api';
import { useAuth } from '@/app/AuthProvider';

interface PlayerProps {
  streamUrl: string;
  streams: StreamItem[];
  currentStream: StreamItem;
  title: string;
  poster?: string;
  backdrop?: string;
  mediaId: string;
  mediaType: string;
  startPosition?: number;
  onSwitchStream: (stream: StreamItem) => void;
  onBack: () => void;
}

function formatTime(seconds: number): string {
  if (!isFinite(seconds) || seconds < 0) return '0:00';
  const s = Math.floor(seconds);
  const m = Math.floor(s / 60);
  const sec = s % 60;
  if (m >= 60) {
    const h = Math.floor(m / 60);
    const min = m % 60;
    return `${h}:${String(min).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
  }
  return `${m}:${String(sec).padStart(2, '0')}`;
}

export default function Player({
  streamUrl,
  streams,
  currentStream,
  title,
  poster,
  backdrop,
  mediaId,
  mediaType,
  startPosition,
  onSwitchStream,
  onBack,
}: PlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const progressInterval = useRef<ReturnType<typeof setInterval> | null>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const { currentProfile } = useAuth();

  const [state, setState] = useState<'loading' | 'playing' | 'paused' | 'ended' | 'error'>('loading');
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState(0);
  const [showControls, setShowControls] = useState(true);
  const [showSources, setShowSources] = useState(false);
  const [showAudioMenu, setShowAudioMenu] = useState(false);
  const [showSubMenu, setShowSubMenu] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const [volume, setVolume] = useState(1);
  const [muted, setMuted] = useState(false);
  const [audioTracks, setAudioTracks] = useState<{ id: number; name: string; lang: string }[]>([]);
  const [activeAudioTrack, setActiveAudioTrack] = useState(-1);
  const [subtitleTracks, setSubtitleTracks] = useState<{ id: number; name: string; lang: string }[]>([]);
  const [activeSubtitle, setActiveSubtitle] = useState(-1);
  const startPosRef = useRef<number | undefined>();

  useEffect(() => { startPosRef.current = startPosition; }, [startPosition]);

  // --- Init/cleanup hls.js ---
  const initPlayer = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;

    if (hlsRef.current) { hlsRef.current.destroy(); hlsRef.current = null; }
    video.src = '';

    setState('loading');
    setErrorMessage('');
    setAudioTracks([]);
    setActiveAudioTrack(-1);
    setSubtitleTracks([]);
    setActiveSubtitle(-1);

    const proxyHeaders = currentStream.behaviorHints?.proxyHeaders?.request;
    const hasHeaders = proxyHeaders != null && Object.keys(proxyHeaders).length > 0;
    const looksLikeHls = streamUrl.includes('.m3u8') || streamUrl.includes('/manifest') || streamUrl.includes('/playlist');
    const tryHls = (looksLikeHls || hasHeaders) && Hls.isSupported();

    if (tryHls) {
      let hlsErrorCount = 0;
      const hls = new Hls({
        xhrSetup(xhr) {
          if (hasHeaders) {
            for (const [key, value] of Object.entries(proxyHeaders!)) {
              xhr.setRequestHeader(key, value);
            }
          }
        },
      });

      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        hlsErrorCount = 0;
        // Try to grab tracks immediately (some streams have them ready here)
        const tracks = hls.audioTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || 'unknown' }));
        const subs = hls.subtitleTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || 'unknown' }));
        if (tracks.length > 0) {
          setAudioTracks(tracks);
          if (hls.audioTrack >= 0) setActiveAudioTrack(hls.audioTrack);
        }
        if (subs.length > 0) {
          setSubtitleTracks(subs);
          setActiveSubtitle(hls.subtitleTrack);
        }
        video.play().catch(() => {});
      });

      hls.on(Hls.Events.AUDIO_TRACKS_UPDATED, () => {
        const tracks = hls.audioTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || 'unknown' }));
        setAudioTracks(tracks);
        if (hls.audioTrack >= 0) setActiveAudioTrack(hls.audioTrack);
      });

      hls.on(Hls.Events.SUBTITLE_TRACKS_UPDATED, () => {
        const subs = hls.subtitleTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || 'unknown' }));
        setSubtitleTracks(subs);
        setActiveSubtitle(hls.subtitleTrack);
      });

      hls.on(Hls.Events.AUDIO_TRACK_SWITCHED, (_e, d) => setActiveAudioTrack(d.id));
      hls.on(Hls.Events.SUBTITLE_TRACK_SWITCH, (_e, d) => setActiveSubtitle(d.id));

      hls.on(Hls.Events.ERROR, (_event, data) => {
        hlsErrorCount++;
        if (data.fatal) {
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR && hlsErrorCount <= 1) {
            hls.destroy();
            hlsRef.current = null;
            video.src = '';
            video.src = streamUrl;
            video.play().catch(() => {});
          } else {
            setState('error');
            setErrorMessage(data.type === Hls.ErrorTypes.NETWORK_ERROR ? 'Network error' : 'Playback error');
            hls.destroy();
            hlsRef.current = null;
          }
        }
      });

      hls.loadSource(streamUrl);
      hls.attachMedia(video);
      hlsRef.current = hls;
    } else {
      video.src = streamUrl;
      video.play().catch(() => {});
    }
  }, [streamUrl, currentStream]);

  useEffect(() => {
    initPlayer();
    return () => { if (hlsRef.current) { hlsRef.current.destroy(); hlsRef.current = null; } };
  }, [initPlayer]);

  // --- Video events ---
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const onCanPlay = () => {
      setState('paused');
      if (startPosRef.current !== undefined && startPosRef.current > 0) {
        video.currentTime = startPosRef.current;
        startPosRef.current = undefined;
      }
    };
    const onPlay = () => setState('playing');
    const onPause = () => { if (!video.ended) setState('paused'); };
    const onEnded = () => setState('ended');
    const onError = () => { setState('error'); setErrorMessage('Failed to play this stream'); };
    const onTimeUpdate = () => {
      setPosition(video.currentTime);
      setDuration(video.duration || 0);
      if (video.buffered.length > 0) setBuffered(video.buffered.end(video.buffered.length - 1));
    };
    video.addEventListener('canplay', onCanPlay);
    video.addEventListener('play', onPlay);
    video.addEventListener('pause', onPause);
    video.addEventListener('ended', onEnded);
    video.addEventListener('error', onError);
    video.addEventListener('timeupdate', onTimeUpdate);
    return () => {
      video.removeEventListener('canplay', onCanPlay);
      video.removeEventListener('play', onPlay);
      video.removeEventListener('pause', onPause);
      video.removeEventListener('ended', onEnded);
      video.removeEventListener('error', onError);
      video.removeEventListener('timeupdate', onTimeUpdate);
    };
  }, [streamUrl]);

  // --- Progress tracking ---
  useEffect(() => {
    if (!currentProfile) return;
    progressInterval.current = setInterval(async () => {
      const video = videoRef.current;
      if (video && video.currentTime > 0) {
        await updateWatchProgress(currentProfile.id, mediaId, mediaType, video.currentTime, video.duration || 0, false);
      }
    }, 10000);
    return () => { if (progressInterval.current) clearInterval(progressInterval.current); };
  }, [currentProfile, mediaId, mediaType]);

  useEffect(() => {
    if (state === 'ended' && currentProfile) {
      updateWatchProgress(currentProfile.id, mediaId, mediaType, duration, duration, true);
    }
  }, [state, currentProfile, mediaId, mediaType, duration]);

  // --- Controls auto-hide on mouse move ---
  const resetHideTimer = useCallback(() => {
    setShowControls(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => {
      if (!showAudioMenu && !showSubMenu && !showSources) setShowControls(false);
    }, 3000);
  }, [showAudioMenu, showSubMenu, showSources]);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const onMove = () => {
      if (!showAudioMenu && !showSubMenu && !showSources) resetHideTimer();
    };
    const onLeave = () => { if (!showAudioMenu && !showSubMenu && !showSources) setShowControls(false); };
    el.addEventListener('mousemove', onMove);
    el.addEventListener('mouseleave', onLeave);
    resetHideTimer();
    return () => {
      el.removeEventListener('mousemove', onMove);
      el.removeEventListener('mouseleave', onLeave);
      if (hideTimer.current) clearTimeout(hideTimer.current);
    };
  }, [resetHideTimer, showAudioMenu, showSubMenu, showSources]);

  // --- Volume ---
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.volume = volume;
    video.muted = muted;
  }, [volume, muted]);

  // --- Playback controls ---
  const togglePlay = () => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) video.play().catch(() => {}); else video.pause();
  };
  const seek = (seconds: number) => {
    const video = videoRef.current;
    if (!video) return;
    video.currentTime = seconds;
    setPosition(seconds);
  };
  const skip = (s: number) => {
    const video = videoRef.current;
    if (!video) return;
    seek(Math.max(0, Math.min(video.duration || 0, video.currentTime + s)));
  };
  const toggleFullscreen = () => {
    const el = containerRef.current;
    if (!el) return;
    if (document.fullscreenElement) document.exitFullscreen();
    else el.requestFullscreen().catch(() => {});
  };
  const switchAudio = (id: number) => {
    if (hlsRef.current) {
      hlsRef.current.audioTrack = id;
      setActiveAudioTrack(id);
    }
    setShowAudioMenu(false);
  };
  const switchSubtitle = (id: number) => {
    if (hlsRef.current) {
      hlsRef.current.subtitleTrack = id;
      setActiveSubtitle(id);
    }
    setShowSubMenu(false);
  };
  const switchSource = (stream: StreamItem) => {
    setShowSources(false);
    onSwitchStream(stream);
  };

  // --- Keyboard shortcuts ---
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.key === ' ' || e.key === 'k') { e.preventDefault(); togglePlay(); }
      if (e.key === 'ArrowLeft') skip(-10);
      if (e.key === 'ArrowRight') skip(10);
      if (e.key === 'ArrowUp') setVolume(v => Math.min(1, v + 0.1));
      if (e.key === 'ArrowDown') setVolume(v => Math.max(0, v - 0.1));
      if (e.key === 'f') toggleFullscreen();
      if (e.key === 'm') setMuted(m => !m);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const bgSrc = backdrop || poster;

  return (
    <div ref={containerRef} className="fixed inset-0 bg-black z-50 select-none">

      {/* Video */}
      <video ref={videoRef} className="absolute inset-0 w-full h-full" playsInline onClick={togglePlay} />

      {/* Loading */}
      {state === 'loading' && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-5 bg-black/80 z-20">
          {bgSrc && <div className="absolute inset-0 bg-cover bg-center opacity-30 blur-md" style={{ backgroundImage: `url(${bgSrc})` }} />}
          <div className="relative z-10 flex flex-col items-center gap-5">
            {poster && <img src={poster} alt="" className="w-24 sm:w-32 rounded-xl shadow-2xl ring-1 ring-white/10" />}
            <h2 className="text-lg font-semibold text-white text-center max-w-sm px-4">{title}</h2>
            <div className="animate-spin rounded-full h-8 w-8 border-2 border-luna-accent border-t-transparent" />
            <p className="text-sm text-luna-muted">Loading from {currentStream.addonName || 'addon'}...</p>
          </div>
        </div>
      )}

      {/* Error */}
      {state === 'error' && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-black/90 z-20">
          <p className="text-white text-lg font-semibold">Playback Error</p>
          <p className="text-luna-muted text-sm">{errorMessage}</p>
          <div className="flex gap-3 mt-2">
            <button onClick={onBack} className="px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full text-sm">Back</button>
            <button onClick={initPlayer} className="px-6 py-2.5 bg-luna-accent hover:bg-purple-400 text-white font-semibold rounded-full text-sm">Retry</button>
          </div>
        </div>
      )}

      {/* Ended */}
      {state === 'ended' && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-black/80 z-20">
          <p className="text-white text-lg font-semibold">Finished</p>
          <button onClick={onBack} className="px-6 py-2.5 bg-luna-accent hover:bg-purple-400 text-white font-semibold rounded-full text-sm">Back</button>
        </div>
      )}

      {/* Cinematic controls overlay */}
      <div
        className={`absolute inset-0 z-10 transition-opacity duration-300 ${
          showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
      >
        {/* Top gradient bar */}
        <div className="absolute top-0 left-0 right-0 h-24 bg-gradient-to-b from-black/70 to-transparent pointer-events-none" />
        {/* Bottom gradient bar */}
        <div className="absolute bottom-0 left-0 right-0 h-36 bg-gradient-to-t from-black/70 to-transparent pointer-events-none" />

        {/* Top bar */}
        <div className="absolute top-0 left-0 right-0 p-5 flex items-center gap-3">
          <button onClick={onBack} className="p-1.5 -ml-1.5 rounded-full hover:bg-white/10 transition-colors">
            <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" className="w-6 h-6">
              <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
            </svg>
          </button>
          <span className="text-xs font-medium text-white/90 truncate flex-1">{title}</span>

          {/* Audio tracks */}
          <div className="relative">
            <button
              onClick={() => { setShowAudioMenu(!showAudioMenu); setShowSubMenu(false); }}
              className="text-xs px-2.5 py-1.5 rounded-md bg-white/10 hover:bg-white/15 text-white/70 hover:text-white transition-colors"
            >
              {audioTracks.length > 0
                ? (audioTracks.find(t => t.id === activeAudioTrack)?.lang || 'Audio')
                : 'Audio'}
            </button>
            {showAudioMenu && (
              <div className="absolute top-full right-0 mt-1 bg-neutral-900 border border-white/10 rounded-lg overflow-hidden min-w-[160px] shadow-xl">
                {audioTracks.length > 0 ? (
                  audioTracks.map(t => (
                    <button key={t.id} onClick={() => switchAudio(t.id)}
                      className={`w-full text-left px-3 py-2 text-xs hover:bg-white/10 transition-colors ${t.id === activeAudioTrack ? 'text-luna-accent' : 'text-white/70'}`}>
                      {t.name} ({t.lang})
                    </button>
                  ))
                ) : (
                  <div className="px-3 py-2 text-xs text-white/30">No audio tracks</div>
                )}
              </div>
            )}
          </div>

          {/* Subtitles */}
          <div className="relative">
            <button
              onClick={() => { setShowSubMenu(!showSubMenu); setShowAudioMenu(false); }}
              className="text-xs px-2.5 py-1.5 rounded-md bg-white/10 hover:bg-white/15 text-white/70 hover:text-white transition-colors"
            >
              CC
            </button>
            {showSubMenu && (
              <div className="absolute top-full right-0 mt-1 bg-neutral-900 border border-white/10 rounded-lg overflow-hidden min-w-[160px] shadow-xl">
                <button onClick={() => switchSubtitle(-1)}
                  className={`w-full text-left px-3 py-2 text-xs hover:bg-white/10 transition-colors ${activeSubtitle < 0 ? 'text-luna-accent' : 'text-white/70'}`}>
                  Off
                </button>
                {subtitleTracks.length > 0 ? (
                  subtitleTracks.map(t => (
                    <button key={t.id} onClick={() => switchSubtitle(t.id)}
                      className={`w-full text-left px-3 py-2 text-xs hover:bg-white/10 transition-colors ${t.id === activeSubtitle ? 'text-luna-accent' : 'text-white/70'}`}>
                      {t.name} ({t.lang})
                    </button>
                  ))
                ) : (
                  <div className="px-3 py-2 text-xs text-white/30">No subtitle tracks</div>
                )}
              </div>
            )}
          </div>
        </div>

        {/* Bottom controls */}
        <div className="absolute bottom-0 left-0 right-0 p-5 pt-12 space-y-3">

          {/* Seek bar */}
          <div className="flex items-center gap-3 group/seek">
            <span className="text-[11px] text-white/50 w-10 text-right tabular-nums flex-shrink-0">
              {formatTime(position)}
            </span>
            <div className="relative flex-1 flex items-center h-4 cursor-pointer group">
              <div className="absolute left-0 right-0 h-[2px] group-hover:h-[4px] rounded-full bg-white/15 transition-all duration-150">
                {duration > 0 && (
                  <div className="absolute left-0 top-0 h-full bg-white/20 rounded-full" style={{ width: `${(buffered / duration) * 100}%` }} />
                )}
                {duration > 0 && (
                  <div className="absolute left-0 top-0 h-full bg-luna-accent rounded-full" style={{ width: `${(position / duration) * 100}%` }} />
                )}
              </div>
              <input
                type="range" min={0} max={duration || 1} step={0.1} value={position}
                onChange={(e) => seek(Number(e.target.value))}
                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-10"
              />
              {duration > 0 && (
                <div className="absolute top-1/2 -translate-y-1/2 w-3 h-3 bg-luna-accent rounded-full -translate-x-1/2 pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity shadow-glow"
                  style={{ left: `${(position / duration) * 100}%`, boxShadow: '0 0 10px rgba(192,132,252,0.6)' }}
                />
              )}
            </div>
            <span className="text-[11px] text-white/50 w-10 tabular-nums flex-shrink-0">
              {formatTime(duration)}
            </span>
          </div>

          {/* Control row */}
          <div className="flex items-center justify-between">
            {/* Left group */}
            <div className="flex items-center gap-2">
              <button onClick={() => skip(-10)} className="p-2 rounded-full hover:bg-white/10 transition-colors group" title="Back 10s">
                <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="1.5" className="w-5 h-5 text-white/60 group-hover:text-white transition-colors">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M9 15L3 9m0 0l6-6M3 9h12a6 6 0 010 12h-3" />
                  <text x="11" y="5" fill="white" fontSize="7" fontWeight="700">10</text>
                </svg>
              </button>
              <button onClick={togglePlay}
                className="w-10 h-10 rounded-full border-2 border-white/30 hover:border-white/60 flex items-center justify-center transition-all duration-200 hover:scale-105">
                {state === 'playing' ? (
                  <svg viewBox="0 0 24 24" fill="white" className="w-5 h-5">
                    <rect x="6" y="4" width="4" height="16" rx="1" />
                    <rect x="14" y="4" width="4" height="16" rx="1" />
                  </svg>
                ) : (
                  <svg viewBox="0 0 24 24" fill="white" className="w-5 h-5 ml-0.5">
                    <polygon points="6,4 20,12 6,20" />
                  </svg>
                )}
              </button>
              <button onClick={() => skip(10)} className="p-2 rounded-full hover:bg-white/10 transition-colors group" title="Forward 10s">
                <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="1.5" className="w-5 h-5 text-white/60 group-hover:text-white transition-colors">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M15 15l6-6m0 0l-6-6m6 6H9a6 6 0 000 12h3" />
                  <text x="2" y="5" fill="white" fontSize="7" fontWeight="700">10</text>
                </svg>
              </button>
              <span className="text-[11px] text-white/40 ml-1 tabular-nums">
                {formatTime(position)} / {formatTime(duration)}
              </span>
            </div>

            {/* Right group */}
            <div className="flex items-center gap-1">
              {/* Volume */}
              <div className="flex items-center gap-1.5 group/vol">
                <button onClick={() => setMuted(!muted)} className="p-1.5 rounded-full hover:bg-white/10 transition-colors">
                  {muted || volume === 0 ? (
                    <svg viewBox="0 0 24 24" fill="white" className="w-4 h-4 text-white/50">
                      <path d="M13.5 4.06c0-1.336-1.616-2.005-2.56-1.06L3.72 10.22l7.22 7.22c.944.944 2.56.274 2.56-1.06V4.06z" />
                      <line x1="17" y1="8" x2="23" y2="16" stroke="white" strokeWidth="2" />
                      <line x1="23" y1="8" x2="17" y2="16" stroke="white" strokeWidth="2" />
                    </svg>
                  ) : volume < 0.5 ? (
                    <svg viewBox="0 0 24 24" fill="white" className="w-4 h-4 text-white/50">
                      <path d="M13.5 4.06c0-1.336-1.616-2.005-2.56-1.06L3.72 10.22l7.22 7.22c.944.944 2.56.274 2.56-1.06V4.06z" />
                      <path d="M17 9a4 4 0 010 6" stroke="white" strokeWidth="2" fill="none" />
                    </svg>
                  ) : (
                    <svg viewBox="0 0 24 24" fill="white" className="w-4 h-4 text-white/50">
                      <path d="M13.5 4.06c0-1.336-1.616-2.005-2.56-1.06L3.72 10.22l7.22 7.22c.944.944 2.56.274 2.56-1.06V4.06z" />
                      <path d="M17 8a5 5 0 010 8" stroke="white" strokeWidth="2" fill="none" />
                      <path d="M20 5a8 8 0 010 14" stroke="white" strokeWidth="2" fill="none" />
                    </svg>
                  )}
                </button>
                <div className="w-0 overflow-hidden group-hover/vol:w-16 transition-all duration-200 h-5 flex items-center">
                  <input type="range" min={0} max={1} step={0.05} value={muted ? 0 : volume}
                    onChange={(e) => { setVolume(Number(e.target.value)); setMuted(false); }}
                    className="w-full h-1 accent-luna-accent cursor-pointer"
                    style={{ writingMode: 'horizontal-tb' }}
                  />
                </div>
              </div>

              {/* Sources */}
              <button onClick={() => setShowSources(true)} className="p-1.5 rounded-full hover:bg-white/10 transition-colors" title="Sources">
                <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="1.5" className="w-4 h-4 text-white/50">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
                </svg>
              </button>

              {/* Fullscreen */}
              <button onClick={toggleFullscreen} className="p-1.5 rounded-full hover:bg-white/10 transition-colors" title="Fullscreen">
                <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" className="w-4 h-4 text-white/50">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 8.25M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15.75M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 8.25M20.25 20.25h-4.5m4.5 0v-4.5m0 4.5L15 15.75" />
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Center play overlay (when controls hidden) */}
      {!showControls && state !== 'loading' && state !== 'error' && state !== 'ended' && (
        <button onClick={togglePlay} className="absolute inset-0 z-10 flex items-center justify-center cursor-pointer">
          {state === 'paused' && (
            <div className="w-16 h-16 rounded-full bg-black/50 backdrop-blur-sm flex items-center justify-center animate-fade-in border border-white/10">
              <svg viewBox="0 0 24 24" fill="white" className="w-8 h-8 ml-1">
                <polygon points="6,4 20,12 6,20" />
              </svg>
            </div>
          )}
        </button>
      )}

      {/* Source selection panel */}
      {showSources && (
        <div className="absolute inset-0 z-30 flex justify-end">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowSources(false)} />
          <div className="relative w-80 max-w-[85vw] h-full bg-neutral-950 border-l border-white/10 overflow-y-auto">
            <div className="p-4 border-b border-white/10 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-white">Sources</h3>
              <button onClick={() => setShowSources(false)} className="p-1 rounded-full hover:bg-white/10">
                <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" className="w-5 h-5 text-white/50">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            {(() => {
              const grouped: Record<string, StreamItem[]> = {};
              for (const s of streams) {
                const key = s.addonName || 'Unknown';
                if (!grouped[key]) grouped[key] = [];
                grouped[key].push(s);
              }
              return Object.entries(grouped).map(([addonName, groupStreams]) => (
                <div key={addonName} className="border-b border-white/5 last:border-b-0">
                  <div className="px-4 pt-3 pb-1">
                    <p className="text-[10px] font-semibold text-white/30 uppercase tracking-wider">{addonName}</p>
                  </div>
                  {groupStreams.map((s) => (
                    <button key={s.url || s.infoHash || Math.random().toString()}
                      onClick={() => switchSource(s)}
                      className={`w-full text-left px-4 py-3 hover:bg-white/5 flex items-center justify-between ${s.url === currentStream.url ? 'bg-luna-accent/10 border-l-2 border-luna-accent' : ''}`}
                    >
                      <div className="min-w-0 flex-1">
                        <p className="text-sm text-white truncate">{s.title || s.name || s.description || 'Unknown'}</p>
                        {s.description && (s.title || s.name) && (
                          <p className="text-xs text-white/30 truncate mt-0.5">{s.description}</p>
                        )}
                      </div>
                      {s.url === currentStream.url && (
                        <svg viewBox="0 0 24 24" fill="currentColor" className="w-4 h-4 text-luna-accent flex-shrink-0 ml-2">
                          <path fillRule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12zm13.36-1.814a.75.75 0 10-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 00-1.06 1.06l2.25 2.25a.75.75 0 001.14-.094l3.75-5.25z" clipRule="evenodd" />
                        </svg>
                      )}
                    </button>
                  ))}
                </div>
              ));
            })()}
          </div>
        </div>
      )}
    </div>
  );
}
