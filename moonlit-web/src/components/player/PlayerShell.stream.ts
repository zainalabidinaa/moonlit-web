import { getStreamingServerUrl } from '@/lib/config';
import { getInitialSourceType, getPlayableStreamUrl, getStreamCompatibility, isStreamMKV } from '@/lib/player-utils';
import { probeMediabunnyPlayback } from '@/lib/mediabunny-probe';
import { buildRemuxUrl } from '@/lib/streaming-server';
import type { StreamItem } from '@/lib/types';

export type PlayerType = 'vidstack' | 'mediabunny' | 'webcodecs' | 'mpv';
export type PlaybackRouteReason =
  | 'vidstack-direct'
  | 'vidstack-proxy'
  | 'mediabunny-direct'
  | 'mediabunny-proxy'
  | 'server-remux'
  | 'server-transcode'
  | 'unsupported';

export interface MediabunnyProbeResult {
  playable: boolean;
  transport?: 'direct' | 'proxy';
  reason?: string;
}

export interface PrepareStreamOptions {
  serverUrl?: string;
  probeMediabunny?: (url: string, stream: StreamItem) => Promise<MediabunnyProbeResult>;
}

export interface PreparedStream {
  rawUrl: string;
  playbackUrl: string;
  playbackStream: StreamItem;
  playerType: PlayerType;
  shouldPreflight: boolean;
  routeReason?: PlaybackRouteReason;
  unplayableReason?: string;
}

const UNSUPPORTED_4K_MESSAGE = 'This 4K source needs transcoding or another browser-compatible source.';

function isAioStreamsPlaybackUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.hostname === 'aiostreams.elfhosted.com' && parsed.pathname.startsWith('/playback/');
  } catch {
    return false;
  }
}

function buildMediaProxyUrl(url: string): string {
  return `/api/media-proxy?url=${encodeURIComponent(url)}`;
}

function isDebridCdn(url: string): boolean {
  try {
    const hostname = new URL(url).hostname;
    return /real-debrid\.com|alldebrid\.com|bttrr\.cc|torbox\.app|premiumize\.me|debrid-link\.com|aiostreams/i.test(hostname);
  } catch {
    return false;
  }
}

function streamSearchText(stream: StreamItem): string {
  return `${stream.name ?? ''} ${stream.title ?? ''} ${stream.description ?? ''} ${stream.behaviorHints?.filename ?? ''}`.toLowerCase();
}

function isRiskyForBrowser(stream: StreamItem, rawUrl: string): boolean {
  return isAioStreamsPlaybackUrl(rawUrl) || hasHighRiskPlaybackSignals(stream);
}

function hasHighRiskPlaybackSignals(stream: StreamItem): boolean {
  const text = streamSearchText(stream);
  const size = stream.behaviorHints?.videoSize ?? 0;
  return (
    text.includes('2160') ||
    text.includes('4k') ||
    text.includes('uhd') ||
    text.includes('hevc') ||
    text.includes('h.265') ||
    text.includes('h265') ||
    text.includes('x265') ||
    text.includes('dolby vision') ||
    text.includes('[dv]') ||
    /\bdv\b/.test(text) ||
    text.includes('hdr') ||
    text.includes('truehd') ||
    text.includes('atmos') ||
    text.includes('dts') ||
    size > 8_000_000_000
  );
}

function canBenefitFromMediabunny(stream: StreamItem, rawUrl: string): boolean {
  const text = streamSearchText(stream);
  const path = (() => {
    try { return new URL(rawUrl).pathname.toLowerCase(); } catch { return rawUrl.toLowerCase().split('?')[0]; }
  })();

  return (
    isStreamMKV(stream) ||
    text.includes('.webm') ||
    text.includes(' matroska') ||
    path.endsWith('.mkv') ||
    path.endsWith('.webm')
  );
}

function makeServerPreparedStream(
  stream: StreamItem,
  rawUrl: string,
  serverUrl: string,
  tier = getStreamCompatibility(stream),
): PreparedStream {
  const effectiveTier = tier === 'direct' ? 'remux' : tier;
  return {
    rawUrl,
    playbackUrl: buildRemuxUrl(serverUrl, rawUrl, effectiveTier),
    playbackStream: {
      ...stream,
      behaviorHints: {
        ...stream.behaviorHints,
        webPlayableType: 'application/x-mpegurl',
      },
    },
    playerType: 'vidstack',
    shouldPreflight: true,
    routeReason: effectiveTier === 'remux' ? 'server-remux' : 'server-transcode',
  };
}

export function determinePlayerType(stream: StreamItem): PlayerType {
  return isStreamMKV(stream) && getStreamCompatibility(stream) === 'direct'
    ? 'mediabunny'
    : 'vidstack';
}

