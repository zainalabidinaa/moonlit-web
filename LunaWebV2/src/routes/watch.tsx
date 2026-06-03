import { useEffect, useState, useRef } from 'react';
import { useParams, useSearch, useRouter } from '@tanstack/react-router';
import { useAuth } from '@/app/AuthProvider';
import Player from '@/components/Player';
import { StreamItem } from '@/lib/types';
import { SubtitleItem, fetchSubtitlesFromAll, fetchStreamsFromAll } from '@/lib/stremio';
import { getCachedStreams, getCachedStream, cacheStreams } from '@/lib/stream-cache';
import { getPlayableStreamUrl, sortStreamsForBrowserPlayback, getStreamCompatibility } from '@/lib/player-utils';
import { getStreamingServerUrl } from '@/lib/config';
import { buildRemuxUrl } from '@/lib/streaming-server';
import { ChevronLeft } from 'lucide-react';

export default function WatchPage() {
  const { type, id } = useParams({ strict: false }) as { type: string; id: string };
  const { url: initialUrl = '', cid: cacheId = '', title: displayTitle, logo: mediaLogo, pos: resumePosition } =
    useSearch({ strict: false }) as { url?: string; cid?: string; title?: string; logo?: string; pos?: number };
  const router = useRouter();
  const { addons, isLoading: authLoading } = useAuth();

  const resolvedTitle = displayTitle || decodeURIComponent(id);
  const cachedStreams = cacheId ? (getCachedStreams(cacheId) ?? []) : [];
  const cachedStream = cacheId && initialUrl ? getCachedStream(cacheId, initialUrl) : null;

  const [activeStream, setActiveStream] = useState<StreamItem>(
    cachedStream || (initialUrl ? { url: initialUrl, addonName: 'Direct' } : { url: '', addonName: '' })
  );
  const [activeUrl, setActiveUrl] = useState(initialUrl);
  const [allStreams, setAllStreams] = useState<StreamItem[]>(cachedStreams);
  const [subtitles, setSubtitles] = useState<SubtitleItem[]>([]);
  // null = still fetching, string = error message, '' = ready
  const [fetchError, setFetchError] = useState<string | null>(initialUrl ? '' : null);
  const savedPosition = useRef(0);

  // Auto-fetch streams when navigated without a URL (Play button flow)
  useEffect(() => {
    if (initialUrl || authLoading) return;
    if (addons.length === 0) return;

    let cancelled = false;
    setFetchError(null);

    (async () => {
      try {
        const fetched = await fetchStreamsFromAll(type, id, addons);
        if (cancelled) return;
        const cacheKey = `${type}:${id}`;
        cacheStreams(cacheKey, fetched);
        setAllStreams(fetched);

        const best = sortStreamsForBrowserPlayback(fetched)[0];
        if (best) {
          const rawUrl = getPlayableStreamUrl(best) ?? '';
          const serverUrl = getStreamingServerUrl();
          const tier = getStreamCompatibility(best);
          console.log(`[watch] stream tier: ${tier} | server: ${serverUrl ? 'configured' : 'none'}`);

          // Mixed content: HTTP stream on an HTTPS page → browser will block it.
          // Route through the server even for direct-tier streams in this case.
          const isMixedContent = serverUrl && rawUrl.startsWith('http:') && window.location.protocol === 'https:';

          if (serverUrl && (tier !== 'direct' || isMixedContent)) {
            // Tier 2 (remux): container wrong, codecs fine → broad codec list,
            //   server copies all streams — fast (~1s extra).
            // Tier 3 (transcode): codecs need conversion → browser-detected list,
            //   server re-encodes only what's needed.
            // Tier 1 (direct) via server: mixed-content bypass — server proxies
            //   the HTTP stream over HTTPS so the browser accepts it.
            const effectiveTier = tier === 'direct' ? 'remux' : tier;
            const remuxed = buildRemuxUrl(serverUrl, rawUrl, effectiveTier);
            console.log(`[watch] routing via server (${effectiveTier}): ${remuxed}`);
            setActiveStream({
              ...best,
              behaviorHints: { ...best.behaviorHints, webPlayableType: 'application/x-mpegurl' },
            });
            setActiveUrl(remuxed);
          } else {
            // Tier 1 (direct): browser-native — zero added latency.
            // Also used when no server is configured.
            setActiveStream(best);
            setActiveUrl(rawUrl);
          }
          setFetchError('');
        } else {
          setFetchError('No playable sources found for this title.');
        }
      } catch {
        if (!cancelled) setFetchError('Failed to load sources. Check your addons in Settings.');
      }
    })();

    return () => { cancelled = true; };
  }, [type, id, addons, initialUrl, authLoading]);

  useEffect(() => {
    if (!addons || addons.length === 0) return;
    fetchSubtitlesFromAll(type, id, addons).then(setSubtitles).catch(() => {});
  }, [type, id, addons]);

  function handleSwitchStream(newStream: StreamItem) {
    const url = getPlayableStreamUrl(newStream);
    if (!url) return;
    const video = document.querySelector('video');
    savedPosition.current = video?.currentTime || 0;
    setActiveStream(newStream);
    setActiveUrl(url);
  }

  // Still fetching streams — show loading screen
  if (fetchError === null) {
    return (
      <div className="fixed inset-0 bg-black z-50 flex flex-col items-center justify-center gap-5 select-none">
        <button
          onClick={() => router.history.back()}
          className="absolute top-5 left-6 flex items-center gap-2 text-white/60 hover:text-white transition-colors text-sm font-medium"
        >
          <ChevronLeft size={20} strokeWidth={2} />
          Back
        </button>
        <div className="flex flex-col items-center gap-5">
          {mediaLogo && <img src={mediaLogo} alt="" className="h-10 object-contain" />}
          <h2 className="text-lg font-semibold text-white text-center max-w-sm px-4">{resolvedTitle}</h2>
          <div className="w-56 h-1 rounded-full bg-white/10 overflow-hidden">
            <div className="h-full w-1/2 rounded-full bg-luna-accent animate-pulse" />
          </div>
          <p className="text-sm text-white/45">Finding best source…</p>
        </div>
      </div>
    );
  }

  // Fetch completed but no playable stream found
  if (fetchError) {
    return (
      <div className="fixed inset-0 bg-black z-50 flex flex-col items-center justify-center gap-4 select-none">
        <p className="text-white text-lg font-semibold">Nothing to play</p>
        <p className="text-white/50 text-sm text-center max-w-xs px-4">{fetchError}</p>
        <button
          onClick={() => router.history.back()}
          className="mt-2 px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white rounded-full text-sm"
        >
          Back
        </button>
      </div>
    );
  }

  return (
    <Player
      streamUrl={activeUrl}
      streams={allStreams}
      currentStream={activeStream}
      title={resolvedTitle}
      mediaLogo={mediaLogo}
      mediaId={id}
      mediaType={type}
      startPosition={savedPosition.current > 0 ? savedPosition.current : resumePosition}
      subtitles={subtitles}
      onSwitchStream={handleSwitchStream}
      onBack={() => router.history.back()}
    />
  );
}
