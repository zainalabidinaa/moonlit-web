import { useEffect, useRef, useState, useCallback, useMemo } from 'react';
import { ChevronLeft, X, Play, Pause, Maximize, Minimize, Volume2, VolumeX } from 'lucide-react';
import { MediabunnyRemuxer } from '@/lib/mediabunny-remuxer';
import { StreamItem } from '@/lib/types';
import { sortStreamsForBrowserPlayback } from '@/lib/player-utils';
import { PlaybackErrorScreen } from '@/components/player/PlaybackErrorScreen';

interface MediabunnyPlayerProps {
  streamUrl: string;
  streams: StreamItem[];
  currentStream: StreamItem;
  title: string;
  mediaLogo?: string;
  startPosition?: number;
  onBack: () => void;
  onSwitchStream: (stream: StreamItem) => void;
  onError?: () => void;
}

export default function MediabunnyPlayer({
  streamUrl, streams, currentStream, title, mediaLogo,
  startPosition = 0, onBack, onSwitchStream, onError,
}: MediabunnyPlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const remuxerRef = useRef<MediabunnyRemuxer | null>(null);
  const mediaSourceRef = useRef<MediaSource | null>(null);
  const sourceBufferRef = useRef<SourceBuffer | null>(null);
  const queuedChunksRef = useRef<Uint8Array[]>([]);
  const appendPromiseRef = useRef(Promise.resolve());

  const [phase, setPhase] = useState<'loading' | 'playing' | 'error'>('loading');
  const [errorMsg, setErrorMsg] = useState('');
  const [showControls, setShowControls] = useState(true);
  const [showSources, setShowSources] = useState(false);
  const [showErrorSources, setShowErrorSources] = useState(false);
  const [errorRetryKey, setErrorRetryKey] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [paused, setPaused] = useState(true);
  const [muted, setMuted] = useState(false);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const resetHide = useCallback(() => {
    setShowControls(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setShowControls(false), 3500);
  }, []);

  // Setup MediaSource + Remuxer
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    let disposed = false;
    queuedChunksRef.current = [];
    appendPromiseRef.current = Promise.resolve();

    // Create MediaSource
    const ms = new MediaSource();
    mediaSourceRef.current = ms;
    video.src = URL.createObjectURL(ms);

    ms.addEventListener('sourceopen', async () => {
      if (disposed) return;

      const remuxer = new MediabunnyRemuxer();
      remuxerRef.current = remuxer;

      try {
        await remuxer.start(streamUrl, {
          onReady: (mimeType: string) => {
            if (disposed) return;
            // Create SourceBuffer with the correct MIME type
            const sb = ms.addSourceBuffer(mimeType);
            sourceBufferRef.current = sb;

            // Flush any queued chunks
            const chunks = queuedChunksRef.current;
            queuedChunksRef.current = [];
            for (const chunk of chunks) {
              appendToSourceBuffer(sb, chunk);
            }

            if (startPosition > 0) {
              video.currentTime = startPosition;
            }
            video.play().catch(() => {});
            setPhase('playing');
            setPaused(false);
          },
          onChunk: (data: Uint8Array) => {
            if (disposed) return;
            const sb = sourceBufferRef.current;
            if (sb) {
              appendToSourceBuffer(sb, data);
            } else {
              queuedChunksRef.current.push(data);
            }
          },
          onProgress: (progress: number) => {
            // Progress from mediabunny: 0-1
            if (!disposed && ms.readyState === 'open' && sourceBufferRef.current && progress >= 1) {
              try { ms.endOfStream(); } catch {}
            }
          },
          onError: (err: Error) => {
            if (disposed) return;
            setErrorMsg(err.message || 'Transmux failed');
            setPhase('error');
            onError?.();
          },
        });
      } catch (err) {
        if (disposed) return;
        setErrorMsg(err instanceof Error ? err.message : 'Failed to start transmux');
        setPhase('error');
        onError?.();
      }
    }, { once: true });

    return () => {
      disposed = true;
      try { remuxerRef.current?.destroy(); } catch {}
      try { if (ms.readyState !== 'closed') ms.endOfStream(); } catch {}
      try { URL.revokeObjectURL(video.src); } catch {}
    };
  }, [streamUrl, errorRetryKey]);

  // Sync video element events to state
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const onTime = () => setCurrentTime(video.currentTime);
    const onDur = () => setDuration(video.duration || 0);
    const onPlay = () => setPaused(false);
    const onPause = () => setPaused(true);
    video.addEventListener('timeupdate', onTime);
    video.addEventListener('durationchange', onDur);
    video.addEventListener('play', onPlay);
    video.addEventListener('pause', onPause);
    return () => {
      video.removeEventListener('timeupdate', onTime);
      video.removeEventListener('durationchange', onDur);
      video.removeEventListener('play', onPlay);
      video.removeEventListener('pause', onPause);
    };
  }, []);

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const video = videoRef.current;
      if (!video) return;
      if (e.key === ' ' || e.key === 'k') {
        e.preventDefault();
        video.paused ? video.play() : video.pause();
      } else if (e.key === 'ArrowLeft') {
        video.currentTime = Math.max(0, video.currentTime - 10);
      } else if (e.key === 'ArrowRight') {
        video.currentTime = Math.min(video.duration || 0, video.currentTime + 10);
      } else if (e.key === 'f') {
        e.preventDefault();
        document.fullscreenElement ? document.exitFullscreen() : video.requestFullscreen();
      } else if (e.key === 'm') {
        video.muted = !video.muted;
        setMuted(video.muted);
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);

  const fmt = (s: number) => {
    if (!isFinite(s)) return '0:00';
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = Math.floor(s % 60);
    return h > 0
      ? `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`
      : `${m}:${String(sec).padStart(2, '0')}`;
  };

  const pct = duration > 0 ? (currentTime / duration) * 100 : 0;
  const sortedStreams = useMemo(() => sortStreamsForBrowserPlayback(streams), [streams]);

  if (phase === 'error') {
    return (
      <div className="fixed inset-0 bg-black z-50">
        <PlaybackErrorScreen
          error={{
            message: errorMsg || 'Transmux failed',
            details: `URL: ${streamUrl}\nStream: ${currentStream.title || currentStream.name || currentStream.addonName || 'unknown'}`,
            streamTitle: currentStream.title || currentStream.name,
            streamAddon: currentStream.addonName,
          }}
          onBack={onBack}
          onRetry={() => {
            setShowErrorSources(false);
            setErrorRetryKey(k => k + 1);
          }}
          onChooseSource={() => setShowErrorSources(true)}
        />
        {showErrorSources && (
          <div className="absolute inset-0 z-[60] flex justify-end">
            <div className="absolute inset-0 bg-black/60" onClick={() => setShowErrorSources(false)} />
            <div className="relative w-[460px] max-w-[92vw] h-full bg-[#090910]/95 border-l border-white/10 overflow-y-auto shadow-2xl">
              <div className="p-6 border-b border-white/8 flex items-center justify-between">
                <h3 className="text-xl font-bold text-white">Sources</h3>
                <button onClick={() => setShowErrorSources(false)} className="p-2 rounded-full hover:bg-white/10"><X size={18} className="text-white/60" /></button>
              </div>
              <div className="p-4 space-y-2">
                {sortedStreams.map((s, i) => (
                  <button key={s.url ? `${s.url}-${i}` : `stream-${i}`} onClick={() => { setShowErrorSources(false); setErrorRetryKey(k => k + 1); onSwitchStream(s); }} className="w-full text-left px-4 py-3 rounded-2xl border border-white/10 bg-white/5 hover:bg-white/10 text-white/80 hover:text-white text-sm">
                    {s.name || s.title || s.addonName || `Stream ${i + 1}`}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="fixed inset-0 bg-black z-50" onMouseMove={resetHide}>
      {/* Loading overlay */}
      {phase === 'loading' && (
        <div className="absolute inset-0 z-10 flex items-center justify-center">
          <div className="w-10 h-10 border-2 border-white/20 border-t-white rounded-full animate-spin" />
        </div>
      )}

      {/* Video element */}
      <video
        ref={videoRef}
        className="w-full h-full object-contain"
        playsInline
        muted={muted}
        onClick={() => {
          const v = videoRef.current;
          if (!v) return;
          v.paused ? v.play() : v.pause();
        }}
      />

      {/* Controls overlay */}
      <div className={`absolute inset-0 flex flex-col justify-between transition-opacity duration-300 select-none ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}>
        {/* Top bar */}
        <div className="flex items-center justify-between px-8 pt-6 pb-24" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.85) 0%, transparent 100%)' }}>
          <button onClick={onBack} className="flex items-center gap-2 text-white/80 hover:text-white font-medium text-base">
            <ChevronLeft size={22} />Back
          </button>
          <p className="text-base font-semibold text-white/70 truncate max-w-[45%]">{title}</p>
          <button onClick={() => setShowSources(true)} className="flex items-center gap-1.5 bg-white/10 hover:bg-white/15 border border-white/10 rounded-xl px-3 py-2 text-sm text-white/80">
            Sources
          </button>
        </div>

        {/* Bottom bar */}
        <div className="px-8 pb-8 pt-24" style={{ background: 'linear-gradient(to top, rgba(0,0,0,0.85) 0%, transparent 100%)' }}>
          {/* Seek bar */}
          <div
            className="w-full h-1 bg-white/20 rounded-full mb-5 cursor-pointer group"
            onClick={(e) => {
              const rect = e.currentTarget.getBoundingClientRect();
              const ratio = (e.clientX - rect.left) / rect.width;
              const v = videoRef.current;
              if (v && duration > 0) v.currentTime = ratio * duration;
            }}
          >
            <div className="h-full bg-white rounded-full" style={{ width: `${pct}%` }} />
          </div>

          <div className="flex items-center gap-5">
            <button
              onClick={() => {
                const v = videoRef.current;
                if (!v) return;
                v.paused ? v.play() : v.pause();
              }}
              className="text-white hover:scale-110 transition-transform"
            >
              {paused ? <Play size={28} fill="white" /> : <Pause size={28} fill="white" />}
            </button>
            <button
              onClick={() => {
                const v = videoRef.current;
                if (!v) return;
                v.muted = !v.muted;
                setMuted(v.muted);
              }}
              className="text-white/70 hover:text-white"
            >
              {muted ? <VolumeX size={20} /> : <Volume2 size={20} />}
            </button>
            <span className="text-sm text-white/60 font-mono tabular-nums">
              {fmt(currentTime)} / {fmt(duration)}
            </span>
            <div className="flex-1" />
            <button
              onClick={() => {
                const v = videoRef.current;
                document.fullscreenElement ? document.exitFullscreen() : v?.requestFullscreen();
              }}
              className="text-white/70 hover:text-white"
            >
              {document.fullscreenElement ? <Minimize size={20} /> : <Maximize size={20} />}
            </button>
          </div>
        </div>
      </div>

      {/* Sources panel */}
      {showSources && (
        <div className="absolute inset-0 z-40 flex justify-end">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowSources(false)} />
          <div className="relative w-[460px] max-w-[92vw] h-full bg-[#090910]/95 border-l border-white/10 overflow-y-auto shadow-2xl">
            <div className="p-6 border-b border-white/8 flex items-center justify-between">
              <h3 className="text-xl font-bold text-white">Sources</h3>
              <button onClick={() => setShowSources(false)} className="p-2 rounded-full hover:bg-white/10"><X size={18} className="text-white/60" /></button>
            </div>
            <div className="p-4 space-y-2">
              {sortedStreams.map((s, i) => (
                <button key={s.url ? `${s.url}-${i}` : `stream-${i}`} onClick={() => { setShowSources(false); onSwitchStream(s); }} className="w-full text-left px-4 py-3 rounded-2xl border border-white/10 bg-white/5 hover:bg-white/10 text-white/80 hover:text-white text-sm">
                  {s.name || s.title || s.addonName || `Stream ${i + 1}`}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

let appendChain = Promise.resolve();

function appendToSourceBuffer(sb: SourceBuffer, data: Uint8Array) {
  // SourceBuffer.appendBuffer calls must be serialized
  appendChain = appendChain.then(() => new Promise<void>((resolve) => {
    function doAppend() {
      try { sb.appendBuffer(data as BufferSource); } catch (e) { /* buffer full — drop */ }
      sb.addEventListener('updateend', () => resolve(), { once: true });
    }
    if (sb.updating) {
      sb.addEventListener('updateend', () => doAppend(), { once: true });
    } else {
      doAppend();
    }
  }));
}