export function prepareStreamForPlayback(
  stream: StreamItem,
  serverUrl = getStreamingServerUrl(),
): PreparedStream | null {
  const rawUrl = getPlayableStreamUrl(stream);
  if (!rawUrl) return null;

  if (isAioStreamsPlaybackUrl(rawUrl)) {
    const isHls = rawUrl.toLowerCase().includes('/elfmagic/');
    return {
      rawUrl,
      playbackUrl: buildMediaProxyUrl(rawUrl),
      playbackStream: {
        ...stream,
        behaviorHints: {
          ...stream.behaviorHints,
          webPlayableType: isHls ? 'application/x-mpegurl' : 'video/mp4',
        },
      },
      playerType: 'vidstack',
      shouldPreflight: true,
      routeReason: 'vidstack-proxy',
    };
  }

  const playerType = determinePlayerType(stream);

  if (playerType !== 'vidstack') {
    return {
      rawUrl,
      playbackUrl: rawUrl,
      playbackStream: stream,
      playerType,
      shouldPreflight: false,
      routeReason: 'mediabunny-direct',
    };
  }

  const tier = getStreamCompatibility(stream);
  const needsServer = !!serverUrl && (
    tier !== 'direct' ||
    (rawUrl.startsWith('http:') && window.location.protocol === 'https:')
  );

  if (needsServer) {
    return makeServerPreparedStream(stream, rawUrl, serverUrl, tier);
  }

  const needsProxy = !!(stream.behaviorHints?.proxyHeaders?.request) || isDebridCdn(rawUrl);
  if (needsProxy) {
    return {
      rawUrl,
      playbackUrl: buildMediaProxyUrl(rawUrl),
      playbackStream: stream,
      playerType,
      shouldPreflight: true,
      routeReason: 'vidstack-proxy',
    };
  }

  return {
    rawUrl,
    playbackUrl: rawUrl,
    playbackStream: stream,
    playerType,
    shouldPreflight: getInitialSourceType(rawUrl, stream) !== 'application/x-mpegurl',
    routeReason: getInitialSourceType(rawUrl, stream) === 'application/x-mpegurl' ? 'vidstack-direct' : 'vidstack-direct',
  };
}

export async function prepareStreamForPlaybackAsync(
  stream: StreamItem,
  options: PrepareStreamOptions = {},
): Promise<PreparedStream | null> {
  const serverUrl = options.serverUrl ?? getStreamingServerUrl();
  const rawUrl = getPlayableStreamUrl(stream);
  if (!rawUrl) return null;

  const basePrepared = prepareStreamForPlayback(stream, serverUrl);
  if (!basePrepared) return null;

  if (isAioStreamsPlaybackUrl(rawUrl)) return basePrepared;

  if (!isRiskyForBrowser(stream, rawUrl)) return basePrepared;
  if (!canBenefitFromMediabunny(stream, rawUrl)) {
    if (getStreamCompatibility(stream) !== 'direct' && !serverUrl) {
      return {
        rawUrl,
        playbackUrl: rawUrl,
        playbackStream: stream,
        playerType: 'vidstack',
        shouldPreflight: false,
        routeReason: 'unsupported',
        unplayableReason: UNSUPPORTED_4K_MESSAGE,
      };
    }
    return basePrepared;
  }

  const probe = options.probeMediabunny ?? probeMediabunnyPlayback;
  const preferredUrl = isAioStreamsPlaybackUrl(rawUrl) ? buildMediaProxyUrl(rawUrl) : rawUrl;

  try {
    const result = await probe(preferredUrl, stream);
    if (result.playable) {
      const transport = result.transport ?? (preferredUrl.startsWith('/api/media-proxy') ? 'proxy' : 'direct');
      const playbackUrl = transport === 'proxy' ? buildMediaProxyUrl(rawUrl) : rawUrl;
      return {
        rawUrl,
        playbackUrl,
        playbackStream: stream,
        playerType: 'mediabunny',
        shouldPreflight: false,
        routeReason: transport === 'proxy' ? 'mediabunny-proxy' : 'mediabunny-direct',
      };
    }
  } catch {
    // Probe failure means Mediabunny is not a safe route for this stream.
  }

  if (!hasHighRiskPlaybackSignals(stream)) return basePrepared;

  if (serverUrl) {
    return makeServerPreparedStream(stream, rawUrl, serverUrl, 'transcode');
  }

  return {
    rawUrl,
    playbackUrl: rawUrl,
    playbackStream: stream,
    playerType: 'vidstack',
    shouldPreflight: false,
    routeReason: 'unsupported',
    unplayableReason: UNSUPPORTED_4K_MESSAGE,
  };
}
