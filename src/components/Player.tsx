'use client';

import { useEffect, useRef, useState, useCallback } from 'react';
import {
  MediaPlayer, MediaProvider, Track,
  PlayButton, MuteButton, FullscreenButton, SeekButton, CaptionButton,
  Controls, TimeSlider,
  Captions, Time, Gesture, useMediaState,
  isHLSProvider,
  type MediaPlayerInstance, type MediaProviderAdapter,
} from '@vidstack/react';
import { DefaultBufferingIndicator } from '@vidstack/react/player/layouts/default';
import '@vidstack/react/player/styles/base.css';
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

const BAD_AUDIO_CODECS = ['dts', 'truehd', 'atmos', 'remux', 'blu-ray', 'bluray'];
function isWebCompatAudio(s: StreamItem): boolean {
  const t = `${s.name ?? ''} ${s.title ?? ''} ${s.description ?? ''}`.toLowerCase();
  return !BAD_AUDIO_CODECS.some(k => t.includes(k));
}

export default function Player({
  streamUrl, streams, currentStream, title,
  mediaId, mediaType, startPosition, subtitles = [],
  onSwitchStream, onBack,
}: PlayerProps) {
  const playerRef = useRef<MediaPlayerInstance>(null);
  const { currentProfile } = useAuth();
  const [showSources, setShowSources] = useState(false);
  const [showSpeed, setShowSpeed] = useState(false);
  const speeds = [0.5, 0.75, 1, 1.25, 1.5, 2];

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
    <div className="fixed inset-0 bg-black z-50 luna-player">
      <MediaPlayer
        ref={playerRef}
        src={{ src: streamUrl, type: 'video/mp4' }}
        autoPlay
        className="absolute inset-0 w-full h-full"
        onProviderChange={onProviderChange}
        onEnded={onEnded}
        onCanPlay={onCanPlay}
        title={title}
        crossOrigin="anonymous"
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
        <MediaProvider className="absolute inset-0" />

        {/* Subtitle tracks from Stremio addons — Vidstack handles SRT natively */}
        {subtitles.map(sub => (
          <Track key={sub.id} src={sub.url} kind="subtitles" label={sub.name || sub.lang} language={sub.lang} />
        ))}

        {/* Subtitle overlay rendered by Vidstack */}
        <Captions className="luna-captions" />

        {/* Buffering spinner — DefaultBufferingIndicator shows when media is waiting */}
        <DefaultBufferingIndicator />

        {/* Tap / double-tap gestures */}
        <Gesture className="absolute inset-0 z-0" event="pointerup" action="toggle:paused" />
        <Gesture className="absolute left-0 top-0 h-full w-1/4 z-0" event="dblpointerup" action="seek:-15" />
        <Gesture className="absolute right-0 top-0 h-full w-1/4 z-0" event="dblpointerup" action="seek:15" />

        {/* Controls — Vidstack handles show/hide on mouse activity */}
        <Controls.Root className="luna-controls absolute inset-0 flex flex-col justify-between pointer-events-none select-none">

          {/* ── TOP BAR ── */}
          <Controls.Group className="flex items-center justify-between px-8 pt-6 pointer-events-auto"
            style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.75) 0%, transparent 100%)' }}>
            <button
              onClick={onBack}
              className="flex items-center gap-2 text-white/85 hover:text-white text-base font-medium transition-colors"
            >
              <SFSymbol name="chevron.left" size={18} opacity={0.85} />
              Back
            </button>

            <p className="text-base font-semibold text-white/75 truncate max-w-[40%]">{title}</p>

            <button
              onClick={() => setShowSources(true)}
              className="flex items-center gap-2 bg-white/10 hover:bg-white/15 border border-white/10 rounded-xl px-3.5 py-2 transition-colors"
            >
              {!isWebCompatAudio(currentStream) && (
                <span className="text-xs font-bold text-yellow-400">⚠</span>
              )}
              <span className="text-sm font-medium text-white/65">{currentStream.addonName || 'Source'}</span>
            </button>
          </Controls.Group>

          {/* ── CENTER — skip + play ── */}
          <Controls.Group className="flex items-center justify-center gap-16 pointer-events-auto">
            <SeekButton seconds={-15} className="opacity-80 hover:opacity-100 transition-opacity active:scale-95">
              <SFSymbol name="gobackward.15" size={52} />
            </SeekButton>

            <PlayButton className="flex items-center justify-center hover:scale-105 active:scale-95 transition-transform">
              <SFSymbol name="play.fill" size={72} className="media-paused:block hidden" />
              <SFSymbol name="pause.fill" size={72} className="media-paused:hidden block" />
            </PlayButton>

            <SeekButton seconds={15} className="opacity-80 hover:opacity-100 transition-opacity active:scale-95">
              <SFSymbol name="goforward.15" size={52} />
            </SeekButton>
          </Controls.Group>

          {/* ── BOTTOM SHELF ── */}
          <Controls.Group className="px-8 pb-8 pointer-events-auto"
            style={{ background: 'linear-gradient(to top, rgba(0,0,0,0.85) 0%, transparent 100%)' }}>

            <p className="text-base font-bold text-white mb-4">{title}</p>

            {/* Scrubber */}
            <TimeSlider.Root className="luna-slider group mb-3">
              <TimeSlider.Track className="relative h-1 w-full rounded-full bg-white/20 group-hover:h-[5px] transition-all duration-150">
                <TimeSlider.TrackFill className="absolute h-full rounded-full bg-white origin-left" />
                <TimeSlider.Progress className="absolute h-full rounded-full bg-white/30 origin-left" />
              </TimeSlider.Track>
              <TimeSlider.Thumb className="absolute top-1/2 -translate-y-1/2 w-4 h-4 rounded-full bg-white shadow-lg opacity-0 group-hover:opacity-100 transition-opacity -translate-x-1/2" />
              <TimeSlider.Preview className="luna-slider-preview">
                <TimeSlider.Value className="text-sm text-white bg-black/85 px-2 py-1 rounded-lg font-semibold" type="pointer" format="time" />
              </TimeSlider.Preview>
            </TimeSlider.Root>

            {/* Time + controls row */}
            <div className="flex items-center justify-between mt-1">
              <div className="flex items-center gap-1.5 text-sm font-medium text-white/50 tabular-nums">
                <Time type="current" />
                <span className="text-white/25">·</span>
                <Time type="duration" />
              </div>

              <div className="flex items-center gap-1">
                <MuteButton className="player-btn">
                  <SFSymbol name="speaker.slash.fill" size={22} opacity={0.75} className="media-muted:block hidden" />
                  <SFSymbol name="speaker.1.fill" size={22} opacity={0.75} className="media-muted:hidden media-volume-low:block hidden" />
                  <SFSymbol name="speaker.3" size={22} opacity={0.75} className="media-muted:hidden media-volume-high:block hidden" />
                </MuteButton>

                <CaptionButton className="player-btn">
                  <SFSymbol name="captions.bubble.fill" size={22} className="media-captions-on:opacity-100 opacity-50" />
                </CaptionButton>

                {/* Speed picker */}
                <div className="relative">
                  <button
                    onClick={() => setShowSpeed(p => !p)}
                    className="player-btn text-sm font-bold text-white/50 hover:text-white/90"
                  >
                    1×
                  </button>
                  {showSpeed && (
                    <div className="absolute bottom-full right-0 mb-3 bg-[#141414] border border-white/10 rounded-2xl p-1.5 min-w-[130px] z-30 shadow-xl">
                      {speeds.map(s => (
                        <button
                          key={s}
                          onClick={() => { if (playerRef.current) playerRef.current.playbackRate = s; setShowSpeed(false); }}
                          className="w-full text-left px-4 py-2.5 rounded-xl text-sm text-white/65 hover:bg-white/10 hover:text-white transition-colors font-medium"
                        >
                          {s === 1 ? 'Normal' : `${s}×`}
                        </button>
                      ))}
                    </div>
                  )}
                </div>

                <FullscreenButton className="player-btn">
                  <SFSymbol name="arrow.up.left.and.arrow.down.right" size={20} opacity={0.75} className="media-fullscreen:hidden block" />
                  <SFSymbol name="arrow.down.right.and.arrow.up.left" size={20} opacity={0.75} className="media-fullscreen:block hidden" />
                </FullscreenButton>
              </div>
            </div>
          </Controls.Group>
        </Controls.Root>
      </MediaPlayer>

      {/* ── SOURCES PANEL ── */}
      {showSources && (
        <div className="absolute inset-0 z-40 flex justify-end">
          <div className="absolute inset-0 bg-black/60" onClick={() => setShowSources(false)} />
          <div className="relative w-80 max-w-[85vw] h-full bg-neutral-950 border-l border-white/8 overflow-y-auto">
            <div className="p-4 border-b border-white/8 flex items-center justify-between sticky top-0 bg-neutral-950 z-10">
              <h3 className="text-sm font-semibold text-white">Sources</h3>
              <button onClick={() => setShowSources(false)} className="p-1 rounded-full hover:bg-white/10">
                <SFSymbol name="xmark" size={14} opacity={0.5} />
              </button>
            </div>

            {/* Only show web-compatible streams */}
            {(() => {
              const compatible = streams.filter(isWebCompatAudio);
              const grp: Record<string, StreamItem[]> = {};
              for (const s of compatible) { const k = s.addonName || 'Unknown'; (grp[k] ??= []).push(s); }

              if (compatible.length === 0) {
                return (
                  <div className="px-4 py-8 text-center">
                    <p className="text-white/40 text-sm">No web-compatible streams found</p>
                    <p className="text-white/25 text-xs mt-1">All streams have DTS/TrueHD audio</p>
                  </div>
                );
              }

              return Object.entries(grp).map(([name, items]) => (
                <div key={name} className="border-b border-white/4 last:border-b-0">
                  <div className="px-4 pt-3 pb-1">
                    <p className="text-[10px] font-semibold text-white/25 uppercase tracking-wider">{name}</p>
                  </div>
                  {items.map((s, i) => {
                    const isActive = s.url === currentStream.url;
                    const q = parseQuality(s);
                    // Parse human-readable info from description (Torrentio puts "1080p 🎥 H.264 🎵 AAC 👤 12 💾 8.3 GB")
                    const desc = s.description || '';
                    const info = desc
                      .replace(/\[.*?\]/g, '') // remove brackets
                      .replace(/[^\x00-\x7F🎥🎵👤💾⚙️\s\.]/g, '') // keep useful emoji
                      .trim() || s.title || s.name || 'Unknown';

                    return (
                      <button
                        key={s.url || s.infoHash || `${name}-${i}`}
                        onClick={() => { setShowSources(false); onSwitchStream(s); }}
                        className={`w-full text-left px-4 py-3 hover:bg-white/5 flex items-center gap-3 transition-colors ${isActive ? 'border-l-2 border-white bg-white/4' : ''}`}
                      >
                        <span className={`text-[10px] font-bold px-2 py-0.5 rounded flex-shrink-0 ${q.color}`}>{q.label}</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm text-white/85 truncate">{info}</p>
                          {s.description && (
                            <p className="text-xs text-white/30 mt-0.5 truncate">{s.description}</p>
                          )}
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
