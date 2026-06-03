import { StreamItem } from './types';

export type VidstackSourceType = 'application/x-mpegurl' | 'video/mp4';

export function getStreamUrl(stream: Pick<StreamItem, 'url' | 'externalUrl'>): string | undefined {
  return stream.url || stream.externalUrl;
}

export function getPlayableStreamUrl(stream: Pick<StreamItem, 'url'>): string | undefined {
  return stream.url;
}

function streamSearchText(stream: StreamItem): string {
  return `${stream.name ?? ''} ${stream.title ?? ''} ${stream.description ?? ''} ${stream.behaviorHints?.filename ?? ''}`.toLowerCase();
}

export function browserPlaybackScore(stream: StreamItem): number {
  const text = streamSearchText(stream);
  let score = getPlayableStreamUrl(stream) ? 100 : -1000;
  if (stream.infoHash || stream.behaviorHints?.notWebReady) score -= 1000;
  if (text.includes('.mp4') || text.includes(' h.264') || text.includes(' h264') || text.includes('x264') || text.includes(' avc')) score += 80;
  if (text.includes('aac')) score += 30;
  if (text.includes('eac3') || text.includes('dd+') || text.includes('ddp')) score += 10;
  if (text.includes('720')) score += 35;
  if (text.includes('1080')) score += 25;
  if (text.includes('2160') || text.includes('4k')) score -= 35;
  if (text.includes('.mkv')) score -= 80;
  if (text.includes('hevc') || text.includes('h.265') || text.includes('h265') || text.includes('x265')) score -= 100;
  if (text.includes('dolby vision') || text.includes(' dv ') || text.includes('hdr')) score -= 45;
  if (text.includes('truehd') || text.includes('atmos') || text.includes('dts')) score -= 60;
  const size = stream.behaviorHints?.videoSize;
  if (size && size > 8_000_000_000) score -= 25;
  return score;
}

export function sortStreamsForBrowserPlayback(streams: StreamItem[]): StreamItem[] {
  return [...streams]
    .filter(stream => getPlayableStreamUrl(stream) && !stream.infoHash && !stream.behaviorHints?.notWebReady)
    .sort((a, b) => browserPlaybackScore(b) - browserPlaybackScore(a));
}

const HLS_URL_PATTERNS = ['.m3u8', '.m3u', '/manifest', '/playlist', '/hls/', 'type=hls'];
// Debrid domains removed — they primarily serve MP4 files (not HLS manifests).
// Type is now resolved by the client-side probe in stream-resolver.ts which
// follows redirects and reads the actual content. Keeping domain guesses here
// caused Vidstack to always try HLS first for debrid links, wasting a round-trip.
const HLS_DOMAIN_PATTERNS: string[] = [];

export function getInitialSourceType(url: string, stream?: Pick<StreamItem, 'behaviorHints'>): VidstackSourceType {
  if (stream?.behaviorHints?.webPlayableType) return stream.behaviorHints.webPlayableType;

  const lower = url.toLowerCase();

  for (const p of HLS_URL_PATTERNS) {
    if (lower.includes(p)) return 'application/x-mpegurl';
  }

  if (stream?.behaviorHints?.proxyHeaders) return 'application/x-mpegurl';

  for (const d of HLS_DOMAIN_PATTERNS) {
    if (lower.includes(d)) return 'application/x-mpegurl';
  }

  return 'video/mp4';
}

export function getFallbackSourceType(currentType: VidstackSourceType): VidstackSourceType | null {
  return currentType === 'application/x-mpegurl' ? 'video/mp4' : null;
}

export function streamMatchesUrl(stream: Pick<StreamItem, 'url' | 'externalUrl'>, url: string): boolean {
  return stream.url === url || stream.externalUrl === url;
}

export function formatContinueWatchingTitle({
  mediaId,
  mediaType,
  name,
}: {
  mediaId: string;
  mediaType: string;
  name?: string;
}): string {
  const parts = mediaId.split(':');
  const baseTitle = name || parts[0] || mediaId;
  if (mediaType === 'series' && parts.length >= 3) {
    return `${baseTitle} - Episode ${parts[2]}`;
  }
  return baseTitle;
}
