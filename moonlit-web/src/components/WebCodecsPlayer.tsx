import { useEffect, useRef, useState, useCallback } from 'react';
import { ChevronLeft, X, Play, Pause, Maximize, Minimize } from 'lucide-react';
import { WebCodecsPlayerEngine, WebCodecsPlayerState } from '@/lib/webcodecs-player';
import { StreamItem } from '@/lib/types';
import { sortStreamsForBrowserPlayback } from '@/lib/player-utils';

interface WebCodecsPlayerProps {
  streamUrl: string;
  streams: StreamItem[];
  currentStream: StreamItem;
  title: string;
  mediaLogo?: string;
  onBack: () => void;
  onSwitchStream: (stream: StreamItem) => void;
}

export default function WebCodecsPlayer({
  streamUrl, streams, currentStream, title, mediaLogo, onBack, onSwitchStream,
}: WebCodecsPlayerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<WebCodecsPlayerEngine | null>(null);
  const [state, setState] = useState<WebCodecsPlayerState>({
    duration: 0, currentTime: 0, isPlaying: false, isReady: false, error: null,
  });
  const [showControls, setShowControls] = useState(true);
  const [showSources, setShowSources] = useState(false);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const resetHide = useCallback(() => {
    setShowControls(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setShowControls(false), 3500);
  }, []);

  // Load stream into engine
  useEffect(() => {
    if (!canvasRef.current) return;
    const engine = new WebCodecsPlayerEngine();
    engineRef.current = engine;
    const unsub = engine.subscribe(setState);
    engine.load(streamUrl, canvasRef.current).then(() => engine.play());
    return () => { unsub(); engine.destroy(); engineRef.current = null; };
  }, [streamUrl]);

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const eng = engineRef.current;
      if (!eng) return;
      if (e.key === ' ' || e.key === 'k') {
        e.preventDefault();
        state.isPlaying ? eng.pause() : eng.play();
      } else if (e.key === 'ArrowLeft') {
        eng.seek(Math.max(0, state.currentTime - 10));
      } else if (e.key === 'ArrowRight') {
        eng.seek(Math.min(state.duration, state.currentTime + 10));
      } else if (e.key === 'f') {
        document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [state.isPlaying, state.currentTime, state.duration]);

  const fmt = (s: number) => {
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = Math.floor(s % 60);
    return h > 0 ? `${h}:${String(m).padStart(2,'0')}:${String(sec).padStart(2,'0')}` : `${m}:${String(sec).padStart(2,'0')}`;
  };

  const pct = state.duration > 0 ? (state.currentTime / state.duration) * 100 : 0;
  const sortedStreams = sortStreamsForBrowserPlayback(streams);

  if (state.error) {
    return (
      <div className="fixed inset-0 bg-black z-50 flex flex-col items-center justify-center gap-4">
        <p className="text-white text-lg font-semibold">Playback Error</p>
        <p className="text-white/50 text-sm text-center max-w-sm px-4">{state.error}</p>
        <div className="flex gap-3">
          <button onClick={onBack} className="px-6 py-2.5 bg-white/10 text-white rounded-full text-sm">Back</button>
          <button onClick={() => setShowSources(true)} className="px-6 py-2.5 bg-moonlit-accent text-white rounded-full text-sm font-semibold">Choose source</button>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 bg-black z-50" onMouseMove={resetHide}>
      {/* Loading overlay */}
      {!state.isReady && (
        <div className="absolute inset-0 z-10 flex items-center justify-center">
          <div className="w-10 h-10 border-2 border-white/20 border-t-white rounded-full animate-spin" />
        </div>
      )}

      {/* Canvas */}
      <canvas
        ref={canvasRef}
        className="w-full h-full object-contain"
        onClick={() => state.isPlaying ? engineRef.current?.pause() : engineRef.current?.play()}
      />

      {/* Controls */}
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
              engineRef.current?.seek(ratio * state.duration);
            }}
          >
            <div className="h-full bg-white rounded-full" style={{ width: `${pct}%` }} />
          </div>

          <div className="flex items-center gap-5">
            <button onClick={() => state.isPlaying ? engineRef.current?.pause() : engineRef.current?.play()} className="text-white hover:scale-110 transition-transform">
              {state.isPlaying ? <Pause size={28} fill="white" /> : <Play size={28} fill="white" />}
            </button>
            <span className="text-sm text-white/60 font-mono tabular-nums">
              {fmt(state.currentTime)} / {fmt(state.duration)}
            </span>
            <div className="flex-1" />
            <button onClick={() => document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen()} className="text-white/70 hover:text-white">
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
                <button key={s.url || i} onClick={() => { setShowSources(false); onSwitchStream(s); }} className="w-full text-left px-4 py-3 rounded-2xl border border-white/10 bg-white/5 hover:bg-white/10 text-white/80 hover:text-white text-sm">
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
