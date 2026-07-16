import { useState, useEffect, useCallback, useRef } from 'react';
import Player from '@/components/Player';
import WebCodecsPlayer from '@/components/WebCodecsPlayer';
import MediabunnyPlayer from '@/components/MediabunnyPlayer';
import { MpvPlayer } from '@/components/player/MpvPlayer';
import { usePlayer } from '@/app/PlayerProvider';
import { PlayerLaunch } from '@/app/PlayerProvider';
import { StreamItem } from '@/lib/types';
import { SubtitleItem, fetchStreamsFromAll, fetchSubtitlesFromAll } from '@/lib/stremio';
import { getCachedStreams, cacheStreams } from '@/lib/stream-cache';
import { getPlayableStreamUrl, getStreamUrl, sortStreamsForBrowserPlayback } from '@/lib/player-utils';
import { getLastStream, saveLastStream } from '@/lib/last-stream';
import { preflightUrl } from '@/lib/player/preflight';
import { useAuth } from '@/app/AuthProvider';
import { PlayerType, PreparedStream, prepareStreamForPlayback, prepareStreamForPlaybackAsync } from './PlayerShell.stream';
import { mpvAvailable } from '@/lib/platform/mpv';
import { sortStreamsForDesktop, pickDesktopStream, getPrefer4K } from '@/lib/platform/desktop-selection';

interface PlayerShellProps {
  launch: PlayerLaunch;
  onBack: () => void;
  onVideoReady: () => void;
  onError: () => void;
  onDesktop?: () => void;
  profileId?: string;
}

type ShellPhase = 'resolving' | 'preflighting' | 'playing' | 'error';

/** Strip the /api/stremio/vtt?url= proxy prefix for mpv (handles SRT natively). */
function rawSubUrl(proxied: string): string {
  const m = proxied.match(/^\/api\/stremio\/vtt\?url=(.*)/);
  if (m) return decodeURIComponent(m[1]);
  return proxied;
}

