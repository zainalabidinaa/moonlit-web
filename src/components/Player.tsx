'use client';

import { useEffect, useRef, useState, useCallback } from 'react';
import {
  MediaPlayer,
  MediaProvider,
  Track,
  isHLSProvider,
  type MediaPlayerInstance,
  type MediaProviderAdapter,
} from '@vidstack/react';
import { DefaultVideoLayout, defaultLayoutIcons } from '@vidstack/react/player/layouts/default';
import '@vidstack/react/player/styles/default/theme.css';
import '@vidstack/react/player/styles/default/layouts/video.css';
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
  streamUrl, streams, currentStream, title, poster, backdrop,
  mediaId, mediaType, startPosition, subtitles = [], onSwitchStream, onBack,
}: PlayerProps) {
  const player = useRef<MediaPlayerInstance>(null);
  const { currentProfile } = useAuth();
  const [showSources, setShowSources] = useState(false);
  const progressInterval = useRef<ReturnType<typeof setInterval> | null>(null);

  // Configure HLS.js when provider changes — this is where we apply Real-Debrid
  // proxy headers and ensure all stream types are attempted via HLS.js first.
  const onProviderChange = useCallback((provider: MediaProviderAdapter | null) => {
    if (isHLSProvider(provider)) {
      const proxyHeaders = currentStream.behaviorHints?.proxyHeaders?.request;
      provider.config = {
        renderTextTracksNatively: false,
        startLevel: -1,
        ...(proxyHeaders && {
          xhrSetup: (xhr: XMLHttpRequest) => {
            for (const [k, v] of Object.entries(proxyHeaders)) xhr.setRequestHeader(k, v);
          },
        }),
      };
    }
  }, [currentStream]);

  // Save progress every 10 seconds
  useEffect(() => {
    if (!currentProfile) return;
    progressInterval.current = setInterval(() => {
      const p = player.current;
      if (p && p.currentTime > 0) {
        updateWatchProgress(currentProfile.id, mediaId, mediaType, p.currentTime, p.duration || 0, false);
      }
    }, 10000);
    return () => { if (progressInterval.current) clearInterval(progressInterval.current); };
  }, [currentProfile, mediaId, mediaType]);

  // Save on ended
  const onEnded = useCallback(() => {
    const p = player.current;
    if (!currentProfile || !p) return;
    updateWatchProgress(currentProfile.id, mediaId, mediaType, p.currentTime, p.duration || 0, true);
  }, [currentProfile, mediaId, mediaType]);

  // Resume from saved position
  const onCanPlay = useCallback(() => {
    if (startPosition && startPosition > 0 && player.current) {
      player.current.currentTime = startPosition;
    }
  }, [startPosition]);

  const switchSrc = (s: StreamItem) => { setShowSources(false); onSwitchStream(s); };

  // Vidstack needs an explicit src type for HLS URLs that don't contain .m3u8
  const src = { src: streamUrl, type: 'video/mp4' as const };

  return (
    <div className="fixed inset-0 bg-black z-50 luna-player">
      {/* Vidstack player */}
      <MediaPlayer
        ref={player}
        src={src}
        autoPlay
        className="absolute inset-0 w-full h-full"
        onProviderChange={onProviderChange}
        onEnded={onEnded}
        onCanPlay={onCanPlay}
        title={title}
        crossOrigin="anonymous"
      >
        <MediaProvider />

        {/* External subtitle tracks from Stremio addons */}
        {subtitles.map(sub => (
          <Track
            key={sub.id}
            src={sub.url}
            kind="subtitles"
            label={sub.name || sub.lang}
            language={sub.lang}
          />
        ))}

        {/* Default layout with monochrome theme and custom slots */}
        <DefaultVideoLayout
          icons={defaultLayoutIcons}
          slots={{
            // Source badge top-right — shows addon name + codec warning
            topControlsGroupEnd: (
              <div className="flex items-center gap-2">
                {!isWebCompatAudio(currentStream) && (
                  <span className="text-xs font-semibold text-yellow-400 bg-yellow-400/10 px-1.5 py-0.5 rounded" title="Audio codec may not play in browser">
                    ⚠ No audio
                  </span>
                )}
                <button
                  onClick={() => setShowSources(true)}
                  className="flex items-center gap-1.5 bg-white/8 hover:bg-white/12 border border-white/10 rounded-lg px-2.5 py-1.5 transition-colors"
                >
                  <span className="text-xs font-medium text-white/70">
                    {currentStream.addonName || 'Source'}
                  </span>
                  <SFSymbol name="chevron.up.chevron.down" size={10} opacity={0.4} />
                </button>
              </div>
            ),
            // Back button top-left
            topControlsGroupStart: (
              <button
                onClick={onBack}
                className="flex items-center gap-1.5 text-white/75 hover:text-white text-sm font-medium transition-colors"
              >
                <SFSymbol name="chevron.left" size={14} opacity={0.75} />
                Back
              </button>
            ),
          }}
        />
      </MediaPlayer>

      {/* Sources panel — slide in from right */}
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
              const sorted = [...streams].sort((a, b) => (isWebCompatAudio(a) ? 0 : 1) - (isWebCompatAudio(b) ? 0 : 1));
              const grp: Record<string, StreamItem[]> = {};
              for (const s of sorted) { const k = s.addonName || 'Unknown'; (grp[k] ??= []).push(s); }
              return Object.entries(grp).map(([name, items]) => (
                <div key={name} className="border-b border-white/4 last:border-b-0">
                  <div className="px-4 pt-3 pb-1">
                    <p className="text-[10px] font-semibold text-white/25 uppercase tracking-wider">{name}</p>
                  </div>
                  {items.map((s, i) => {
                    const isActive = s.url === currentStream.url;
                    const quality = parseQuality(s);
                    const webCompat = isWebCompatAudio(s);
                    return (
                      <button
                        key={s.url || s.infoHash || s.externalUrl || `${name}-${i}`}
                        onClick={() => switchSrc(s)}
                        className={`w-full text-left px-4 py-3 hover:bg-white/5 flex items-center gap-3 ${isActive ? 'border-l-2 border-white bg-white/4' : ''}`}
                      >
                        <span className={`text-[10px] font-bold px-2 py-0.5 rounded flex-shrink-0 ${quality.color}`}>{quality.label}</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm text-white/85 truncate">{s.title || s.name || 'Unknown'}</p>
                          <p className="text-xs text-white/35 mt-0.5">{s.addonName}</p>
                        </div>
                        {!webCompat && (
                          <span className="text-xs font-semibold text-yellow-400 bg-yellow-400/10 px-1.5 py-0.5 rounded flex-shrink-0">⚠ No audio</span>
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
