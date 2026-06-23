import { useState, useEffect, useCallback, useRef } from 'react';
import Player from '@/components/Player';
import WebCodecsPlayer from '@/components/WebCodecsPlayer';
import MediabunnyPlayer from '@/components/MediabunnyPlayer';
import { usePlayer } from '@/app/PlayerProvider';
import { PlayerLaunch } from '@/app/PlayerProvider';
import { StreamItem } from '@/lib/types';
import { SubtitleItem, fetchStreamsFromAll, fetchSubtitlesFromAll } from '@/lib/stremio';
import { getCachedStreams, cacheStreams } from '@/lib/stream-cache';
import { getPlayableStreamUrl, sortStreamsForBrowserPlayback } from '@/lib/player-utils';
import { getLastStream, saveLastStream } from '@/lib/last-stream';
import { preflightUrl } from '@/lib/player/preflight';
import { useAuth } from '@/app/AuthProvider';
import { PlayerType, PreparedStream, prepareStreamForPlayback, prepareStreamForPlaybackAsync } from './PlayerShell.stream';

interface PlayerShellProps {
  launch: PlayerLaunch;
  onBack: () => void;
  onVideoReady: () => void;
  onError: () => void;
  profileId?: string;
}

type ShellPhase = 'resolving' | 'preflighting' | 'playing' | 'error';

