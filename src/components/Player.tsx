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

interface TrackItem { id: number; name: string; lang: string }

function fmt(seconds: number): string {
  if (!isFinite(seconds) || seconds < 0) return '0:00';
  const s = Math.floor(seconds), m = Math.floor(s / 60), rs = s % 60;
  if (m >= 60) { const h = Math.floor(m / 60); return h + ':' + String(m % 60).padStart(2, '0') + ':' + String(rs).padStart(2, '0'); }
  return m + ':' + String(rs).padStart(2, '0');
}

export default function Player({
  streamUrl, streams, currentStream, title, poster, backdrop,
  mediaId, mediaType, startPosition, onSwitchStream, onBack,
}: PlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const progressInterval = useRef<ReturnType<typeof setInterval> | null>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const startPosRef = useRef<number | undefined>();
  const { currentProfile } = useAuth();

  const [state, setState] = useState<'loading' | 'playing' | 'paused' | 'ended' | 'error'>('loading');
  const [pos, setPos] = useState(0);
  const [dur, setDur] = useState(0);
  const [buf, setBuf] = useState(0);
  const [showControls, setShowControls] = useState(true);
  const [showSources, setShowSources] = useState(false);
  const [showSubPop, setShowSubPop] = useState(false);
  const [showChapPop, setShowChapPop] = useState(false);
  const [showQualPop, setShowQualPop] = useState(false);
  const [errMsg, setErrMsg] = useState('');
  const [volume, setVolume] = useState(1);
  const [muted, setMuted] = useState(false);
  const [audioTracks, setAudioTracks] = useState<TrackItem[]>([]);
  const [activeAudio, setActiveAudio] = useState(-1);
  const [subTracks, setSubTracks] = useState<TrackItem[]>([]);
  const [activeSub, setActiveSub] = useState(-1);
  const [isDragging, setIsDragging] = useState(false);
  const [tooltipPos, setTooltipPos] = useState(0);
  const [tooltipText, setTooltipText] = useState('0:00');
  const [isFullscreen, setIsFullscreen] = useState(false);

  useEffect(() => { startPosRef.current = startPosition; }, [startPosition]);

  // --- hls.js init ---
  const initPlayer = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    if (hlsRef.current) { hlsRef.current.destroy(); hlsRef.current = null; }
    video.src = '';
    setState('loading'); setErrMsg('');
    setAudioTracks([]); setActiveAudio(-1);
    setSubTracks([]); setActiveSub(-1);

    const proxyHeaders = currentStream.behaviorHints?.proxyHeaders?.request;
    const hasHeaders = proxyHeaders != null && Object.keys(proxyHeaders).length > 0;
    const isHls = streamUrl.includes('.m3u8') || streamUrl.includes('/manifest') || streamUrl.includes('/playlist');
    const tryHls = (isHls || hasHeaders) && Hls.isSupported();

    if (tryHls) {
      let errCount = 0;
      const hls = new Hls({
        xhrSetup(xhr) {
          if (hasHeaders) for (const [k, v] of Object.entries(proxyHeaders!)) xhr.setRequestHeader(k, v);
        },
      });

      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        errCount = 0;
        const at = hls.audioTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
        const st = hls.subtitleTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
        if (at.length > 0) { setAudioTracks(at); if (hls.audioTrack >= 0) setActiveAudio(hls.audioTrack); }
        if (st.length > 0) { setSubTracks(st); setActiveSub(hls.subtitleTrack); }
        console.log('[hls] manifest parsed audio:', at.length, 'subs:', st.length);
        video.play().catch(() => {});
      });

      hls.on(Hls.Events.AUDIO_TRACKS_UPDATED, () => {
        const at = hls.audioTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
        setAudioTracks(at);
        if (hls.audioTrack >= 0) setActiveAudio(hls.audioTrack);
        console.log('[hls] audio tracks updated:', at.length, at.map(t => t.lang));
      });

      hls.on(Hls.Events.SUBTITLE_TRACKS_UPDATED, () => {
        const st = hls.subtitleTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
        setSubTracks(st);
        setActiveSub(hls.subtitleTrack);
        console.log('[hls] subtitle tracks updated:', st.length, st.map(t => t.lang));
      });

      hls.on(Hls.Events.AUDIO_TRACK_SWITCHED, (_e, d) => setActiveAudio(d.id));
      hls.on(Hls.Events.SUBTITLE_TRACK_SWITCH, (_e, d) => setActiveSub(d.id));

      hls.on(Hls.Events.ERROR, (_e, data) => {
        errCount++;
        if (data.fatal) {
          console.log('[hls] fatal error type:', data.type, 'count:', errCount);
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR && errCount <= 1) {
            hls.destroy(); hlsRef.current = null;
            video.src = streamUrl; video.play().catch(() => {});
          } else {
            setState('error');
            setErrMsg(data.type === Hls.ErrorTypes.NETWORK_ERROR ? 'Network error' : 'Playback error');
            hls.destroy(); hlsRef.current = null;
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
      if (startPosRef.current && startPosRef.current > 0) {
        video.currentTime = startPosRef.current; startPosRef.current = undefined;
      }
    };
    const onPlay = () => setState('playing');
    const onPause = () => { if (!video.ended) setState('paused'); };
    const onEnded = () => setState('ended');
    const onError = () => { setState('error'); setErrMsg('Failed to play'); };
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

  // --- Progress ---
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
    if (state === 'ended' && currentProfile) updateWatchProgress(currentProfile.id, mediaId, mediaType, dur, dur, true);
  }, [state, currentProfile, mediaId, mediaType, dur]);

  // --- Controls auto-hide ---
  const resetHide = useCallback(() => {
    setShowControls(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => {
      if (!showSubPop && !showChapPop && !showQualPop && !showSources) setShowControls(false);
    }, 3500);
  }, [showSubPop, showChapPop, showQualPop, showSources]);
  useEffect(() => {
    const el = containerRef.current; if (!el) return;
    const mv = () => { if (!showSubPop && !showChapPop && !showQualPop && !showSources) resetHide(); };
    const lv = () => { if (!showSubPop && !showChapPop && !showQualPop && !showSources) setShowControls(false); };
    el.addEventListener('mousemove', mv);
    el.addEventListener('mouseleave', lv);
    resetHide();
    return () => { el.removeEventListener('mousemove', mv); el.removeEventListener('mouseleave', lv); if (hideTimer.current) clearTimeout(hideTimer.current); };
  }, [resetHide, showSubPop, showChapPop, showQualPop, showSources]);

  // --- Volume ---
  useEffect(() => { const v = videoRef.current; if (v) { v.volume = volume; v.muted = muted; } }, [volume, muted]);

  // --- Playback ---
  const togglePlay = () => { const v = videoRef.current; if (!v) return; if (v.paused) v.play().catch(() => {}); else v.pause(); };
  const seek = (s: number) => { const v = videoRef.current; if (!v) return; v.currentTime = s; setPos(s); };
  const skip = (s: number) => { const v = videoRef.current; if (!v) return; seek(Math.max(0, Math.min(v.duration || 0, v.currentTime + s))); };
  const toggleFS = () => { const el = containerRef.current; if (!el) return; if (document.fullscreenElement) document.exitFullscreen(); else el.requestFullscreen().catch(() => {}); };

  // Fullscreen state listener
  useEffect(() => {
    const onChange = () => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);
  const switchAudio = (id: number) => { if (hlsRef.current) { hlsRef.current.audioTrack = id; setActiveAudio(id); } setShowSubPop(false); };
  const switchSub = (id: number) => { if (hlsRef.current) { hlsRef.current.subtitleTrack = id; setActiveSub(id); console.log('[sub] switched to track', id); } setShowSubPop(false); };
  const switchSrc = (s: StreamItem) => { setShowSources(false); onSwitchStream(s); };
  const closePops = useCallback(() => { setShowSubPop(false); setShowChapPop(false); setShowQualPop(false); }, []);
  // Close popovers on outside click
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (!(e.target as HTMLElement).closest('.player-popover') && !(e.target as HTMLElement).closest('[aria-label="Subtitles and audio"]') && !(e.target as HTMLElement).closest('[aria-label="Chapters"]') && !(e.target as HTMLElement).closest('[aria-label="Quality and speed"]')) {
        closePops();
      }
    };
    document.addEventListener('click', onClick);
    return () => document.removeEventListener('click', onClick);
  }, [closePops]);

  // --- Seek drag ---
  const seekFromEvent = (e: React.MouseEvent | MouseEvent) => {
    const el = e.currentTarget as HTMLElement;
    const rect = el.getBoundingClientRect();
    const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    const t = pct * (dur || 0); seek(t); setTooltipText(fmt(t));
  };
  const onSeekMove = (e: React.MouseEvent) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const pct = (e.clientX - rect.left) / rect.width;
    setTooltipPos(pct * 100); setTooltipText(fmt(pct * (dur || 0)));
  };

  // --- Keyboard ---
  useEffect(() => {
    const onK = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.key === ' ' || e.key === 'k') { e.preventDefault(); togglePlay(); }
      if (e.key === 'ArrowLeft') skip(-10);
      if (e.key === 'ArrowRight') skip(10);
      if (e.key === 'ArrowUp') setVolume(v => Math.min(1, v + 0.1));
      if (e.key === 'ArrowDown') setVolume(v => Math.max(0, v - 0.1));
      if (e.key === 'f') toggleFS();
      if (e.key === 'm') { e.preventDefault(); setMuted(m => !m); }
    };
    window.addEventListener('keydown', onK);
    return () => window.removeEventListener('keydown', onK);
  }, []);

  const bgSrc = backdrop || poster;
  const pct = dur > 0 ? (pos / dur) * 100 : 0;
  const bufPct = dur > 0 ? (buf / dur) * 100 : 0;

  const volIcon = muted || volume === 0
    ? <><path d="M6 9H3a1 1 0 00-1 1v4a1 1 0 001 1h3l4.5 4.5a.5.5 0 00.85-.35V4.85a.5.5 0 00-.85-.35L6 9z"/><path d="M23 9l-6 6M17 9l6 6"/></>
    : volume < 0.5
    ? <><path d="M6 9H3a1 1 0 00-1 1v4a1 1 0 001 1h3l4.5 4.5a.5.5 0 00.85-.35V4.85a.5.5 0 00-.85-.35L6 9z"/><path d="M16 8a5 5 0 010 8"/></>
    : <><path d="M6 9H3a1 1 0 00-1 1v4a1 1 0 001 1h3l4.5 4.5a.5.5 0 00.85-.35V4.85a.5.5 0 00-.85-.35L6 9z"/><path d="M16 8a5 5 0 010 8M19 5a8 8 0 010 14"/></>;

  const pausePath = 'M13 8v8m6-8v8';
  const playPath = 'M9.5 7v12l11-6z';

  return (
    <div ref={containerRef} className="fixed inset-0 bg-black z-50 select-none">
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
          <p className="text-luna-muted text-sm">{errMsg}</p>
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
      <div className={`absolute inset-0 z-10 transition-opacity duration-300 ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}>
        <div className="absolute inset-0 bg-gradient-to-b from-black/70 via-transparent to-black/80 pointer-events-none" />

        {/* Bottom bar */}
        <div className="absolute bottom-0 left-0 right-0 p-6 pb-8 space-y-3">
          {/* Seek */}
          <div className="flex items-center gap-3">
            <span className="text-xs text-white/50 w-10 text-right tabular-nums flex-shrink-0">{fmt(pos)}</span>
            <div className="relative flex-1 h-5 flex items-center cursor-pointer group"
              onMouseDown={e => { setIsDragging(true); seekFromEvent(e.nativeEvent); e.preventDefault(); }}
              onMouseMove={e => { if (isDragging) seekFromEvent(e.nativeEvent); else onSeekMove(e); }}
            >
              <div className="w-full h-[2.5px] group-hover:h-[5px] bg-white/12 rounded-full relative transition-all">
                <div className="absolute left-0 top-0 h-full bg-white/16 rounded-full" style={{ width: `${bufPct}%` }} />
                <div className="absolute left-0 top-0 h-full bg-white group-hover:bg-red-600 rounded-full" style={{ width: `${pct}%` }} />
              </div>
              <div className="absolute top-1/2 -translate-y-1/2 w-3 h-3 bg-red-600 rounded-full -translate-x-1/2 pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"
                style={{ left: `${pct}%` }} />
              {isDragging && (
                <div className="absolute -top-8 left-1/2 -translate-x-1/2 bg-black/85 backdrop-blur-md text-white text-xs font-semibold px-2 py-1 rounded whitespace-nowrap pointer-events-none">
                  {tooltipText}
                </div>
              )}
            </div>
            <span className="text-xs text-white/50 w-10 tabular-nums flex-shrink-0">{fmt(dur)}</span>
          </div>

          {/* Controls row */}
          <div className="flex items-center justify-between">
            <div className="w-[140px]" />
            {/* Center: Play + Skip */}
            <div className="flex items-center gap-2">
              <button onClick={() => skip(-10)} className="w-10 h-10 rounded-full flex items-center justify-center hover:bg-white/6 transition-colors" aria-label="Skip back 10s">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="w-5 h-5 text-white/60">
                  <path d="M17 20L7 12m0 0l10-8M7 12h10a4 4 0 010 8h-5"/>
                  <text x="17" y="9" stroke="none" fill="currentColor" fontSize="7" fontWeight="700">10</text>
                </svg>
              </button>
              <button onClick={togglePlay} className="w-11 h-11 bg-white/90 hover:bg-white rounded-full flex items-center justify-center transition-all hover:scale-105 active:scale-95" aria-label={state === 'playing' ? 'Pause' : 'Play'}>
                <svg viewBox="0 0 28 28" fill="currentColor" className="w-5 h-5 text-black">
                  <path d={state === 'playing' ? pausePath : playPath} />
                </svg>
              </button>
              <button onClick={() => skip(10)} className="w-10 h-10 rounded-full flex items-center justify-center hover:bg-white/6 transition-colors" aria-label="Skip forward 10s">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="w-5 h-5 text-white/60">
                  <path d="M7 20l10-8m0 0l-10-8m10 8H7a4 4 0 000 8h5"/>
                  <text x="1" y="9" stroke="none" fill="currentColor" fontSize="7" fontWeight="700">10</text>
                </svg>
              </button>
            </div>

            {/* Right: volume, subs, chapters, quality, fullscreen */}
            <div className="flex items-center gap-1">
              {/* Volume */}
              <div className="flex items-center gap-0 group/vol">
                <button onClick={() => setMuted(!muted)} className="w-9 h-9 rounded-full flex items-center justify-center hover:bg-white/6 transition-colors" aria-label={muted ? 'Unmute' : 'Mute'}>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="w-5 h-5 text-white/55">{volIcon}</svg>
                </button>
                <div className="w-0 overflow-hidden group-hover/vol:w-[68px] transition-all duration-200 flex items-center">
                  <input type="range" min={0} max={1} step={0.05} value={muted ? 0 : volume}
                    onChange={e => { setVolume(+e.target.value); setMuted(false); }}
                    className="w-[60px] h-[2.5px] accent-white bg-white/16 rounded-full cursor-pointer" />
                </div>
              </div>

              {/* Subtitles / Audio */}
              <div className="relative">
                <button onClick={() => { setShowSubPop(!showSubPop); closePops(); }} className="w-9 h-9 rounded-full flex items-center justify-center hover:bg-white/6 transition-colors" aria-label="Subtitles and audio">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="w-5 h-5 text-white/55">
                    <path d="M12 20H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8"/><path d="M8 10h4M8 14h8M18 16v4M16 18h4"/>
                  </svg>
                </button>
                {showSubPop && (
                  <div className="absolute bottom-full right-0 mb-2 bg-neutral-900/95 backdrop-blur-2xl border border-white/6 rounded-xl player-popover p-1.5 min-w-[260px] shadow-2xl z-30">
                    <div className="px-3 pt-2 pb-1 text-[10px] font-semibold text-white/25 uppercase tracking-wider">Audio</div>
                    {audioTracks.length > 0 ? audioTracks.map(t => (
                      <button key={t.id} onClick={() => switchAudio(t.id)}
                        className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${t.id === activeAudio ? 'text-white' : 'text-white/65 hover:bg-white/4'}`}>
                        <span>{t.name}{t.lang !== '?' ? ` (${t.lang})` : ''}</span>
                        <span className={`w-1.5 h-1.5 rounded-full bg-red-600 flex-shrink-0 ${t.id === activeAudio ? 'opacity-100' : 'opacity-0'}`} />
                      </button>
                    )) : (
                      <div className="px-3 py-2 text-xs text-white/25">No audio tracks detected</div>
                    )}
                    <div className="mx-2 my-1.5 h-px bg-white/4" />
                    <div className="px-3 pt-1 pb-1 text-[10px] font-semibold text-white/25 uppercase tracking-wider">Subtitles</div>
                    <button onClick={() => switchSub(-1)}
                      className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${activeSub < 0 ? 'text-white' : 'text-white/65 hover:bg-white/4'}`}>
                      <span>Off</span><span className={`w-1.5 h-1.5 rounded-full bg-red-600 ${activeSub < 0 ? 'opacity-100' : 'opacity-0'}`} />
                    </button>
                    {subTracks.length > 0 ? subTracks.map(t => (
                      <button key={t.id} onClick={() => switchSub(t.id)}
                        className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${t.id === activeSub ? 'text-white' : 'text-white/65 hover:bg-white/4'}`}>
                        <span>{t.name}{t.lang !== '?' ? ` (${t.lang})` : ''}</span>
                        <span className={`w-1.5 h-1.5 rounded-full bg-red-600 flex-shrink-0 ${t.id === activeSub ? 'opacity-100' : 'opacity-0'}`} />
                      </button>
                    )) : (
                      <div className="px-3 py-2 text-xs text-white/25">No subtitle tracks detected</div>
                    )}
                  </div>
                )}
              </div>

              {/* Chapters */}
              <div className="relative">
                <button onClick={() => { setShowChapPop(!showChapPop); closePops(); }} className="w-9 h-9 rounded-full flex items-center justify-center hover:bg-white/6 transition-colors" aria-label="Chapters">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="w-5 h-5 text-white/55">
                    <circle cx="6" cy="6" r="1"/><circle cx="6" cy="12" r="1"/><circle cx="6" cy="18" r="1"/>
                    <rect x="10" y="4" width="10" height="3" rx="1"/><rect x="10" y="11" width="10" height="3" rx="1"/><rect x="10" y="18" width="7" height="3" rx="1"/>
                  </svg>
                </button>
                {showChapPop && (
                  <div className="absolute bottom-full right-0 mb-2 bg-neutral-900/95 backdrop-blur-2xl border border-white/6 rounded-xl player-popover p-2 min-w-[280px] shadow-2xl z-30">
                    <div className="px-3 pt-1 pb-2 text-[10px] font-semibold text-white/25 uppercase tracking-wider">Chapters</div>
                    {[...Array(6)].map((_, i) => {
                      const ch = ['Opening Credits','The Meadow','Bunny vs Rodents','The Chase','Revenge','End Credits'];
                      return (
                        <button key={i} onClick={() => { seek(dur * (i * 0.17)); closePops(); }}
                          className="w-full flex gap-3 px-3 py-2 rounded-lg hover:bg-white/4 transition-colors text-left">
                          <div className="w-[68px] h-9 bg-white/4 rounded flex items-center justify-center text-xs text-white/12 font-semibold flex-shrink-0">{i + 1}</div>
                          <div className="min-w-0"><div className="text-xs font-semibold text-white truncate">{ch[i]}</div><div className="text-[11px] text-white/25 mt-0.5">{fmt(dur * (i * 0.17))}</div></div>
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>

              {/* Quality */}
              <div className="relative">
                <button onClick={() => { setShowQualPop(!showQualPop); closePops(); }} className="w-9 h-9 rounded-full flex items-center justify-center hover:bg-white/6 transition-colors" aria-label="Quality and speed">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="w-5 h-5 text-white/55">
                    <circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/>
                  </svg>
                </button>
                {showQualPop && (
                  <div className="absolute bottom-full right-0 mb-2 bg-neutral-900/95 backdrop-blur-2xl border border-white/6 rounded-xl player-popover p-1.5 min-w-[180px] shadow-2xl z-30">
                    <div className="px-3 pt-1 pb-1 text-[10px] font-semibold text-white/25 uppercase tracking-wider">Quality</div>
                    {['Auto','4K HDR','1080p','720p','480p'].map((q, i) => (
                      <button key={q} className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${i === 0 ? 'text-white' : 'text-white/65 hover:bg-white/4'}`}>
                        <span>{q}{q === '4K HDR' && <span className="ml-1.5 text-[10px] font-bold text-red-600 bg-red-600/8 px-1.5 py-0.5 rounded">HDR</span>}</span>
                        <span className={`w-1.5 h-1.5 rounded-full bg-red-600 ${i === 0 ? 'opacity-100' : 'opacity-0'}`} />
                      </button>
                    ))}
                    <div className="mx-2 my-1.5 h-px bg-white/4" />
                    <div className="px-3 pt-1 pb-1 text-[10px] font-semibold text-white/25 uppercase tracking-wider">Speed</div>
                    {[0.5, 0.75, 1, 1.25, 1.5, 2].map(s => (
                      <button key={s} onClick={() => { const v = videoRef.current; if (v) v.playbackRate = s; closePops(); }}
                        className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${s === 1 ? 'text-white' : 'text-white/65 hover:bg-white/4'}`}>
                        <span>{s === 1 ? 'Normal' : `${s}×`}</span>
                        <span className={`w-1.5 h-1.5 rounded-full bg-red-600 ${s === 1 ? 'opacity-100' : 'opacity-0'}`} />
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* Fullscreen */}
              <button onClick={toggleFS} className="w-9 h-9 rounded-full flex items-center justify-center hover:bg-white/6 transition-colors" aria-label="Fullscreen">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="w-5 h-5 text-white/55">
                  {isFullscreen
                    ? <><path d="M4 8V5a2 2 0 012-2h3M16 3h3a2 2 0 012 2v3M4 16v3a2 2 0 002 2h3M16 21h3a2 2 0 002-2v-3"/><circle cx="12" cy="12" r="2"/></>
                    : <path d="M8 3H5a2 2 0 00-2 2v3M16 3h3a2 2 0 012 2v3M8 21H5a2 2 0 01-2-2v-3M16 21h3a2 2 0 002-2v-3"/>}
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Center overlay (controls hidden) */}
      {!showControls && state === 'paused' && (
        <button onClick={togglePlay} className="absolute inset-0 z-10 flex items-center justify-center">
          <div className="w-16 h-16 rounded-full bg-black/45 backdrop-blur-sm flex items-center justify-center">
            <svg viewBox="0 0 24 24" fill="white" className="w-8 h-8 ml-1"><polygon points="6,4 20,12 6,20" /></svg>
          </div>
        </button>
      )}

      {/* Source panel */}
      {showSources && (
        <div className="absolute inset-0 z-40 flex justify-end">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowSources(false)} />
          <div className="relative w-80 max-w-[85vw] h-full bg-neutral-950 border-l border-white/8 overflow-y-auto">
            <div className="p-4 border-b border-white/8 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-white">Sources</h3>
              <button onClick={() => setShowSources(false)} className="p-1 rounded-full hover:bg-white/8">
                <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" className="w-5 h-5 text-white/40"><path d="M6 18L18 6M6 6l12 12"/></svg>
              </button>
            </div>
            {(() => {
              const grp: Record<string, StreamItem[]> = {};
              for (const s of streams) { const k = s.addonName || 'Unknown'; (grp[k] ??= []).push(s); }
              return Object.entries(grp).map(([name, items]) => (
                <div key={name} className="border-b border-white/4 last:border-b-0">
                  <div className="px-4 pt-3 pb-1"><p className="text-[10px] font-semibold text-white/25 uppercase tracking-wider">{name}</p></div>
                  {items.map(s => (
                    <button key={s.url || Math.random().toString()} onClick={() => switchSrc(s)}
                      className={`w-full text-left px-4 py-3 hover:bg-white/4 flex items-center justify-between ${s.url === currentStream.url ? 'bg-luna-accent/10 border-l-2 border-luna-accent' : ''}`}>
                      <div className="min-w-0 flex-1"><p className="text-sm text-white truncate">{s.title || s.name || s.description || 'Unknown'}</p></div>
                      {s.url === currentStream.url && <div className="w-1.5 h-1.5 rounded-full bg-luna-accent flex-shrink-0 ml-2" />}
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