export function PlayerShell({ launch, onBack, onVideoReady, onError, onDesktop }: PlayerShellProps) {
  const { setAllStreams, setActiveStream, registerStreamSwitchHandler } = usePlayer();
  const { addons } = useAuth();

  const [phase, setPhase] = useState<ShellPhase>(launch.streamUrl ? 'preflighting' : 'resolving');
  const [activeUrl, setActiveUrl] = useState(launch.streamUrl || '');
  const [activeStreamLocal, setActiveStreamLocal] = useState<StreamItem | null>(
    launch.streamUrl ? { url: launch.streamUrl, addonName: 'Direct' } : null
  );
  const [allStreamsLocal, setAllStreamsLocal] = useState<StreamItem[]>(launch.streams ?? []);
  const [subtitles, setSubtitles] = useState<SubtitleItem[]>(launch.subtitles ?? []);
  const [rawSubtitles, setRawSubtitles] = useState<SubtitleItem[]>([]);
  const [errorMsg, setErrorMsg] = useState('');
  const [resumePosition] = useState(launch.startPosition || 0);
  const [playerType, setPlayerType] = useState<PlayerType>(
    launch.streamUrl && launch.streamUrl.toLowerCase().includes('.mkv')
      ? 'mediabunny'
      : 'vidstack'
  );
  const [useMpv, setUseMpv] = useState(false);

  const failedUrlsRef = useRef<Set<string>>(new Set());
  const resolvedRef = useRef(false);
  const desktopPickDone = useRef(false);

  const { type, id, metadata } = launch;
  const cacheKey = `${type}:${id}`;

  // Probe for desktop mpv support
  useEffect(() => {
    mpvAvailable().then((yes) => { if (yes) { setUseMpv(true); onDesktop?.(); } }).catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Phase 1: Resolve streams if not provided
  useEffect(() => {
    if (resolvedRef.current) return;
    if (allStreamsLocal.length > 0 || activeUrl) {
      resolvedRef.current = true;
      return;
    }
    const cached = getCachedStreams(cacheKey);
    if (cached && cached.length > 0) {
      setAllStreamsLocal(cached);
      resolvedRef.current = true;
      return;
    }
    fetchStreamsFromAll(type, id, addons).then(fetched => {
      resolvedRef.current = true;
      if (fetched.length > 0) cacheStreams(cacheKey, fetched);
      setAllStreamsLocal(fetched);
    }).catch(() => { resolvedRef.current = true; });
  }, [cacheKey, addons]);

  // Fetch subtitles + raw subtitles for mpv
  useEffect(() => {
    if (subtitles.length > 0) return;
    fetchSubtitlesFromAll(type, id, addons).then((subs) => {
      setSubtitles(subs);
      // For mpv: strip proxy prefix (mpv handles SRT/VTT natively)
      setRawSubtitles(subs.map((s) => ({ ...s, url: rawSubUrl(s.url) })));
    }).catch(() => {});
  }, [type, id, addons]);

  // Phase 2: Desktop stream pick (mpv — no preflight, use raw URLs)
  const pickStreamDesktop = useCallback(() => {
    if (desktopPickDone.current) return;
    if (!useMpv || allStreamsLocal.length === 0) return;
    const lastStream = getLastStream(cacheKey);
    const sorted = sortStreamsForDesktop(allStreamsLocal, getPrefer4K());
    const picked = pickDesktopStream(sorted, lastStream?.url ?? null);
    if (!picked) return;
    const rawUrl = getStreamUrl(picked);
    if (!rawUrl) return;
    desktopPickDone.current = true;
    setActiveUrl(rawUrl);
    setActiveStreamLocal(picked);
    setPlayerType('mpv');
    setAllStreams(allStreamsLocal);
    setActiveStream(picked);
    setPhase('playing');
    saveLastStream(cacheKey, { url: rawUrl, addonName: picked.addonName, streamTitle: picked.title ?? picked.name });
  }, [useMpv, allStreamsLocal, cacheKey, setAllStreams, setActiveStream]);

  useEffect(() => { pickStreamDesktop(); }, [pickStreamDesktop]);

  // Phase 2: Web pick best stream + preflight (only when NOT on mpv path)
  useEffect(() => {
    if (useMpv) return; // desktop handled above
    if (phase !== 'resolving' && phase !== 'preflighting') return;
    if (allStreamsLocal.length === 0 && !activeUrl) return;

    async function resolveAndPreflight() {
      try {
      setPhase('preflighting');
      if (activeUrl && !failedUrlsRef.current.has(activeUrl)) {
        const prepared = await prepareStreamForPlaybackAsync(activeStreamLocal ?? { url: activeUrl, addonName: 'Direct' });
        if (prepared && await canPlayPreparedStream(prepared)) {
          selectPreparedStream(prepared); setPhase('playing'); return;
        }
        failedUrlsRef.current.add(activeUrl);
      }
      const lastStream = getLastStream(cacheKey);
      const sorted = sortStreamsForBrowserPlayback(allStreamsLocal);
      if (lastStream) {
        const lastMatch = sorted.find(s => { const url = getPlayableStreamUrl(s); return url && url === lastStream.url; });
        if (lastMatch) {
          const prepared = await prepareStreamForPlaybackAsync(lastMatch);
          if (prepared && !failedUrlsRef.current.has(prepared.rawUrl)) {
            if (await canPlayPreparedStream(prepared)) {
              selectPreparedStream(prepared); setPhase('playing'); return;
            }
            failedUrlsRef.current.add(prepared.rawUrl);
          }
        }
      }
      let lastUnplayableReason = '';
      for (const stream of sorted) {
        const prepared = await prepareStreamForPlaybackAsync(stream);
        if (!prepared || failedUrlsRef.current.has(prepared.rawUrl)) continue;
        if (prepared.unplayableReason) lastUnplayableReason = prepared.unplayableReason;
        if (await canPlayPreparedStream(prepared)) {
          selectPreparedStream(prepared); setPhase('playing'); return;
        }
        failedUrlsRef.current.add(prepared.rawUrl);
      }
      setErrorMsg(lastUnplayableReason || 'No playable sources found. Check your addons in Settings.');
      setPhase('error');
      } catch (e) {
        console.error('[player] resolveAndPreflight failed:', e);
        setErrorMsg(e instanceof Error ? e.message : 'Unexpected error resolving streams.');
        setPhase('error');
      }
    }
    resolveAndPreflight();
  }, [phase, allStreamsLocal, activeUrl, cacheKey, useMpv]);

  async function canPlayPreparedStream(prepared: PreparedStream): Promise<boolean> {
    if (prepared.routeReason === 'unsupported') return false;
    if (!prepared.shouldPreflight) return true;
    if (failedUrlsRef.current.has(prepared.playbackUrl)) return false;
    const result = await preflightUrl(prepared.playbackUrl);
    if (result.reachable) return true;
    failedUrlsRef.current.add(prepared.playbackUrl);
    return false;
  }

  function selectPreparedStream(prepared: PreparedStream) {
    setActiveUrl(prepared.playbackUrl);
    setActiveStreamLocal(prepared.playbackStream);
    setPlayerType(prepared.playerType);
    saveLastStream(cacheKey, { url: prepared.rawUrl, addonName: prepared.playbackStream.addonName, streamTitle: prepared.playbackStream.title ?? prepared.playbackStream.name });
  }

  // Register stream switch handler
  const handleStreamSwitch = useCallback((newStream: StreamItem) => {
    if (useMpv) {
      // Desktop: just restart with new raw URL
      const rawUrl = getStreamUrl(newStream);
      if (!rawUrl) return;
      const prevPos = activeUrl ? undefined : resumePosition;
      setActiveUrl(rawUrl);
      setActiveStreamLocal(newStream);
      setPlayerType('mpv');
      setPhase('playing');
      setAllStreams(allStreamsLocal);
      setActiveStream(newStream);
      saveLastStream(cacheKey, { url: rawUrl, addonName: newStream.addonName, streamTitle: newStream.title ?? newStream.name });
      return;
    }
    void (async () => {
      const prepared = await prepareStreamForPlaybackAsync(newStream);
      if (!prepared) return;
      if (prepared.unplayableReason) { setErrorMsg(prepared.unplayableReason); setPhase('error'); return; }
      selectPreparedStream(prepared);
    })();
  }, [useMpv, cacheKey, resumePosition, allStreamsLocal, activeUrl, setAllStreams, setActiveStream]);

  useEffect(() => { registerStreamSwitchHandler(handleStreamSwitch); }, [handleStreamSwitch, registerStreamSwitchHandler]);

  // Sync to PlayerProvider
  useEffect(() => {
    setAllStreams(allStreamsLocal);
    setActiveStream(activeStreamLocal!);
  }, [allStreamsLocal, activeStreamLocal, setAllStreams, setActiveStream]);

  // Video ready
  useEffect(() => {
    if (phase === 'playing') onVideoReady();
  }, [phase, onVideoReady]);

  // Error
  useEffect(() => {
    if (phase === 'error') onError();
  }, [phase, onError]);

  if (phase === 'error') {
    return (
      <div className="absolute inset-0 z-50 flex flex-col items-center justify-center gap-4 bg-black">
        <p className="text-white text-lg font-semibold">Nothing to play</p>
        <p className="text-white/50 text-sm text-center max-w-xs px-4">{errorMsg}</p>
        <button onClick={onBack} className="mt-2 px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full text-sm cursor-pointer">
          Back
        </button>
      </div>
    );
  }

  if (phase !== 'playing' || !activeUrl || !activeStreamLocal) return null;

  if (playerType === 'mediabunny') {
    return (
      <MediabunnyPlayer
        streamUrl={activeUrl} streams={allStreamsLocal} currentStream={activeStreamLocal}
        title={metadata.title} mediaLogo={metadata.logo} startPosition={resumePosition}
        onSwitchStream={handleStreamSwitch} onBack={onBack} onError={onError}
      />
    );
  }

  if (playerType === 'webcodecs') {
    return (
      <WebCodecsPlayer
        streamUrl={activeUrl} streams={allStreamsLocal} currentStream={activeStreamLocal}
        title={metadata.title} mediaLogo={metadata.logo} startPosition={resumePosition}
        subtitles={subtitles} onSwitchStream={handleStreamSwitch} onBack={onBack} onError={onError}
      />
    );
  }

  if (playerType === 'mpv') {
    return (
      <MpvPlayer
        streamUrl={activeUrl} streams={allStreamsLocal} currentStream={activeStreamLocal}
        title={metadata.title} mediaLogo={metadata.logo} mediaId={id} mediaType={type}
        startPosition={resumePosition} subtitles={rawSubtitles}
        onSwitchStream={handleStreamSwitch}
        onOpenSources={() => {
          // SourcesPanel is integrated via a callback — for now, trigger switchStream externally
          // In future, this opens the existing SourcesPanel sheet
        }}
        onBack={onBack}
        onReady={onVideoReady}
      />
    );
  }

  return (
    <Player
      streamUrl={activeUrl} streams={allStreamsLocal} currentStream={activeStreamLocal}
      title={metadata.title} mediaLogo={metadata.logo} mediaPoster={metadata.poster}
      mediaId={id} mediaType={type} startPosition={resumePosition} subtitles={subtitles}
      onSwitchStream={handleStreamSwitch} onBack={onBack}
    />
  );
}