export function PlayerShell({ launch, onBack, onVideoReady, onError }: PlayerShellProps) {
  const { setAllStreams, setActiveStream, registerStreamSwitchHandler } = usePlayer();
  const { addons } = useAuth();

  const [phase, setPhase] = useState<ShellPhase>(launch.streamUrl ? 'preflighting' : 'resolving');
  const [activeUrl, setActiveUrl] = useState(launch.streamUrl || '');
  const [activeStreamLocal, setActiveStreamLocal] = useState<StreamItem | null>(
    launch.streamUrl ? { url: launch.streamUrl, addonName: 'Direct' } : null
  );
  const [allStreamsLocal, setAllStreamsLocal] = useState<StreamItem[]>(launch.streams ?? []);
  const [subtitles, setSubtitles] = useState<SubtitleItem[]>(launch.subtitles ?? []);
  const [errorMsg, setErrorMsg] = useState('');
  const [resumePosition] = useState(launch.startPosition || 0);
  const [playerType, setPlayerType] = useState<PlayerType>(
    launch.streamUrl && launch.streamUrl.toLowerCase().includes('.mkv')
      ? 'mediabunny'
      : 'vidstack'
  );

  const failedUrlsRef = useRef<Set<string>>(new Set());
  const resolvedRef = useRef(false);

  const { type, id, metadata } = launch;
  const cacheKey = `${type}:${id}`;


  // Phase 1: Resolve streams if not provided
  useEffect(() => {
    if (resolvedRef.current) return;
    if (allStreamsLocal.length > 0 || activeUrl) {
      resolvedRef.current = true;
      return;
    }
    // Check cache first
    const cached = getCachedStreams(cacheKey);
    if (cached && cached.length > 0) {
      setAllStreamsLocal(cached);
      resolvedRef.current = true;
      return;
    }
    // Fetch from addons
    fetchStreamsFromAll(type, id, addons).then(fetched => {
      resolvedRef.current = true;
      if (fetched.length > 0) {
        cacheStreams(cacheKey, fetched);
        setAllStreamsLocal(fetched);
      }
    }).catch(() => {
      resolvedRef.current = true;
    });
  }, [cacheKey, addons]);

  // Fetch subtitles
  useEffect(() => {
    if (subtitles.length > 0) return;
    fetchSubtitlesFromAll(type, id, addons).then(setSubtitles).catch(() => {});
  }, [type, id, addons]);

  // Phase 2: Pick best stream + preflight
  useEffect(() => {
    if (phase !== 'resolving' && phase !== 'preflighting') return;
    if (allStreamsLocal.length === 0 && !activeUrl) return;

    async function resolveAndPreflight() {
      try {
      setPhase('preflighting');

      // If we already have a URL from launch, preflight it
      if (activeUrl && !failedUrlsRef.current.has(activeUrl)) {
        const prepared = await prepareStreamForPlaybackAsync(activeStreamLocal ?? { url: activeUrl, addonName: 'Direct' });
        if (prepared && await canPlayPreparedStream(prepared)) {
          selectPreparedStream(prepared);
          setPhase('playing');
          return;
        }
        failedUrlsRef.current.add(activeUrl);
      }

      // Pick best streams
      const lastStream = getLastStream(cacheKey);
      const sorted = sortStreamsForBrowserPlayback(allStreamsLocal);

      // Prefer last played stream
      if (lastStream) {
        const lastMatch = sorted.find(s => {
          const url = getPlayableStreamUrl(s);
          return url && url === lastStream.url;
        });
        if (lastMatch) {
          const prepared = await prepareStreamForPlaybackAsync(lastMatch);
          if (prepared && !failedUrlsRef.current.has(prepared.rawUrl)) {
            if (await canPlayPreparedStream(prepared)) {
              selectPreparedStream(prepared);
              setPhase('playing');
              return;
            }
            failedUrlsRef.current.add(prepared.rawUrl);
          }
        }
      }

      // Try sorted streams
      let lastUnplayableReason = '';
      for (const stream of sorted) {
        const prepared = await prepareStreamForPlaybackAsync(stream);
        if (!prepared || failedUrlsRef.current.has(prepared.rawUrl)) continue;
        if (prepared.unplayableReason) lastUnplayableReason = prepared.unplayableReason;
        if (await canPlayPreparedStream(prepared)) {
          selectPreparedStream(prepared);
          setPhase('playing');
          return;
        }
        failedUrlsRef.current.add(prepared.rawUrl);
      }

      // All streams failed
      setErrorMsg(lastUnplayableReason || 'No playable sources found. Check your addons in Settings.');
      setPhase('error');

      } catch (e) {
        console.error('[player] resolveAndPreflight failed:', e);
        setErrorMsg(e instanceof Error ? e.message : 'Unexpected error resolving streams.');
        setPhase('error');
      }
    }

    resolveAndPreflight();
  }, [phase, allStreamsLocal, activeUrl, cacheKey]);

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
    console.log('[player] route:', prepared.routeReason ?? prepared.playerType, '| raw:', prepared.rawUrl, '| playback:', prepared.playbackUrl);
    setActiveUrl(prepared.playbackUrl);
    setActiveStreamLocal(prepared.playbackStream);
    setPlayerType(prepared.playerType);
    saveLastStream(cacheKey, {
      url: prepared.rawUrl,
      addonName: prepared.playbackStream.addonName,
      streamTitle: prepared.playbackStream.title ?? prepared.playbackStream.name,
    });
  }

  async function selectStream(stream: StreamItem) {
    const prepared = await prepareStreamForPlaybackAsync(stream);
    if (!prepared) return;
    if (prepared.unplayableReason) {
      setErrorMsg(prepared.unplayableReason);
      setPhase('error');
      return;
    }
    selectPreparedStream(prepared);
  }

  // Register stream switch handler
  const handleStreamSwitch = useCallback((newStream: StreamItem) => {
    void selectStream(newStream);
  }, [cacheKey]);

  useEffect(() => {
    registerStreamSwitchHandler(handleStreamSwitch);
  }, [handleStreamSwitch, registerStreamSwitchHandler]);

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
        streamUrl={activeUrl}
        streams={allStreamsLocal}
        currentStream={activeStreamLocal}
        title={metadata.title}
        mediaLogo={metadata.logo}
        startPosition={resumePosition}
        onSwitchStream={handleStreamSwitch}
        onBack={onBack}
        onError={onError}
      />
    );
  }

  if (playerType === 'webcodecs') {
    return (
      <WebCodecsPlayer
        streamUrl={activeUrl}
        streams={allStreamsLocal}
        currentStream={activeStreamLocal}
        title={metadata.title}
        mediaLogo={metadata.logo}
        startPosition={resumePosition}
        subtitles={subtitles}
        onSwitchStream={handleStreamSwitch}
        onBack={onBack}
        onError={onError}
      />
    );
  }

  return (
    <Player
      streamUrl={activeUrl}
      streams={allStreamsLocal}
      currentStream={activeStreamLocal}
      title={metadata.title}
      mediaLogo={metadata.logo}
      mediaPoster={metadata.poster}
      mediaId={id}
      mediaType={type}
      startPosition={resumePosition}
      subtitles={subtitles}
      onSwitchStream={handleStreamSwitch}
      onBack={onBack}
    />
  );
}
