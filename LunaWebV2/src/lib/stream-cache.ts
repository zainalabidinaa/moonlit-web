import { StreamItem } from './types';
import { streamMatchesUrl } from './player-utils';

const cache = new Map<string, StreamItem[]>();

export function cacheStreams(key: string, streams: StreamItem[]) {
  cache.set(key, streams);
}

export function getCachedStreams(key: string): StreamItem[] | null {
  return cache.get(key) ?? null;
}

export function getCachedStream(key: string, streamUrl: string): StreamItem | null {
  const streams = cache.get(key);
  if (!streams) return null;
  return streams.find(s => streamMatchesUrl(s, streamUrl)) ?? null;
}

export function clearCache() {
  cache.clear();
}
