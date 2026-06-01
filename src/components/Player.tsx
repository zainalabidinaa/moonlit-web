'use client';

import { useEffect, useRef, useState, useCallback } from 'react';
import Hls from 'hls.js';
import { SFSymbol } from '@/components/SFSymbol';
import { StreamItem } from '@/lib/types';
import { SubtitleItem } from '@/lib/stremio';
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

// Audio codecs Chrome/Firefox cannot decode — streams with these will play video
// but produce silence in the browser (DTS, TrueHD, raw Atmos require native decoders).
const BAD_AUDIO_CODECS = ['dts', 'truehd', 'atmos', 'remux', 'blu-ray', 'bluray'];
function isWebCompatAudio(s: StreamItem): boolean {
  // Concatenate all fields — Torrentio puts codec info in different fields
  // depending on the stream, so we must check all of them.
  const t = `${s.name ?? ''} ${s.title ?? ''} ${s.description ?? ''}`.toLowerCase();
  return !BAD_AUDIO_CODECS.some(k => t.includes(k));
}

export default function Player({
  streamUrl, streams, currentStream, title, poster, backdrop,
  mediaId, mediaType, startPosition, subtitles = [], onSwitchStream, onBack,
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
  const [showQualPop, setShowQualPop] = useState(false);
  const [showSpeedPop, setShowSpeedPop] = useState(false);
  const [errMsg, setErrMsg] = useState('');
  const [volume, setVolume] = useState(1);
  const [muted, setMuted] = useState(false);
  const [audioTracks, setAudioTracks] = useState<TrackItem[]>([]);
  const [activeAudio, setActiveAudio] = useState(-1);
  const [subTracks, setSubTracks] = useState<TrackItem[]>([]);
  const [activeSub, setActiveSub] = useState(-1);
  const [qualityLevels, setQualityLevels] = useState<{ height: number; bitrate: number }[]>([]);
  const [activeQuality, setActiveQuality] = useState(-1);
  const [playbackRate, setPlaybackRate] = useState(1);
  const [isDragging, setIsDragging] = useState(false);
  const [tooltipPos, setTooltipPos] = useState(0);
  const [tooltipText, setTooltipText] = useState('0:00');
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [activeCueText, setActiveCueText] = useState('');
  const [isHlsStream, setIsHlsStream] = useState(false);

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
    setQualityLevels([]); setActiveQuality(-1);
    setActiveCueText('');

    const proxyHeaders = currentStream.behaviorHints?.proxyHeaders?.request;
    const hasHeaders = proxyHeaders != null && Object.keys(proxyHeaders).length > 0;

    console.log('[player] streamUrl:', streamUrl);

    if (Hls.isSupported()) {
      // Always try HLS.js — many Real-Debrid/debrid URLs are HLS without .m3u8 in the URL.
      // If the content isn't HLS, HLS.js fires a manifest error and we fall back to direct.
      let mediaErrCount = 0;
      setIsHlsStream(true);

      const hls = new Hls({
        renderTextTracksNatively: false,
        startLevel: -1,
        xhrSetup(xhr) {
          if (hasHeaders) for (const [k, v] of Object.entries(proxyHeaders!)) xhr.setRequestHeader(k, v);
        },
      });
      hls.subtitleDisplay = false;

      hls.on(Hls.Events.MANIFEST_PARSED, (_e, data) => {
        const at = hls.audioTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
        const st = hls.subtitleTracks.map((t, i) => ({ id: i, name: t.name || t.lang || 'Unknown', lang: t.lang || '?' }));
        const ql = data.levels.map((l: { height: number; bitrate: number }) => ({ height: l.height, bitrate: l.bitrate }));
        setAudioTracks(at); setSubTracks(st); setQualityLevels(ql);
        if (at.length > 0) setActiveAudio(hls.audioTrack >= 0 ? hls.audioTrack : 0);
        console.log('[hls] manifest parsed audio:', at.length, 'subs:', st.length, 'levels:', ql.length);
        console.log('[hls] audio tracks:', hls.audioTracks.length, hls.audioTracks.map(t => `${t.name}(${t.lang})`));
        console.log('[hls] subtitle tracks:', hls.subtitleTracks.length, hls.subtitleTracks.map(t => `${t.name}(${t.lang})`));
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
      hls.on(Hls.Events.SUBTITLE_TRACK_SWITCH, (_e, d) => {
        setActiveSub(d.id);
        // DO NOT set hls.subtitleDisplay here — it conflicts with custom overlay
      });

      hls.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal) {
          console.log('[hls] fatal error:', data.type, data.details);
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
            mediaErrCount++;
            if (mediaErrCount <= 2) {
              hls.recoverMediaError();
            } else {
              hls.destroy(); hlsRef.current = null;
              video.src = streamUrl;
              video.play().catch(() => {});
            }
          } else {
            // Any other fatal error (network, CORS, manifest parse, etc.) —
            // fall back to direct src. If that also fails, the video element's
            // 'error' event will surface the error state.
            console.log('[hls] falling back to direct src:', data.details);
            hls.destroy(); hlsRef.current = null;
            setIsHlsStream(false);
            video.src = streamUrl;
            video.play().catch(() => {});
          }
        }
      });

      hls.loadSource(streamUrl);
      hls.attachMedia(video);
      hlsRef.current = hls;
    } else {
      // HLS.js not supported (e.g. Safari uses native HLS) — go direct
      setIsHlsStream(false);
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
      setState(video.paused ? 'paused' : 'playing');
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
      // Sync play state from video element truth to avoid stale state after async play()
      setState(prev => {
        if (!video.paused && prev === 'paused') return 'playing';
        if (video.paused && prev === 'playing') return 'paused';
        return prev;
      });
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

  // --- Subtitle cue overlay ---
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    function updateCue() {
      if (activeSub < 0 && !externalTrackRef.current) { setActiveCueText(''); return; }
      let text = '';
      for (let i = 0; i < video!.textTracks.length; i++) {
        const track = video!.textTracks[i];
        if (track.kind !== 'subtitles' && track.kind !== 'captions') continue;
        if (track.mode === 'disabled') continue;
        if (!track.activeCues?.length) continue;
        for (let j = 0; j < track.activeCues.length; j++) {
          const cue = track.activeCues[j] as VTTCue;
          const cueHTML = (cue as VTTCue).getCueAsHTML?.();
          const cueText = cueHTML
            ? cueHTML.textContent ?? ''
            : (cue as VTTCue).text?.replace(/<[^>]+>/g, '') ?? '';
          if (cueText.trim()) text += (text ? '\n' : '') + cueText.trim();
        }
        if (text) break;
      }
      setActiveCueText(text);
    }
    video.addEventListener('timeupdate', updateCue);
    return () => video.removeEventListener('timeupdate', updateCue);
  }, [streamUrl]);


  // --- Progress reporting ---
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
      if (!showSubPop && !showQualPop && !showSpeedPop && !showSources) setShowControls(false);
    }, 3500);
  }, [showSubPop, showQualPop, showSpeedPop, showSources]);

  useEffect(() => {
    const el = containerRef.current; if (!el) return;
    const mv = () => { if (!showSubPop && !showQualPop && !showSpeedPop && !showSources) resetHide(); };
    const lv = () => { if (!showSubPop && !showQualPop && !showSpeedPop && !showSources) setShowControls(false); };
    el.addEventListener('mousemove', mv);
    el.addEventListener('mouseleave', lv);
    resetHide();
    return () => { el.removeEventListener('mousemove', mv); el.removeEventListener('mouseleave', lv); if (hideTimer.current) clearTimeout(hideTimer.current); };
  }, [resetHide, showSubPop, showQualPop, showSpeedPop, showSources]);

  // --- Global mouseup for drag ---
  useEffect(() => {
    const onUp = () => setIsDragging(false);
    window.addEventListener('mouseup', onUp);
    return () => window.removeEventListener('mouseup', onUp);
  }, []);

  // --- Volume ---
  useEffect(() => { const v = videoRef.current; if (v) { v.volume = volume; v.muted = muted; } }, [volume, muted]);

  // --- Playback ---
  const togglePlay = () => { const v = videoRef.current; if (!v) return; if (v.paused) v.play().catch(() => {}); else v.pause(); };
  const seek = (s: number) => { const v = videoRef.current; if (!v) return; v.currentTime = s; setPos(s); };
  const skip = (s: number) => { const v = videoRef.current; if (!v) return; seek(Math.max(0, Math.min(v.duration || 0, v.currentTime + s))); };
  const toggleFS = () => { const el = containerRef.current; if (!el) return; if (document.fullscreenElement) document.exitFullscreen(); else el.requestFullscreen().catch(() => {}); };

  // AirPlay
  const triggerAirPlay = () => {
    const video = videoRef.current as HTMLVideoElement & { webkitShowPlaybackTargetPicker?: () => void };
    if (video?.webkitShowPlaybackTargetPicker) video.webkitShowPlaybackTargetPicker();
  };

  // PiP
  const triggerPiP = async () => {
    const video = videoRef.current as HTMLVideoElement & { requestPictureInPicture?: () => Promise<void> };
    if (video?.requestPictureInPicture) {
      try { await video.requestPictureInPicture(); } catch { /* ignore */ }
    }
  };

  // Fullscreen state listener
  useEffect(() => {
    const onChange = () => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);

  const switchAudio = (id: number) => { if (hlsRef.current) { hlsRef.current.audioTrack = id; } setShowSubPop(false); };
  const switchSub = (id: number) => {
    if (hlsRef.current) { hlsRef.current.subtitleTrack = id; }
    setActiveSub(id);
    setShowSubPop(false);
  };

  const externalTrackRef = useRef<HTMLTrackElement | null>(null);
  const [activeExternalSubId, setActiveExternalSubId] = useState<string | null>(null);

  const switchExternalSub = useCallback(async (sub: SubtitleItem | null) => {
    const video = videoRef.current;
    if (!video) return;

    // Remove previous external track
    if (externalTrackRef.current) {
      try { video.removeChild(externalTrackRef.current); } catch {}
      externalTrackRef.current = null;
    }

    if (!sub) { setActiveExternalSubId(null); setActiveCueText(''); setShowSubPop(false); return; }

    // Deactivate HLS subtitle tracks
    if (hlsRef.current) hlsRef.current.subtitleTrack = -1;
    setActiveSub(-1);

    try {
      const res = await fetch(sub.url);
      let text = await res.text();
      // Convert SRT to VTT if needed
      if (!text.trimStart().startsWith('WEBVTT')) {
        text = 'WEBVTT\n\n' + text.replace(/\r\n/g, '\n').replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2');
      }
      const blob = new Blob([text], { type: 'text/vtt' });
      const blobUrl = URL.createObjectURL(blob);

      const track = document.createElement('track');
      track.kind = 'subtitles';
      track.srclang = sub.lang;
      track.label = sub.name || sub.lang;
      track.src = blobUrl;
      video.appendChild(track);
      // hidden = cues fire, browser doesn't render natively
      setTimeout(() => { if (track.track) track.track.mode = 'hidden'; }, 50);

      externalTrackRef.current = track;
      setActiveExternalSubId(sub.id);
    } catch (e) {
      console.error('[sub] failed to load external subtitle', e);
    }
    setShowSubPop(false);
  }, []);
  const switchQuality = (level: number) => {
    if (hlsRef.current) hlsRef.current.currentLevel = level;
    setActiveQuality(level);
    setShowQualPop(false);
  };
  const switchSpeed = (rate: number) => {
    const v = videoRef.current; if (v) v.playbackRate = rate;
    setPlaybackRate(rate);
    setShowSpeedPop(false);
  };
  const switchSrc = (s: StreamItem) => { setShowSources(false); onSwitchStream(s); };

  const closePops = useCallback(() => { setShowSubPop(false); setShowQualPop(false); setShowSpeedPop(false); }, []);

  // Close popovers on outside click
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (
        !(e.target as HTMLElement).closest('.player-popover') &&
        !(e.target as HTMLElement).closest('[aria-label="Subtitles and audio"]') &&
        !(e.target as HTMLElement).closest('[aria-label="Quality"]') &&
        !(e.target as HTMLElement).closest('[aria-label="Speed"]')
      ) {
        closePops();
      }
    };
    document.addEventListener('click', onClick);
    return () => document.removeEventListener('click', onClick);
  }, [closePops]);

  // --- Seek drag ---
  const seekFromClientX = (clientX: number, rect: DOMRect) => {
    const pct = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    const t = pct * (dur || 0); seek(t); setTooltipText(fmt(t));
  };

  const onSeekBarMouseDown = (e: React.MouseEvent<HTMLDivElement>) => {
    setIsDragging(true);
    const rect = e.currentTarget.getBoundingClientRect();
    seekFromClientX(e.clientX, rect);
    e.preventDefault();

    const onMove = (me: MouseEvent) => { seekFromClientX(me.clientX, rect); };
    const onUp = () => {
      setIsDragging(false);
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    };
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  };

  const onSeekMove = (e: React.MouseEvent<HTMLDivElement>) => {
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
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const bgSrc = backdrop || poster;
  const pct = dur > 0 ? (pos / dur) * 100 : 0;
  const bufPct = dur > 0 ? (buf / dur) * 100 : 0;

  return (
    <div ref={containerRef} className="fixed inset-0 bg-black z-50 select-none">
      <video ref={videoRef} className="absolute inset-0 w-full h-full" playsInline onClick={togglePlay} />

      {/* Subtitle cue overlay */}
      {activeCueText && (
        <div className="absolute bottom-28 left-0 right-0 flex justify-center pointer-events-none z-20 px-6">
          <div className="bg-black/75 text-white text-base font-medium px-4 py-2 rounded-lg text-center leading-snug whitespace-pre-line">
            {activeCueText}
          </div>
        </div>
      )}

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

      {/* Controls overlay */}
      <div className={`absolute inset-0 z-10 transition-opacity duration-300 ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}>

        {/* TOP BAR */}
        <div className="absolute top-0 left-0 right-0 flex items-center justify-between px-5 pt-5 bg-gradient-to-b from-black/60 to-transparent pointer-events-none">
          {/* Back — plain text + icon, no pill */}
          <button
            onClick={onBack}
            className="flex items-center gap-1.5 text-white/85 hover:text-white text-sm font-medium pointer-events-auto"
            aria-label="Back"
          >
            <SFSymbol name="chevron.left" size={14} opacity={0.85} />
            Back
          </button>

          <p className="text-sm font-medium text-white/70 truncate max-w-[40%]">{title}</p>

          <div className="flex gap-3 pointer-events-auto">
            <button
              onClick={triggerAirPlay}
              className="text-white/65 hover:text-white"
              aria-label="AirPlay"
            >
              <SFSymbol name="airplayvideo" size={20} opacity={0.7} />
            </button>
            <button
              onClick={triggerPiP}
              className="text-white/65 hover:text-white"
              aria-label="Picture in Picture"
            >
              <SFSymbol name="rectangle.on.rectangle" size={20} opacity={0.7} />
            </button>
          </div>
        </div>

        {/* CENTER: Skip + Play/Pause */}
        <div className="absolute inset-0 flex items-center justify-center gap-12 pointer-events-none">
          {/* Skip back 15s */}
          <button
            onClick={() => skip(-15)}
            className="pointer-events-auto flex flex-col items-center gap-1.5 hover:opacity-80"
            aria-label="Skip back 15 seconds"
          >
            <SFSymbol name="gobackward.15" size={36} opacity={0.8} />
            <span className="text-[9px] tracking-widest text-white/35 font-semibold">BACK</span>
          </button>

          {/* Play / Pause */}
          <button
            onClick={togglePlay}
            className="pointer-events-auto w-16 h-16 rounded-full bg-white/20 hover:bg-white/30 flex items-center justify-center transition-colors"
            aria-label={state === 'playing' ? 'Pause' : 'Play'}
          >
            {state === 'playing'
              ? <SFSymbol name="pause.fill" size={24} />
              : <SFSymbol name="play.fill" size={24} />}
          </button>

          {/* Skip forward 15s */}
          <button
            onClick={() => skip(15)}
            className="pointer-events-auto flex flex-col items-center gap-1.5 hover:opacity-80"
            aria-label="Skip forward 15 seconds"
          >
            <SFSymbol name="goforward.15" size={36} opacity={0.8} />
            <span className="text-[9px] tracking-widest text-white/35 font-semibold">FWD</span>
          </button>
        </div>

        {/* BOTTOM SHELF — full-width gradient */}
        <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 via-black/40 to-transparent px-6 pb-6 pt-20">
          {/* Show title */}
          <p className="text-sm font-semibold text-white mb-2">{title}</p>

          {/* Scrubber row */}
          <div className="flex items-center gap-3">
            <span className="text-xs text-white/50 w-10 text-right tabular-nums flex-shrink-0">{fmt(pos)}</span>
            <div
              className="relative flex-1 h-5 flex items-center cursor-pointer group"
              onMouseDown={onSeekBarMouseDown}
              onMouseMove={onSeekMove}
              onMouseLeave={() => { if (!isDragging) setTooltipPos(0); }}
            >
              <div className="w-full h-[2.5px] group-hover:h-[5px] bg-white/12 rounded-full relative transition-all">
                <div className="absolute left-0 top-0 h-full bg-white/16 rounded-full" style={{ width: `${bufPct}%` }} />
                <div className="absolute left-0 top-0 h-full bg-white group-hover:bg-luna-accent rounded-full transition-colors" style={{ width: `${pct}%` }} />
              </div>
              <div
                className="absolute top-1/2 -translate-y-1/2 w-3 h-3 bg-luna-accent rounded-full -translate-x-1/2 pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity"
                style={{ left: `${pct}%` }}
              />
              {(isDragging || tooltipPos > 0) && (
                <div
                  className="absolute -top-8 bg-black/85 backdrop-blur-md text-white text-xs font-semibold px-2 py-1 rounded whitespace-nowrap pointer-events-none -translate-x-1/2"
                  style={{ left: `${tooltipPos}%` }}
                >
                  {tooltipText}
                </div>
              )}
            </div>
            <span className="text-xs text-white/50 w-10 tabular-nums flex-shrink-0">{fmt(dur)}</span>
          </div>

          {/* Controls row */}
          <div className="flex items-center justify-between mt-2">
            {/* Left: Volume — always visible */}
            <div className="flex items-center gap-2">
              <button
                onClick={() => setMuted(m => !m)}
                className="flex items-center justify-center text-white/60 hover:text-white transition-colors"
                aria-label={muted ? 'Unmute' : 'Mute'}
              >
                {muted || volume === 0
                  ? <SFSymbol name="speaker.slash.fill" size={18} opacity={0.7} />
                  : volume < 0.5
                  ? <SFSymbol name="speaker.1.fill" size={18} opacity={0.7} />
                  : <SFSymbol name="speaker.3" size={18} opacity={0.7} />}
              </button>
              <input
                type="range" min={0} max={1} step={0.05}
                value={muted ? 0 : volume}
                onChange={e => { setVolume(+e.target.value); setMuted(false); }}
                className="w-[60px] h-[3px] accent-white bg-white/20 rounded-full cursor-pointer"
                style={{ accentColor: 'white' }}
              />
            </div>

            {/* Right: Subtitles, Speed, Quality, Sources, Fullscreen */}
            <div className="flex items-center gap-1">
              {/* Sources */}
              <button
                onClick={() => setShowSources(true)}
                className="w-9 h-9 rounded-full flex items-center justify-center text-white/60 hover:text-white hover:bg-white/8 transition-colors"
                aria-label="Sources"
              >
                <SFSymbol name="ellipsis" size={18} opacity={0.7} />
              </button>

              {/* Subtitles / Audio */}
              <div className="relative">
                <button
                  onClick={() => { setShowSubPop(p => !p); setShowQualPop(false); setShowSpeedPop(false); }}
                  className="w-9 h-9 rounded-full flex items-center justify-center text-white/60 hover:text-white hover:bg-white/8 transition-colors"
                  aria-label="Subtitles and audio"
                >
                  <SFSymbol name="captions.bubble.fill" size={18} opacity={activeSub >= 0 || activeExternalSubId ? 1 : 0.65} />
                </button>
                {showSubPop && (
                  <div className="absolute bottom-full right-0 mb-2 rounded-xl player-popover p-1.5 min-w-[260px] z-30 bg-neutral-900 border border-white/10">
                    <div className="px-3 pt-2 pb-1 text-[10px] font-semibold text-white/30 uppercase tracking-wider">Audio</div>
                    {audioTracks.length > 0 ? audioTracks.map(t => (
                      <button key={t.id} onClick={() => switchAudio(t.id)}
                        className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${t.id === activeAudio ? 'text-white' : 'text-white/65 hover:bg-white/6'}`}>
                        <span>{t.name}{t.lang !== '?' ? ` (${t.lang})` : ''}</span>
                        <span className={`w-1.5 h-1.5 rounded-full bg-luna-accent flex-shrink-0 ${t.id === activeAudio ? 'opacity-100' : 'opacity-0'}`} />
                      </button>
                    )) : (
                      <div className="px-3 py-2 text-xs text-white/30">No audio tracks in this stream</div>
                    )}
                    <div className="mx-2 my-1.5 h-px bg-white/6" />
                    <div className="px-3 pt-1 pb-1 text-[10px] font-semibold text-white/30 uppercase tracking-wider">Subtitles</div>
                    <button onClick={() => { switchSub(-1); switchExternalSub(null); }}
                      className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${activeSub < 0 && !activeExternalSubId ? 'text-white' : 'text-white/65 hover:bg-white/6'}`}>
                      <span>Off</span>
                      <span className={`w-1.5 h-1.5 rounded-full bg-luna-accent ${activeSub < 0 && !activeExternalSubId ? 'opacity-100' : 'opacity-0'}`} />
                    </button>
                    {subTracks.map(t => (
                      <button key={t.id} onClick={() => { switchExternalSub(null); switchSub(t.id); }}
                        className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${t.id === activeSub ? 'text-white' : 'text-white/65 hover:bg-white/6'}`}>
                        <span>{t.name}{t.lang !== '?' ? ` (${t.lang})` : ''}</span>
                        <span className={`w-1.5 h-1.5 rounded-full bg-luna-accent flex-shrink-0 ${t.id === activeSub ? 'opacity-100' : 'opacity-0'}`} />
                      </button>
                    ))}
                    {subtitles.map(s => (
                      <button key={s.id} onClick={() => switchExternalSub(s)}
                        className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${s.id === activeExternalSubId ? 'text-white' : 'text-white/65 hover:bg-white/6'}`}>
                        <span>{s.name || s.lang}</span>
                        <span className={`w-1.5 h-1.5 rounded-full bg-luna-accent flex-shrink-0 ${s.id === activeExternalSubId ? 'opacity-100' : 'opacity-0'}`} />
                      </button>
                    ))}
                    {subTracks.length === 0 && subtitles.length === 0 && (
                      <div className="px-3 py-2 text-xs text-white/30">No subtitle tracks in this stream</div>
                    )}
                  </div>
                )}
              </div>

              {/* Speed */}
              <div className="relative">
                <button
                  onClick={() => { setShowSpeedPop(p => !p); setShowQualPop(false); setShowSubPop(false); }}
                  className="w-9 h-9 rounded-full flex items-center justify-center text-white/60 hover:text-white hover:bg-white/8 transition-colors"
                  aria-label="Speed"
                >
                  <SFSymbol name="speedometer" size={18} opacity={0.7} />
                </button>
                {showSpeedPop && (
                  <div className="absolute bottom-full right-0 mb-2 rounded-xl player-popover p-1.5 min-w-[160px] z-30 bg-neutral-900 border border-white/10">
                    <div className="px-3 pt-1 pb-1 text-[10px] font-semibold text-white/30 uppercase tracking-wider">Speed</div>
                    {[0.5, 0.75, 1, 1.25, 1.5, 2].map(s => (
                      <button key={s} onClick={() => switchSpeed(s)}
                        className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${s === playbackRate ? 'text-white' : 'text-white/65 hover:bg-white/6'}`}>
                        <span>{s === 1 ? 'Normal' : `${s}×`}</span>
                        <span className={`w-1.5 h-1.5 rounded-full bg-luna-accent ${s === playbackRate ? 'opacity-100' : 'opacity-0'}`} />
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* Quality */}
              <div className="relative">
                <button
                  onClick={() => { setShowQualPop(p => !p); setShowSpeedPop(false); setShowSubPop(false); }}
                  className="w-9 h-9 rounded-full flex items-center justify-center text-white/60 hover:text-white hover:bg-white/8 transition-colors"
                  aria-label="Quality"
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="w-5 h-5">
                    <rect x="2" y="7" width="20" height="14" rx="2" /><path d="M16 3l-4 4-4-4"/>
                  </svg>
                </button>
                {showQualPop && (
                  <div className="absolute bottom-full right-0 mb-2 rounded-xl player-popover p-1.5 min-w-[180px] z-30 bg-neutral-900 border border-white/10">
                    <div className="px-3 pt-1 pb-1 text-[10px] font-semibold text-white/30 uppercase tracking-wider">Quality</div>
                    <button onClick={() => switchQuality(-1)}
                      className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${activeQuality === -1 ? 'text-white' : 'text-white/65 hover:bg-white/6'}`}>
                      <span>Auto</span>
                      <span className={`w-1.5 h-1.5 rounded-full bg-luna-accent ${activeQuality === -1 ? 'opacity-100' : 'opacity-0'}`} />
                    </button>
                    {qualityLevels.length > 0 ? qualityLevels.map((q, i) => (
                      <button key={i} onClick={() => switchQuality(i)}
                        className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors flex items-center justify-between gap-2 ${i === activeQuality ? 'text-white' : 'text-white/65 hover:bg-white/6'}`}>
                        <span>{q.height ? `${q.height}p` : `${Math.round(q.bitrate / 1000)}k`}</span>
                        <span className={`w-1.5 h-1.5 rounded-full bg-luna-accent flex-shrink-0 ${i === activeQuality ? 'opacity-100' : 'opacity-0'}`} />
                      </button>
                    )) : (
                      <div className="px-3 py-2 text-xs text-white/30">No quality levels</div>
                    )}
                  </div>
                )}
              </div>

              {/* Fullscreen */}
              <button
                onClick={toggleFS}
                className="w-9 h-9 rounded-full flex items-center justify-center text-white/60 hover:text-white hover:bg-white/8 transition-colors"
                aria-label={isFullscreen ? 'Exit fullscreen' : 'Fullscreen'}
              >
                {isFullscreen
                  ? <SFSymbol name="arrow.down.right.and.arrow.up.left" size={17} opacity={0.7} />
                  : <SFSymbol name="arrow.up.left.and.arrow.down.right" size={17} opacity={0.7} />}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Center pause hint (controls hidden) */}
      {!showControls && state === 'paused' && (
        <button onClick={togglePlay} className="absolute inset-0 z-10 flex items-center justify-center">
          <div className="w-16 h-16 rounded-full bg-white/20 flex items-center justify-center">
            <SFSymbol name="play.fill" size={24} />
          </div>
        </button>
      )}

      {/* Source panel — slide in from right */}
      {showSources && (
        <div className="absolute inset-0 z-40 flex justify-end">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowSources(false)} />
          <div className="relative w-80 max-w-[85vw] h-full bg-neutral-950 border-l border-white/8 overflow-y-auto">
            <div className="p-4 border-b border-white/8 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-white">Sources</h3>
              <button onClick={() => setShowSources(false)} className="p-1 rounded-full hover:bg-white/8">
                <SFSymbol name="xmark" size={14} opacity={0.5} />
              </button>
            </div>
            {(() => {
              // Sort: web-compatible audio streams first within each addon group
              const sorted = [...streams].sort((a, b) => {
                const aOk = isWebCompatAudio(a) ? 0 : 1;
                const bOk = isWebCompatAudio(b) ? 0 : 1;
                return aOk - bOk;
              });
              const grp: Record<string, StreamItem[]> = {};
              for (const s of sorted) { const k = s.addonName || 'Unknown'; (grp[k] ??= []).push(s); }
              return Object.entries(grp).map(([name, items]) => (
                <div key={name} className="border-b border-white/4 last:border-b-0">
                  <div className="px-4 pt-3 pb-1"><p className="text-[10px] font-semibold text-white/25 uppercase tracking-wider">{name}</p></div>
                  {items.map((s, i) => {
                    const isActive = s.url === currentStream.url;
                    const quality = parseQuality(s);
                    const webCompat = isWebCompatAudio(s);
                    return (
                      <button
                        key={s.url || s.infoHash || s.externalUrl || `${s.addonName}-${i}`}
                        onClick={() => switchSrc(s)}
                        className={`w-full text-left px-4 py-3 hover:bg-white/5 flex items-center gap-3 ${isActive ? 'border-l-2 border-white bg-white/4' : ''}`}
                      >
                        <span className={`text-[10px] font-bold px-2 py-0.5 rounded flex-shrink-0 ${quality.color}`}>{quality.label}</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm text-white/85 truncate">{s.title || s.name || 'Unknown'}</p>
                          <p className="text-xs text-white/35 mt-0.5">{s.addonName}</p>
                        </div>
                        {!webCompat && (
                          <span className="text-xs font-semibold text-yellow-400 bg-yellow-400/10 px-1.5 py-0.5 rounded flex-shrink-0" title="Audio codec (DTS/TrueHD/Atmos) may not play in browser — pick a WEB-DL or AAC stream instead">⚠ No audio</span>
                        )}
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
