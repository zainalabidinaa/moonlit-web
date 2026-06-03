import { useEffect, useRef, useState, useCallback } from 'react';
import Hls from 'hls.js';
import {
  Play, Pause, RotateCcw, RotateCw,
  Volume2, Volume1, VolumeX,
  Captions as CaptionsIcon, Maximize, Minimize,
  ChevronLeft, X,
} from 'lucide-react';
import { StreamItem } from '@/lib/types';
import { SubtitleItem } from '@/lib/stremio';
import { updateWatchProgress } from '@/lib/services/api';
import { useAuth } from '@/app/AuthProvider';
import { getPlayableStreamUrl, sortStreamsForBrowserPlayback } from '@/lib/player-utils';

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

interface TrackItem { id: number; name: string; lang: string }

function fmt(seconds: number): string {
  if (!isFinite(seconds) || seconds < 0) return '0:00';
  const s = Math.floor(seconds), m = Math.floor(s / 60), rs = s % 60;
  if (m >= 60) { const h = Math.floor(m / 60); return h + ':' + String(m % 60).padStart(2, '0') + ':' + String(rs).padStart(2, '0'); }
  return m + ':' + String(rs).padStart(2, '0');
}

function parseQuality(s: StreamItem): { label: string; color: string } {
  const t = `${s.name ?? ''} ${s.title ?? ''} ${s.description ?? ''}`.toLowerCase();
  if (t.includes('2160') || t.includes('4k') || t.includes('uhd')) return { label: '4K', color: 'text-yellow-400 bg-yellow-400/10' };
  if (t.includes('1080')) return { label: '1080p', color: 'text-blue-400 bg-blue-400/10' };
  if (t.includes('720')) return { label: '720p', color: 'text-slate-400 bg-slate-400/10' };
  return { label: 'SD', color: 'text-slate-500 bg-slate-500/10' };
}

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

