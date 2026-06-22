import { useState, useEffect, useCallback, useRef } from 'react';
import Player from '@/components/Player';
import WebCodecsPlayer from '@/components/WebCodecsPlayer';
import MediabunnyPlayer from '@/components/MediabunnyPlayer';
import { usePlayer } from '@/app/PlayerProvider';
import { PlayerLaunch } from '@/app/PlayerProvider';
import { StreamItem } from '@/lib/types';
import { SubtitleItem, fetchStreamsFromAll, fetchSubtitlesFromAll } from '@/lib/stremio';
import { getCachedStreams, cacheStreams } from '@/lib/stream-cache';
import { getPlayableStreamUrl, sortStreamsForBrowserPlayback, getStreamCompatibility, isStreamMKV } from '@/lib/player-utils';
import { getLastStream, saveLastStream } from '@/lib/last-stream';
import { getStreamingServerUrl } from '@/lib/config';
import { buildRemuxUrl } from '@/lib/streaming-server';
import { preflightUrl, findReachableUrl } from '@/lib/player/preflight';
import { useAuth } from '@/app/AuthProvider';

interface PlayerShellProps {
  launch: PlayerLaunch;
  onBack: () => void;
  onVideoReady: () => void;
  onError: () => void;
  profileId?: string;
}

type ShellPhase = 'resolving' | 'preflighting' | 'playing' | 'error';
type PlayerType = 'vidstack' | 'mediabunny' | 'webcodecs';

export function PlayerShell({ launch, onBack, onVideoReady, onError, profileId }: PlayerShellProps) {
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
  const [resumePosition, setResumePosition] = useState(launch.startPosition || 0);
  const [playerType, setPlayerType] = useState<PlayerType>(
    launch.streamUrl && launch.streamUrl.toLowerCase().includes('.mkv')
      ? 'mediabunny'
      : 'vidstack'
  );

  const failedUrlsRef = useRef<Set<string>>(new Set());
  const resolvedRef = useRef(false);

  const { type, id, metadata } = launch;
  const cacheKey = `${type}:${id}`;


  function resolveUrlForStream(stream: StreamItem): { url: string; stream: StreamItem } {
    const rawUrl = getPlayableStreamUrl(stream)!;
    const serverUrl = getStreamingServerUrl();
    const tier = getStreamCompatibility(stream);
    const needsServer = serverUrl && (
      tier !== 'direct' ||
      (rawUrl.startsWith('http:') && window.location.protocol === 'https:')
    );
    if (needsServer) {
      const effectiveTier = tier === 'direct' ? 'remux' : tier;
      return {
        url: buildRemuxUrl(serverUrl, rawUrl, effectiveTier),
        stream: { ...stream, behaviorHints: { ...stream.behaviorHints, webPlayableType: 'application/x-mpegurl' } },
      };
    }
    return { url: rawUrl, stream };
  }

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
      if (fetched.length > 0) {
        cacheStreams(cacheKey, fetched);
        setAllStreamsLocal(fetched);
        resolvedRef.current = true;
      }
    }).catch(() => {});
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
      setPhase('preflighting');

      // If we already have a URL from launch, preflight it
      if (activeUrl && !failedUrlsRef.current.has(activeUrl)) {
        const result = await preflightUrl(activeUrl);
        if (result.reachable) {
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
          const url = getPlayableStreamUrl(lastMatch);
          if (url && !failedUrlsRef.current.has(url)) {
            const result = await preflightUrl(url);
            if (result.reachable) {
              selectStream(lastMatch);
              setPhase('playing');
              return;
            }
            failedUrlsRef.current.add(url);
          }
        }
      }

      // Try sorted streams
      for (const stream of sorted) {
        const rawUrl = getPlayableStreamUrl(stream);
        if (!rawUrl || failedUrlsRef.current.has(rawUrl)) continue;
        const result = await preflightUrl(rawUrl);
        if (result.reachable) {
          selectStream(stream);
          setPhase('playing');
          return;
        }
        failedUrlsRef.current.add(rawUrl);
      }

      // All streams failed
      setErrorMsg('No playable sources found. Check your addons in Settings.');
      setPhase('error');
    }

    resolveAndPreflight();
  }, [phase, allStreamsLocal, activeUrl, cacheKey]);

  function selectStream(stream: StreamItem) {
    const rawUrl = getPlayableStreamUrl(stream)!;
    const newPlayerType = determinePlayerType(stream);

    if (newPlayerType === 'vidstack') {
      const resolved = resolveUrlForStream(stream);
      setActiveUrl(resolved.url);
      setActiveStreamLocal(resolved.stream);
    } else {
      // Mediabunny and WebCodecs handle MKV client-side — raw URL
      setActiveUrl(rawUrl);
      setActiveStreamLocal(stream);
    }

    setPlayerType(newPlayerType);
    saveLastStream(cacheKey, { url: rawUrl, addonName: stream.addonName, streamTitle: stream.title ?? stream.name });
  }

  // Register stream switch handler
  const handleStreamSwitch = useCallback((newStream: StreamItem) => {
    selectStream(newStream);
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
