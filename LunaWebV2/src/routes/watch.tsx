import { useEffect, useState, useRef } from 'react';
import { useParams, useSearch, useRouter } from '@tanstack/react-router';
import { useAuth } from '@/app/AuthProvider';
import Player from '@/components/Player';
import { StreamItem } from '@/lib/types';
import { SubtitleItem, fetchSubtitlesFromAll } from '@/lib/stremio';
import { getCachedStreams, getCachedStream } from '@/lib/stream-cache';
import { getPlayableStreamUrl } from '@/lib/player-utils';

export default function WatchPage() {
  const { type, id } = useParams({ strict: false }) as { type: string; id: string };
  const { url: streamUrl = '', cid: cacheId = '', title: displayTitle, logo: mediaLogo, pos: resumePosition } =
    useSearch({ strict: false }) as { url?: string; cid?: string; title?: string; logo?: string; pos?: number };
  const router = useRouter();
  const { addons } = useAuth();

  const resolvedTitle = displayTitle || decodeURIComponent(id);
  const allStreams: StreamItem[] = cacheId ? (getCachedStreams(cacheId) ?? []) : [];
  const cachedStream = cacheId && streamUrl ? getCachedStream(cacheId, streamUrl) : null;
  const fallbackStream: StreamItem = { url: streamUrl, addonName: 'Direct' };

  const [activeStream, setActiveStream] = useState<StreamItem>(cachedStream || fallbackStream);
  const [activeUrl, setActiveUrl] = useState(streamUrl);
  const [subtitles, setSubtitles] = useState<SubtitleItem[]>([]);
  const savedPosition = useRef(0);

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

  if (!streamUrl) return null;

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