export default function Player({
  streamUrl, streams, currentStream, title, mediaLogo,
  mediaId, mediaType, startPosition, subtitles = [],
  onSwitchStream, onBack,
}: PlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const progressInterval = useRef<ReturnType<typeof setInterval> | null>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const loadTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const externalTrackRef = useRef<HTMLTrackElement | null>(null);
  const savedFailoverPosition = useRef(0);
  const startPosRef = useRef<number | undefined>(undefined);
  const failoverToNextStreamRef = useRef<() => void>(() => {});
  const { currentProfile } = useAuth();

  const [state, setState] = useState<'loading' | 'playing' | 'paused' | 'ended' | 'error'>('loading');
  const [pos, setPos] = useState(0);
  const [dur, setDur] = useState(0);
  const [buf, setBuf] = useState(0);
  const [showControls, setShowControls] = useState(true);
  const [showSources, setShowSources] = useState(false);
  const [showTracks, setShowTracks] = useState(false);
  const [showSpeed, setShowSpeed] = useState(false);
  const [errMsg, setErrMsg] = useState('');
  const [volume, setVolume] = useState(1);
  const [muted, setMuted] = useState(false);
  const [audioTracks, setAudioTracks] = useState<TrackItem[]>([]);
  const [activeAudio, setActiveAudio] = useState(-1);
  const [subTracks, setSubTracks] = useState<TrackItem[]>([]);
  const [activeSub, setActiveSub] = useState(-1);
  const [activeExternalSubId, setActiveExternalSubId] = useState<string | null>(null);
  const [activeCueText, setActiveCueText] = useState('');
  const [qualityLevels, setQualityLevels] = useState<{ height: number; bitrate: number }[]>([]);
  const [activeQuality, setActiveQuality] = useState(-1);
  const [playbackRate, setPlaybackRate] = useState(1);
  const [isDragging, setIsDragging] = useState(false);
  const [tooltipPos, setTooltipPos] = useState(0);
  const [tooltipText, setTooltipText] = useState('0:00');
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [failedUrls, setFailedUrls] = useState<Set<string>>(() => new Set());

  useEffect(() => { startPosRef.current = startPosition; }, [startPosition]);
  useEffect(() => { setFailedUrls(new Set()); }, [mediaId]);

  // ── hls.js init ──────────────────────────────────────────────────────────
  const initPlayer = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    if (hlsRef.current) { hlsRef.current.destroy(); hlsRef.current = null; }
    video.src = '';
    setState('loading'); setErrMsg('');
    setAudioTracks([]); setActiveAudio(-1);
    setSubTracks([]); setActiveSub(-1);
    setActiveCueText('');
    setQualityLevels([]); setActiveQuality(-1);
    setActiveExternalSubId(null);
    if (externalTrackRef.current) { try { video.removeChild(externalTrackRef.current); } catch {} externalTrackRef.current = null; }

    const proxyHeaders = currentStream.behaviorHints?.proxyHeaders?.request;
    const hasHeaders = proxyHeaders != null && Object.keys(proxyHeaders).length > 0;

    const fallbackToNative = () => {
      if (hlsRef.current) { hlsRef.current.destroy(); hlsRef.current = null; }
      video.src = streamUrl;
      video.load();
      video.play().catch(() => setState('paused'));
    };

    // Probe-confirmed MP4 → go native directly, skip HLS.js entirely
    if (currentStream.behaviorHints?.webPlayableType === 'video/mp4') {
      video.src = streamUrl;
      video.load();
      video.play().catch(() => setState('paused'));
      return;
    }

    if (!Hls.isSupported()) {
      video.src = streamUrl;
      video.play().catch(() => setState('paused'));
      return;
    }

    const loadTimeout = setTimeout(() => {
      if (hlsRef.current) fallbackToNative();
    }, 15000);
    loadTimeoutRef.current = loadTimeout;

    let mediaErrCount = 0;
    const hls = new Hls({
      renderTextTracksNatively: false,
      startLevel: -1,
      xhrSetup(xhr) {
        if (hasHeaders) for (const [k, v] of Object.entries(proxyHeaders!)) xhr.setRequestHeader(k, v);
      },
    });
    hls.subtitleDisplay = false;

    hls.on(Hls.Events.MANIFEST_PARSED, (_e, data) => {
      clearTimeout(loadTimeout);
      mediaErrCount = 0;
      const at = hls.audioTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
      const st = hls.subtitleTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
      const ql = data.levels.map((l: { height: number; bitrate: number }) => ({ height: l.height, bitrate: l.bitrate }));
      setAudioTracks(at); setSubTracks(st); setQualityLevels(ql);
      if (at.length > 0) setActiveAudio(hls.audioTrack >= 0 ? hls.audioTrack : 0);
      console.log('[hls] manifest parsed audio:', at.length, 'subs:', st.length, 'levels:', ql.length);
      video.play().catch(() => setState('paused'));
    });

    hls.on(Hls.Events.AUDIO_TRACKS_UPDATED, () => {
      const at = hls.audioTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
      setAudioTracks(at);
      if (hls.audioTrack >= 0) setActiveAudio(hls.audioTrack);
    });

    hls.on(Hls.Events.SUBTITLE_TRACKS_UPDATED, () => {
      const st = hls.subtitleTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
      setSubTracks(st);
      setActiveSub(hls.subtitleTrack);
    });

    hls.on(Hls.Events.AUDIO_TRACK_SWITCHED, (_e, d) => setActiveAudio(d.id));
    hls.on(Hls.Events.SUBTITLE_TRACK_SWITCH, (_e, d) => {
      setActiveSub(d.id);
    });

    hls.on(Hls.Events.ERROR, (_e, data) => {
      if (!data.fatal) return;
      clearTimeout(loadTimeout);
      console.log('[hls] fatal error:', data.type, data.details);
      if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
        mediaErrCount++;
        if (mediaErrCount <= 2) {
          hls.recoverMediaError();
          return;
        }
      }
      fallbackToNative();
    });

    hls.loadSource(streamUrl);
    hls.attachMedia(video);
    hlsRef.current = hls;
  }, [streamUrl, currentStream]);

  useEffect(() => {
    initPlayer();
    return () => {
      if (loadTimeoutRef.current) clearTimeout(loadTimeoutRef.current);
      if (hlsRef.current) { hlsRef.current.destroy(); hlsRef.current = null; }
    };
  }, [initPlayer]);

  // ── Video events ─────────────────────────────────────────────────────────
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const onCanPlay = () => {
      // onPlay is the single exit from 'loading' — don't set 'paused' here
      const resumeAt = savedFailoverPosition.current > 0 ? savedFailoverPosition.current : (startPosRef.current ?? 0);
      if (resumeAt > 0) { video.currentTime = resumeAt; savedFailoverPosition.current = 0; startPosRef.current = undefined; }
    };
    const onPlay = () => setState('playing');
    const onPause = () => { if (!video.ended) setState('paused'); };
    const onEnded = () => setState('ended');
    const onError = () => {
      if (hlsRef.current) return;
      failoverToNextStreamRef.current();
    };
    const onTimeUpdate = () => {
      if (isDragging) return;
      setPos(video.currentTime); setDur(video.duration || 0);
      if (video.buffered.length > 0) setBuf(video.buffered.end(video.buffered.length - 1));
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
  }, [streamUrl, isDragging]);

  // ── Subtitle cue overlay ─────────────────────────────────────────────────
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    function updateCue() {
      if (activeSub < 0 && !externalTrackRef.current) { setActiveCueText(''); return; }
      let text = '';
      for (let i = 0; i < video!.textTracks.length; i++) {
        const track = video!.textTracks[i];
        if (track.kind === 'subtitles' && track.activeCues && track.activeCues.length > 0) {
          for (let j = 0; j < track.activeCues.length; j++) {
            text += (text ? '\n' : '') + (track.activeCues[j] as VTTCue).text;
          }
        }
      }
      setActiveCueText(text);
    }
    video.addEventListener('timeupdate', updateCue);
    return () => video.removeEventListener('timeupdate', updateCue);
  }, [activeSub]);

  // ── Progress reporting ───────────────────────────────────────────────────
  useEffect(() => {
    if (!currentProfile) return;
    progressInterval.current = setInterval(() => {
      const v = videoRef.current;
      if (v && v.currentTime > 0) {
        updateWatchProgress(currentProfile.id, mediaId, mediaType, v.currentTime, v.duration || 0, false, title);
      }
    }, 10000);
    return () => { if (progressInterval.current) clearInterval(progressInterval.current); };
  }, [currentProfile, mediaId, mediaType, title]);

  const onEnded = useCallback(() => {
    if (currentProfile && dur > 0) {
      updateWatchProgress(currentProfile.id, mediaId, mediaType, dur, dur, true, title);
    }
  }, [currentProfile, mediaId, mediaType, dur, title]);

  useEffect(() => {
    if (state === 'ended') onEnded();
  }, [state, onEnded]);

  // ── Controls auto-hide ───────────────────────────────────────────────────
  const resetHide = useCallback(() => {
    setShowControls(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => {
      if (!showSources && !showTracks && !showSpeed) setShowControls(false);
    }, 3500);
  }, [showSources, showTracks, showSpeed]);

  useEffect(() => {
    const el = containerRef.current; if (!el) return;
    const mv = () => { if (!showSources && !showTracks && !showSpeed) resetHide(); };
    const lv = () => { if (!showSources && !showTracks && !showSpeed) setShowControls(false); };
    el.addEventListener('mousemove', mv);
    el.addEventListener('mouseleave', lv);
    resetHide();
    return () => { el.removeEventListener('mousemove', mv); el.removeEventListener('mouseleave', lv); if (hideTimer.current) clearTimeout(hideTimer.current); };
  }, [resetHide, showSources, showTracks, showSpeed]);

  useEffect(() => {
    if (state === 'paused') { setShowControls(true); if (hideTimer.current) clearTimeout(hideTimer.current); }
    else resetHide();
  }, [state, resetHide]);

  // ── Volume ───────────────────────────────────────────────────────────────
  useEffect(() => { const v = videoRef.current; if (v) { v.volume = volume; v.muted = muted; } }, [volume, muted]);

  // ── Fullscreen ───────────────────────────────────────────────────────────
  useEffect(() => {
    const onChange = () => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);

  // ── Playback helpers ─────────────────────────────────────────────────────
  const togglePlay = () => { const v = videoRef.current; if (!v) return; if (v.paused) v.play().catch(() => {}); else v.pause(); };
  const seek = (s: number) => { const v = videoRef.current; if (!v) return; v.currentTime = s; setPos(s); };
  const skip = (s: number) => { const v = videoRef.current; if (!v) return; seek(Math.max(0, Math.min(v.duration || 0, v.currentTime + s))); };
  const toggleFS = () => { const el = containerRef.current; if (!el) return; if (document.fullscreenElement) document.exitFullscreen(); else el.requestFullscreen().catch(() => {}); };
  const switchAudio = (id: number) => { if (hlsRef.current) { hlsRef.current.audioTrack = id; } setShowTracks(false); };
  const switchSub = (id: number) => { if (hlsRef.current) { hlsRef.current.subtitleTrack = id; } setActiveSub(id); setShowTracks(false); };
  const switchQuality = (level: number) => { if (hlsRef.current) hlsRef.current.currentLevel = level; setActiveQuality(level); };

  const switchExternalSub = useCallback(async (sub: SubtitleItem | null) => {
    const video = videoRef.current;
    if (!video) return;
    if (externalTrackRef.current) { try { video.removeChild(externalTrackRef.current); } catch {} externalTrackRef.current = null; }
    if (!sub) { setActiveExternalSubId(null); setActiveCueText(''); setShowTracks(false); return; }
    if (hlsRef.current) hlsRef.current.subtitleTrack = -1;
    setActiveSub(-1);
    try {
      const res = await fetch(sub.url);
      let text = await res.text();
      if (!text.trimStart().startsWith('WEBVTT')) {
        text = 'WEBVTT\n\n' + text.replace(/\r\n/g, '\n').replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2');
      }
      const blob = new Blob([text], { type: 'text/vtt' });
      const blobUrl = URL.createObjectURL(blob);
      const track = document.createElement('track');
      track.kind = 'subtitles'; track.srclang = sub.lang; track.label = sub.name || sub.lang; track.src = blobUrl;
      video.appendChild(track);
      setTimeout(() => { if (track.track) track.track.mode = 'hidden'; }, 50);
      externalTrackRef.current = track;
      setActiveExternalSubId(sub.id);
    } catch (e) { console.error('[sub] failed to load external subtitle', e); }
    setShowTracks(false);
  }, []);

  const failoverToNextStream = useCallback(() => {
    const p = videoRef.current;
    if (p?.currentTime) savedFailoverPosition.current = p.currentTime;
    const nextFailed = new Set(failedUrls);
    nextFailed.add(streamUrl);
    setFailedUrls(nextFailed);
    const next = sortStreamsForBrowserPlayback(streams).find(s => {
      const url = getPlayableStreamUrl(s);
      return url && url !== streamUrl && !nextFailed.has(url);
    });
    if (next) {
      onSwitchStream(next);
    } else {
      setState('error');
      setErrMsg('No playable sources found');
    }
  }, [failedUrls, onSwitchStream, streamUrl, streams]);

  failoverToNextStreamRef.current = failoverToNextStream;

  // ── Seek drag ────────────────────────────────────────────────────────────
  const seekFromEvent = (e: React.MouseEvent | MouseEvent) => {
    const el = e.currentTarget as HTMLElement;
    const rect = el.getBoundingClientRect();
    const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    seek(pct * (dur || 0)); setTooltipText(fmt(pct * (dur || 0)));
  };
  const onSeekMove = (e: React.MouseEvent) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const pct = (e.clientX - rect.left) / rect.width;
    setTooltipPos(pct * 100); setTooltipText(fmt(pct * (dur || 0)));
  };

  // ── Keyboard ─────────────────────────────────────────────────────────────
  useEffect(() => {
    const onK = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.key === ' ' || e.key === 'k') { e.preventDefault(); togglePlay(); }
      if (e.key === 'ArrowLeft') skip(-15);
      if (e.key === 'ArrowRight') skip(15);
      if (e.key === 'ArrowUp') setVolume(v => Math.min(1, v + 0.1));
      if (e.key === 'ArrowDown') setVolume(v => Math.max(0, v - 0.1));
      if (e.key === 'f') toggleFS();
      if (e.key === 'm') { e.preventDefault(); setMuted(m => !m); }
    };
    window.addEventListener('keydown', onK);
    return () => window.removeEventListener('keydown', onK);
  }, []);

  const pct = dur > 0 ? (pos / dur) * 100 : 0;
  const bufPct = dur > 0 ? (buf / dur) * 100 : 0;
  const VolumeIcon = muted || volume === 0 ? VolumeX : volume < 0.5 ? Volume1 : Volume2;

  return (
    <div ref={containerRef} className="fixed inset-0 bg-black z-50 select-none">
      <video ref={videoRef} className="absolute inset-0 w-full h-full" playsInline onClick={togglePlay} />

      {/* Subtitle overlay */}
      {activeCueText && (
        <div className="absolute bottom-24 left-0 right-0 z-10 text-center pointer-events-none px-8">
          <span className="inline-block px-3 py-1.5 bg-black/70 rounded-lg text-white text-lg font-semibold leading-relaxed" style={{ textShadow: '0 1px 2px rgba(0,0,0,0.8)' }}>
            {activeCueText}
          </span>
        </div>
      )}

      {/* Loading */}
      {state === 'loading' && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-5 bg-black/80 z-20">
          <button onClick={onBack} className="absolute top-5 left-6 flex items-center gap-2 text-white/60 hover:text-white transition-colors text-sm font-medium">
            <ChevronLeft size={20} strokeWidth={2} />
            Back
          </button>
          <div className="flex flex-col items-center gap-5">
            {mediaLogo && <img src={mediaLogo} alt="" className="h-10 object-contain" />}
            <h2 className="text-lg font-semibold text-white text-center max-w-sm px-4">{title}</h2>
            <div className="w-56 h-1 rounded-full bg-white/10 overflow-hidden">
              <div className="h-full w-1/2 rounded-full bg-luna-accent animate-pulse" />
            </div>
            <p className="text-sm text-white/45">Loading from {currentStream.addonName || 'Source'}</p>
          </div>
        </div>
      )}

      {/* Error */}
      {state === 'error' && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-black/90 z-20">
          <p className="text-white text-lg font-semibold">Playback Error</p>
          <p className="text-white/50 text-sm">{errMsg}</p>
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

      {/* Controls */}
      <div className={`absolute inset-0 z-10 flex flex-col justify-between transition-opacity duration-300 ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}>
        {/* Top bar */}
        <div className="flex items-center justify-between px-8 pt-6 pb-20" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.8) 0%, transparent 100%)' }}>
          <button onClick={onBack} className="flex items-center gap-2 text-white/80 hover:text-white transition-colors font-medium text-base">
            <ChevronLeft size={22} strokeWidth={2} />
            Back
          </button>
          <p className="text-base font-semibold text-white/70 truncate max-w-[45%]">{title}</p>
          <button onClick={() => setShowSources(true)} className="flex items-center gap-2 bg-white/10 hover:bg-white/15 border border-white/10 rounded-xl px-4 py-2 transition-colors">
            <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${parseQuality(currentStream).color}`}>{parseQuality(currentStream).label}</span>
            <span className="text-sm font-medium text-white/65">{currentStream.addonName || 'Source'}</span>
          </button>
        </div>

        {/* Center: Play + Skip */}
        <div className="flex items-center justify-center gap-16 pointer-events-auto">
          <button onClick={() => skip(-15)} className="opacity-75 hover:opacity-100 transition-opacity active:scale-90">
            <SeekIcon seconds={15} direction="back" />
          </button>
          <button onClick={togglePlay} className="hover:scale-110 active:scale-95 transition-transform">
            {state === 'playing'
              ? <Pause size={76} strokeWidth={0} fill="white" />
              : <Play size={76} strokeWidth={0} fill="white" />}
          </button>
          <button onClick={() => skip(15)} className="opacity-75 hover:opacity-100 transition-opacity active:scale-90">
            <SeekIcon seconds={15} direction="fwd" />
          </button>
        </div>

        {/* Bottom bar */}
        <div className="px-8 pb-8 pt-20" style={{ background: 'linear-gradient(to top, rgba(0,0,0,0.88) 0%, transparent 100%)' }}>
          <p className="text-base font-bold text-white mb-4 truncate">{title}</p>

          {/* Seek */}
          <div
            className="relative flex w-full items-center h-5 cursor-pointer mb-3 group"
            onMouseDown={e => { setIsDragging(true); seekFromEvent(e.nativeEvent); e.preventDefault(); }}
            onMouseMove={e => { if (isDragging) seekFromEvent(e.nativeEvent); else onSeekMove(e); }}
            onMouseUp={() => setIsDragging(false)}
            onMouseLeave={() => setIsDragging(false)}
          >
            <div className="w-full h-1 group-hover:h-[5px] bg-white/20 rounded-full relative transition-all">
              <div className="absolute left-0 top-0 h-full bg-white/30 rounded-full" style={{ width: `${bufPct}%` }} />
              <div className="absolute left-0 top-0 h-full bg-white rounded-full" style={{ width: `${pct}%` }} />
            </div>
            <div className="absolute top-1/2 -translate-y-1/2 w-4 h-4 rounded-full bg-white shadow-lg opacity-0 group-hover:opacity-100 -translate-x-1/2" style={{ left: `${pct}%` }} />
            {isDragging && (
              <div className="absolute -top-8 left-1/2 -translate-x-1/2 bg-black/85 text-white text-xs font-semibold px-2 py-1 rounded whitespace-nowrap pointer-events-none">
                {tooltipText}
              </div>
            )}
          </div>

          {/* Controls row */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5 text-sm font-medium text-white/50 tabular-nums">
              <span>{fmt(pos)}</span>
              <span className="text-white/25">·</span>
              <span>{fmt(dur)}</span>
            </div>

            <div className="flex items-center gap-2">
              {/* Volume */}
              <button onClick={() => setMuted(!muted)} className="w-12 h-12 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                <VolumeIcon size={30} strokeWidth={1.8} className="text-white/90" />
              </button>
              <div className="relative flex w-24 items-center h-8 cursor-pointer group/vol">
                <div className="w-full h-1 group-hover/vol:h-[5px] bg-white/20 rounded-full relative transition-all">
                  <div className="absolute left-0 top-0 h-full bg-white rounded-full" style={{ width: `${muted ? 0 : volume * 100}%` }} />
                </div>
                <input type="range" min={0} max={1} step={0.05} value={muted ? 0 : volume}
                  onChange={e => { setVolume(+e.target.value); setMuted(false); }}
                  className="absolute inset-0 opacity-0 cursor-pointer" />
              </div>

              {/* Subtitles/Audio */}
              <button onClick={() => setShowTracks(true)} className="w-12 h-12 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                <CaptionsIcon size={30} strokeWidth={1.8} className="text-white/90" />
              </button>

              {/* Speed */}
              <div className="relative">
                <button onClick={() => setShowSpeed(p => !p)} className="w-11 h-11 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors text-sm font-bold text-white/55 hover:text-white">
                  {playbackRate === 1 ? '1×' : `${playbackRate}×`}
                </button>
                {showSpeed && (
                  <div className="absolute bottom-full right-0 mb-3 bg-[#141414] border border-white/10 rounded-2xl p-1.5 min-w-[130px] z-30 shadow-xl">
                    {[0.5, 0.75, 1, 1.25, 1.5, 2].map(s => (
                      <button key={s} onClick={() => { if (videoRef.current) videoRef.current.playbackRate = s; setPlaybackRate(s); setShowSpeed(false); }}
                        className={`w-full text-left px-4 py-2.5 rounded-xl text-sm font-medium transition-colors ${s === playbackRate ? 'text-white' : 'text-white/60 hover:bg-white/10 hover:text-white'}`}>
                        {s === 1 ? 'Normal' : `${s}×`}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* Fullscreen */}
              <button onClick={toggleFS} className="w-11 h-11 flex items-center justify-center rounded-full hover:bg-white/10 transition-colors active:scale-95">
                {isFullscreen
                  ? <Minimize size={20} strokeWidth={1.8} className="text-white/80" />
                  : <Maximize size={20} strokeWidth={1.8} className="text-white/80" />}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Tracks popover (Audio + Subtitles) */}
      {showTracks && (
        <div className="absolute inset-0 z-40 flex items-center justify-center px-6">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowTracks(false)} />
          <div className="relative w-[980px] max-w-[94vw] max-h-[76vh] overflow-hidden rounded-2xl bg-[#242424]/98 shadow-2xl border border-white/8">
            <div className="flex items-center justify-between px-8 py-6 border-b border-white/8">
              <h3 className="text-2xl font-bold text-white">Audio & Subtitles</h3>
              <button onClick={() => setShowTracks(false)} className="p-2 rounded-full hover:bg-white/10"><X size={22} className="text-white/70" /></button>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 overflow-y-auto max-h-[60vh]">
              <div className="px-8 py-6 border-r border-white/8">
                <h4 className="text-xl font-bold text-white mb-5">Audio</h4>
                {audioTracks.length > 0 ? audioTracks.map(t => (
                  <button key={t.id} onClick={() => switchAudio(t.id)}
                    className={`flex w-full items-center gap-4 py-3 text-left text-lg ${t.id === activeAudio ? 'text-white' : 'text-white/55 hover:text-white'}`}>
                    <span className="w-5">{t.id === activeAudio ? '✓' : ''}</span><span>{t.name}{t.lang !== '?' ? ` (${t.lang})` : ''}</span>
                  </button>
                )) : <p className="text-white/30 text-sm">No audio tracks in this stream</p>}
              </div>
              <div className="px-8 py-6">
                <h4 className="text-xl font-bold text-white mb-5">Subtitles</h4>
                <button onClick={() => { switchSub(-1); switchExternalSub(null); }}
                  className={`flex w-full items-center gap-4 py-3 text-left text-lg ${activeSub < 0 && !activeExternalSubId ? 'text-white' : 'text-white/55 hover:text-white'}`}>
                  <span className="w-5">{activeSub < 0 && !activeExternalSubId ? '✓' : ''}</span><span>Off</span>
                </button>
                {subTracks.map(t => (
                  <button key={t.id} onClick={() => { switchExternalSub(null); switchSub(t.id); }}
                    className={`flex w-full items-center gap-4 py-3 text-left text-lg ${t.id === activeSub ? 'text-white' : 'text-white/55 hover:text-white'}`}>
                    <span className="w-5">{t.id === activeSub ? '✓' : ''}</span><span>{t.name}{t.lang !== '?' ? ` (${t.lang})` : ''}</span>
                  </button>
                ))}
                {subtitles.map(s => (
                  <button key={s.id} onClick={() => switchExternalSub(s)}
                    className={`flex w-full items-center gap-4 py-3 text-left text-lg ${s.id === activeExternalSubId ? 'text-white' : 'text-white/55 hover:text-white'}`}>
                    <span className="w-5">{s.id === activeExternalSubId ? '✓' : ''}</span><span>{s.name || s.lang}</span>
                  </button>
                ))}
                {subTracks.length === 0 && subtitles.length === 0 && (
                  <p className="text-white/30 text-sm">No subtitle tracks available</p>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Quality popover */}
      {qualityLevels.length > 1 && (
        <div className="absolute bottom-20 left-1/2 -translate-x-1/2 z-30 bg-[#141414] border border-white/10 rounded-2xl p-1.5 shadow-xl">
          <button onClick={() => switchQuality(-1)}
            className={`w-full text-left px-4 py-2 rounded-xl text-sm transition-colors flex items-center justify-between gap-4 ${activeQuality === -1 ? 'text-white' : 'text-white/60 hover:bg-white/10 hover:text-white'}`}>
            <span>Auto</span><span className={`w-1.5 h-1.5 rounded-full bg-luna-accent ${activeQuality === -1 ? 'opacity-100' : 'opacity-0'}`} />
          </button>
          {qualityLevels.map((l, i) => (
            <button key={i} onClick={() => switchQuality(i)}
              className={`w-full text-left px-4 py-2 rounded-xl text-sm transition-colors flex items-center justify-between gap-4 ${i === activeQuality ? 'text-white' : 'text-white/60 hover:bg-white/10 hover:text-white'}`}>
              <span>{l.height}p</span><span className={`w-1.5 h-1.5 rounded-full bg-luna-accent ${i === activeQuality ? 'opacity-100' : 'opacity-0'}`} />
            </button>
          ))}
        </div>
      )}

      {/* Sources panel */}
      {showSources && (
        <div className="absolute inset-0 z-40 flex justify-end">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowSources(false)} />
          <div className="relative w-[430px] max-w-[92vw] h-full bg-[#090910]/95 backdrop-blur-2xl border-l border-white/10 overflow-y-auto shadow-2xl">
            <div className="p-5 border-b border-white/8 flex items-center justify-between sticky top-0 bg-[#090910]/95 backdrop-blur-xl z-10">
              <div>
                <h3 className="text-lg font-semibold text-white">Sources</h3>
                <p className="text-xs text-white/35 mt-0.5">{streams.length} available</p>
              </div>
              <button onClick={() => setShowSources(false)} className="p-2 rounded-full hover:bg-white/10">
                <X size={14} className="text-white/50" />
              </button>
            </div>
            {(() => {
              const compatible = streams.filter(s => s.url && !s.infoHash && !s.behaviorHints?.notWebReady);
              if (compatible.length === 0) return (
                <div className="px-4 py-10 text-center"><p className="text-white/40 text-sm">No playable streams</p></div>
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
                      <button key={s.url || `${name}-${i}`}
                        onClick={() => { setShowSources(false); onSwitchStream(s); }}
                        className={`w-full text-left px-4 py-3.5 mx-2 my-1 rounded-2xl border transition-colors ${isActive ? 'border-luna-accent/70 bg-luna-accent/10' : 'border-white/8 bg-white/[0.035] hover:bg-white/[0.07]'}`}>
                        <div className="flex items-center justify-between gap-2 mb-1.5">
                          <span className={`text-[10px] font-bold px-2 py-0.5 rounded flex-shrink-0 ${q.color}`}>{q.label}</span>
                          <span className="text-[11px] text-white/35 font-medium">{(info.match(/(\d+\.?\d*)\s*(GB|MB|TB)/i)?.[0] || '').toUpperCase()}</span>
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm text-white/70 truncate">{name}</p>
                          <p className="text-[11px] text-white/25 mt-0.5 truncate">{info}</p>
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
    </div>
  );
}
