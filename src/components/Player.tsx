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

const SkipBackIcon = () => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-6 h-6">
    <path d="M12.5 3c4.65 0 8.5 3.85 8.5 8.5S17.15 20 12.5 20c-1.42 0-2.75-.35-3.93-.97l1.43-1.43A6.47 6.47 0 0012.5 18c3.58 0 6.5-2.92 6.5-6.5S16.08 5 12.5 5c-1.88 0-3.59.8-4.78 2.07L4.5 3.78V11h7.22L8.78 8.03A4.97 4.97 0 0112.5 6.5c2.76 0 5 2.24 5 5s-2.24 5-5 5c-2.42 0-4.41-1.72-4.9-4H5.56c.52 3.26 3.35 5.73 6.94 5.73z" />
  </svg>
);

const SkipForwardIcon = () => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-6 h-6">
    <path d="M11.5 3C6.85 3 3 6.85 3 11.5S6.85 20 11.5 20c1.42 0 2.75-.35 3.93-.97l-1.43-1.43A6.47 6.47 0 0111.5 18c-3.58 0-6.5-2.92-6.5-6.5S7.92 5 11.5 5c1.88 0 3.59.8 4.78 2.07L19.5 3.78V11h-7.22l2.94-2.97A4.97 4.97 0 0011.5 6.5c-2.76 0-5 2.24-5 5s2.24 5 5 5c2.42 0 4.41-1.72 4.9-4h1.04c-.52 3.26-3.35 5.73-6.94 5.73z" />
  </svg>
);

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
  const [errorMessage, setErrorMessage] = useState('');
  const startPosRef = useRef<number | undefined>();

  useEffect(() => {
    startPosRef.current = startPosition;
  }, [startPosition]);

  // --- Init/cleanup hls.js ---
  const initPlayer = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;

    // Cleanup previous
    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }
    video.src = '';

    setState('loading');
    setErrorMessage('');

    const proxyHeaders = currentStream.behaviorHints?.proxyHeaders?.request;
    const hasHeaders = proxyHeaders != null && Object.keys(proxyHeaders).length > 0;
    const looksLikeHls = streamUrl.endsWith('.m3u8')
      || streamUrl.includes('.m3u8')
      || streamUrl.includes('/manifest')
      || streamUrl.includes('/playlist');
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
        video.play().catch(() => {});
      });

      hls.on(Hls.Events.ERROR, (_event, data) => {
        hlsErrorCount++;
        if (data.fatal) {
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR && hlsErrorCount <= 1) {
            hls.destroy();
            hlsRef.current = null;
            video.src = '';
            // Fall back to native <video>
            video.src = streamUrl;
            video.play().catch(() => {});
          } else {
            setState('error');
            setErrorMessage(
              data.type === Hls.ErrorTypes.NETWORK_ERROR
                ? 'Network error — check your connection'
                : 'Playback error — try another source'
            );
            hls.destroy();
            hlsRef.current = null;
          }
        }
      });

      hls.loadSource(streamUrl);
      hls.attachMedia(video);
      hlsRef.current = hls;
    } else {
      // Native <video> — direct MP4/WebM or unsupported browser HLS
      video.src = streamUrl;
      video.play().catch(() => {});
    }
  }, [streamUrl, currentStream]);

  useEffect(() => {
    initPlayer();
    return () => {
      if (hlsRef.current) {
        hlsRef.current.destroy();
        hlsRef.current = null;
      }
    };
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
    const onPause = () => {
      if (!video.ended) setState('paused');
    };
    const onEnded = () => setState('ended');
    const onError = () => {
      setState('error');
      setErrorMessage('Failed to play this stream');
    };
    const onTimeUpdate = () => {
      setPosition(video.currentTime);
      setDuration(video.duration || 0);
      if (video.buffered.length > 0) {
        setBuffered(video.buffered.end(video.buffered.length - 1));
      }
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
        await updateWatchProgress(
          currentProfile.id,
          mediaId,
          mediaType,
          video.currentTime,
          video.duration || 0,
          false
        );
      }
    }, 10000);

    return () => {
      if (progressInterval.current) clearInterval(progressInterval.current);
    };
  }, [currentProfile, mediaId, mediaType]);

  // Mark completed on end
  useEffect(() => {
    if (state === 'ended' && currentProfile) {
      updateWatchProgress(currentProfile.id, mediaId, mediaType, duration, duration, true);
    }
  }, [state, currentProfile, mediaId, mediaType, duration]);

  // --- Controls auto-hide ---
  const resetHideTimer = useCallback(() => {
    setShowControls(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setShowControls(false), 4000);
  }, []);

  useEffect(() => {
    resetHideTimer();
    return () => {
      if (hideTimer.current) clearTimeout(hideTimer.current);
    };
  }, [state, resetHideTimer]);

  const toggleControls = () => {
    if (showControls) {
      setShowControls(false);
      if (hideTimer.current) clearTimeout(hideTimer.current);
    } else {
      resetHideTimer();
    }
  };

  // --- Playback controls ---
  const togglePlay = () => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) {
      video.play().catch(() => {});
    } else {
      video.pause();
    }
  };

  const seek = (seconds: number) => {
    const video = videoRef.current;
    if (!video) return;
    video.currentTime = seconds;
    setPosition(seconds);
  };

  const skipBack = () => {
    const video = videoRef.current;
    if (video) seek(Math.max(0, video.currentTime - 15));
  };

  const skipForward = () => {
    const video = videoRef.current;
    if (video) seek(Math.min(video.duration || 0, video.currentTime + 30));
  };

  const switchSource = (stream: StreamItem) => {
    setShowSources(false);
    onSwitchStream(stream);
  };

  // --- Keyboard shortcuts ---
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.key === ' ' || e.key === 'k') {
        e.preventDefault();
        togglePlay();
      }
      if (e.key === 'ArrowLeft') skipBack();
      if (e.key === 'ArrowRight') skipForward();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const bgSrc = backdrop || poster;

  return (
    <div className="fixed inset-0 bg-black z-50 select-none">
      {/* Video element */}
      <video
        ref={videoRef}
        className="absolute inset-0 w-full h-full object-contain"
        playsInline
        onClick={toggleControls}
      />

      {/* Loading overlay */}
      {state === 'loading' && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-6 bg-black/80 z-10">
          {bgSrc && (
            <img
              src={bgSrc}
              alt=""
              className="absolute inset-0 w-full h-full object-cover opacity-30 blur-md"
            />
          )}
          <div className="relative z-10 flex flex-col items-center gap-6">
            {poster && (
              <img
                src={poster}
                alt={title}
                className="w-24 sm:w-32 rounded-xl shadow-2xl ring-1 ring-white/10"
              />
            )}
            <h2 className="text-lg font-semibold text-white text-center">{title}</h2>
            <div className="animate-spin rounded-full h-8 w-8 border-2 border-luna-accent border-t-transparent" />
            <p className="text-sm text-luna-muted">Loading source from {currentStream.addonName || 'addon'}...</p>
          </div>
        </div>
      )}

      {/* Error overlay */}
      {state === 'error' && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-black/90 z-20">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5} className="w-12 h-12 text-red-400">
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
          </svg>
          <p className="text-white text-lg font-semibold">Playback Error</p>
          <p className="text-luna-muted text-sm">{errorMessage}</p>
          <div className="flex gap-3 mt-2">
            <button
              onClick={onBack}
              className="px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full transition-all duration-200 cursor-pointer text-sm"
            >
              Back
            </button>
            <button
              onClick={initPlayer}
              className="px-6 py-2.5 bg-luna-accent hover:bg-purple-400 text-white font-semibold rounded-full transition-all duration-200 cursor-pointer text-sm"
            >
              Retry
            </button>
          </div>
        </div>
      )}

      {/* Ended overlay */}
      {state === 'ended' && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-black/80 z-20">
          <p className="text-white text-lg font-semibold">Finished</p>
          <button
            onClick={onBack}
            className="px-6 py-2.5 bg-luna-accent hover:bg-purple-400 text-white font-semibold rounded-full transition-all duration-200 cursor-pointer text-sm"
          >
            Back
          </button>
        </div>
      )}

      {/* Custom controls */}
      <div
        className={`absolute inset-0 z-10 transition-opacity duration-300 ${
          showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
      >
        {/* Gradient overlays */}
        <div className="absolute inset-0 bg-gradient-to-b from-black/70 via-transparent to-black/70 pointer-events-none" />

        {/* Top bar */}
        <div className="absolute top-0 left-0 right-0 p-4 flex items-center gap-3">
          <button
            onClick={onBack}
            className="p-2 -ml-2 rounded-full hover:bg-white/10 transition-colors cursor-pointer"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="w-6 h-6 text-white">
              <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
            </svg>
          </button>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-white truncate">{title}</p>
            <p className="text-xs text-luna-muted truncate">
              {currentStream.title || currentStream.name || currentStream.addonName || 'Unknown source'}
            </p>
          </div>
        </div>

        {/* Bottom controls */}
        <div className="absolute bottom-0 left-0 right-0 p-4 pt-8 space-y-3">
          {/* Seek bar */}
          <div className="flex items-center gap-3">
            <span className="text-xs text-white/80 w-10 text-right tabular-nums flex-shrink-0">
              {formatTime(position)}
            </span>
            <div className="relative flex-1 h-6 flex items-center group">
              {/* Buffer bar */}
              <div className="absolute left-0 right-0 h-1 rounded-full bg-white/20 overflow-hidden">
                {duration > 0 && (
                  <div
                    className="h-full bg-white/30 rounded-full"
                    style={{ width: `${(buffered / duration) * 100}%` }}
                  />
                )}
              </div>
              {/* Progress */}
              <div className="absolute left-0 right-0 h-1 rounded-full overflow-hidden pointer-events-none">
                {duration > 0 && (
                  <div
                    className="h-full bg-luna-accent rounded-full"
                    style={{ width: `${(position / duration) * 100}%` }}
                  />
                )}
              </div>
              {/* Input range */}
              <input
                type="range"
                min={0}
                max={duration || 1}
                step={0.1}
                value={position}
                onChange={(e) => seek(Number(e.target.value))}
                onMouseDown={() => {
                  if (hideTimer.current) clearTimeout(hideTimer.current);
                }}
                onMouseUp={resetHideTimer}
                onTouchStart={() => {
                  if (hideTimer.current) clearTimeout(hideTimer.current);
                }}
                onTouchEnd={resetHideTimer}
                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-10"
              />
              {/* Thumb dot */}
              {duration > 0 && (
                <div
                  className="absolute w-3 h-3 bg-luna-accent rounded-full -translate-x-1/2 -translate-y-1/2 top-1/2 pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"
                  style={{ left: `${(position / duration) * 100}%` }}
                />
              )}
            </div>
            <span className="text-xs text-white/80 w-10 tabular-nums flex-shrink-0">
              {formatTime(duration)}
            </span>
          </div>

          {/* Control buttons */}
          <div className="flex items-center justify-center gap-4">
            <button
              onClick={skipBack}
              className="p-2 rounded-full hover:bg-white/10 transition-colors cursor-pointer group"
            >
              <span className="text-white/70 group-hover:text-white transition-colors">
                <SkipBackIcon />
              </span>
              <span className="sr-only">Back 15s</span>
            </button>

            <button
              onClick={togglePlay}
              className="p-3 rounded-full bg-white hover:bg-white/90 transition-all duration-200 cursor-pointer"
            >
              {state === 'playing' ? (
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-6 h-6 text-black ml-[-2px]">
                  <path fillRule="evenodd" d="M6.75 5.25a.75.75 0 01.75-.75H9a.75.75 0 01.75.75v13.5a.75.75 0 01-.75.75H7.5a.75.75 0 01-.75-.75V5.25zm7.5 0A.75.75 0 0115 4.5h1.5a.75.75 0 01.75.75v13.5a.75.75 0 01-.75.75H15a.75.75 0 01-.75-.75V5.25z" clipRule="evenodd" />
                </svg>
              ) : (
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-6 h-6 text-black ml-0.5">
                  <path fillRule="evenodd" d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.348c1.295.712 1.295 2.573 0 3.285L7.28 19.991c-1.25.687-2.779-.217-2.779-1.643V5.653z" clipRule="evenodd" />
                </svg>
              )}
            </button>

            <button
              onClick={skipForward}
              className="p-2 rounded-full hover:bg-white/10 transition-colors cursor-pointer group"
            >
              <span className="text-white/70 group-hover:text-white transition-colors">
                <SkipForwardIcon />
              </span>
              <span className="sr-only">Forward 30s</span>
            </button>

            {/* Source switcher */}
            {streams.length > 1 && (
              <button
                onClick={() => setShowSources(true)}
                className="p-2 rounded-full hover:bg-white/10 transition-colors cursor-pointer ml-2"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 text-white/70">
                  <path d="M5.566 4.657A4.505 4.505 0 016.75 4.5h10.5c.41 0 .806.055 1.183.157A3 3 0 0015.75 3h-7.5a3 3 0 00-2.684 1.657zM2.25 12a3 3 0 013-3h13.5a3 3 0 013 3v6a3 3 0 01-3 3H5.25a3 3 0 01-3-3v-6zM5.25 7.5c-.69 0-1.35.155-1.945.437A4.505 4.505 0 015.25 9h13.5A4.5 4.5 0 0021 12.218V12a3 3 0 00-3-3H5.25z" />
                </svg>
                <span className="sr-only">Sources</span>
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Source selection panel */}
      {showSources && (
        <div className="absolute inset-0 z-30 flex justify-end">
          <div
            className="absolute inset-0 bg-black/60"
            onClick={() => setShowSources(false)}
          />
          <div className="relative w-80 max-w-[85vw] h-full bg-luna-bg border-l border-luna-border overflow-y-auto">
            <div className="p-4 border-b border-luna-border flex items-center justify-between">
              <h3 className="text-sm font-semibold text-white">Sources</h3>
              <button
                onClick={() => setShowSources(false)}
                className="p-1 rounded-full hover:bg-white/10 transition-colors cursor-pointer"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="w-5 h-5 text-white/70">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            {/* Group by addon */}
            {(() => {
              const grouped: Record<string, StreamItem[]> = {};
              for (const s of streams) {
                const key = s.addonName || 'Unknown';
                if (!grouped[key]) grouped[key] = [];
                grouped[key].push(s);
              }
              return Object.entries(grouped).map(([addonName, groupStreams]) => (
                <div key={addonName} className="border-b border-luna-border/50 last:border-b-0">
                  <div className="px-4 pt-3 pb-1">
                    <p className="text-xs font-semibold text-luna-muted uppercase tracking-wide">{addonName}</p>
                  </div>
                  {groupStreams.map((s) => (
                    <button
                      key={s.url || s.infoHash || Math.random().toString()}
                      onClick={() => switchSource(s)}
                      className={`w-full text-left px-4 py-3 hover:bg-white/5 transition-colors cursor-pointer flex items-center justify-between ${
                        s.url === currentStream.url ? 'bg-luna-accent/10 border-l-2 border-luna-accent' : ''
                      }`}
                    >
                      <div className="min-w-0 flex-1">
                        <p className="text-sm text-white truncate">
                          {s.title || s.name || s.description || 'Unknown'}
                        </p>
                        {s.description && (s.title || s.name) && (
                          <p className="text-xs text-luna-muted truncate mt-0.5">{s.description}</p>
                        )}
                      </div>
                      {s.url === currentStream.url && (
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-4 h-4 text-luna-accent flex-shrink-0 ml-2">
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

      {/* Center play/pause tap area (when controls hidden) */}
      {!showControls && !showSources && (
        <button
          onClick={togglePlay}
          className="absolute inset-0 z-10 flex items-center justify-center cursor-pointer"
        >
          {state === 'paused' && (
            <div className="w-16 h-16 rounded-full bg-black/60 backdrop-blur-sm flex items-center justify-center animate-fade-in">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-8 h-8 text-white ml-1">
                <path fillRule="evenodd" d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.348c1.295.712 1.295 2.573 0 3.285L7.28 19.991c-1.25.687-2.779-.217-2.779-1.643V5.653z" clipRule="evenodd" />
              </svg>
            </div>
          )}
        </button>
      )}
    </div>
  );
}
