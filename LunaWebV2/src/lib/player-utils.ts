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

/**
 * Three-tier stream compatibility classification.
 *
 * 'direct'    — Browser can play natively (MP4/WebM, H.264/VP9, AAC/MP3).
 *               No server needed, zero latency added.
 *
 * 'remux'     — Container is wrong (MKV) but codecs are browser-compatible
 *               (H.264 video, AAC/E-AC3 audio). The remux server just
 *               repackages into HLS segments — copies both streams, no quality
 *               loss, very fast startup (~1s extra).
 *
 * 'transcode' — Codecs need conversion (HEVC→H.264, TrueHD→AAC, DTS→AAC).
 *               The server must re-encode. Slower startup, slight quality
 *               trade-off, but necessary for playback.
 */
export type StreamTier = 'direct' | 'remux' | 'transcode';

export function getStreamCompatibility(stream: StreamItem): StreamTier {
  const text = streamSearchText(stream);

  // Codec-level issues → transcode (regardless of container)
  const badVideo =
    text.includes('hevc') || text.includes('h.265') || text.includes('h265') || text.includes('x265') ||
    text.includes('dolby vision') || text.includes('[dv]') || / dv[ \].]/.test(text);
  const badAudio =
    text.includes('truehd') || text.includes('atmos') || text.includes('dts');

  if (badVideo || badAudio) return 'transcode';

  // Container-level issue only → remux (copy streams, just repackage)
  if (text.includes('.mkv')) return 'remux';

  return 'direct';
}

/** Convenience alias — true for anything that needs the remux server. */
export function isLikelyIncompatible(stream: StreamItem): boolean {
  return getStreamCompatibility(stream) !== 'direct';
}

const HLS_URL_PATTERNS = ['.m3u8', '.m3u', '/manifest', '/playlist', '/hls/', 'type=hls'];
// Debrid domains removed — they primarily serve MP4/MKV files, not HLS manifests.
// Incompatible containers (MKV/HEVC) are now routed through the remux server
// (see streaming-server.ts), so we no longer guess HLS by domain.
const HLS_DOMAIN_PATTERNS: string[] = [];

export function getInitialSourceType(url: string, stream?: Pick<StreamItem, 'behaviorHints'>): VidstackSourceType {
  if (stream?.behaviorHints?.webPlayableType) return stream.behaviorHints.webPlayableType;

  const lower = url.toLowerCase();

  for (const p of HLS_URL_PATTERNS) {
    if (lower.includes(p)) return 'application/x-mpegurl';
  }

  // proxyHeaders means auth headers are needed, not that the stream is HLS.
  // Only treat as HLS if the URL doesn't already look like a direct video file.
  // Check both the path and query params (e.g. torrent_name=File.mp4&name=...)
  const VIDEO_EXTS = ['.mp4', '.mkv', '.avi', '.webm', '.m4v', '.mov'];
  const looksLikeVideo = VIDEO_EXTS.some(ext =>
    lower.endsWith(ext) || lower.includes(ext + '?') || lower.includes(ext + '&') || lower.includes(ext + '=') || lower.includes('/' + ext.slice(1) + '/')
  );
  if (stream?.behaviorHints?.proxyHeaders && !looksLikeVideo) return 'application/x-mpegurl';

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
