import { StreamItem } from './types';

export type VidstackSourceType = 'application/x-mpegurl' | 'video/mp4';

export function getStreamUrl(stream: Pick<StreamItem, 'url' | 'externalUrl'>): string | undefined {
  return stream.url || stream.externalUrl;
}

export function getPlayableStreamUrl(stream: Pick<StreamItem, 'url'>): string | undefined {
  return stream.url;
}

export function getInitialSourceType(_url: string): VidstackSourceType {
  return 'application/x-mpegurl';
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
