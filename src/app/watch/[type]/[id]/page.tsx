'use client';

import { useEffect, useState, useRef } from 'react';
import { useAuth } from '../../../AuthProvider';
import { useRouter, useSearchParams } from 'next/navigation';
import Player from '@/components/Player';
import { StreamItem } from '@/lib/types';
import { SubtitleItem, fetchSubtitlesFromAll } from '@/lib/stremio';
import { getCachedStreams, getCachedStream } from '@/lib/stream-cache';

export default function WatchPage({ params }: { params: { type: string; id: string } }) {
  const resolved = params;
  const searchParams = useSearchParams();
  const { user, currentProfile, isLoading, addons } = useAuth();
  const router = useRouter();

  const streamUrlRaw = searchParams.get('url');
  const cacheId = searchParams.get('cid');
  const titleRaw = searchParams.get('title');
  const posRaw = searchParams.get('pos');

  const streamUrl = streamUrlRaw ? decodeURIComponent(streamUrlRaw) : '';
  const displayTitle = titleRaw ? decodeURIComponent(titleRaw) : decodeURIComponent(resolved.id);
  const allStreams: StreamItem[] = cacheId ? (getCachedStreams(cacheId) ?? []) : [];
  const cachedStream = cacheId && streamUrl ? getCachedStream(cacheId, streamUrl) : null;
  const fallbackStream: StreamItem = { url: streamUrl, addonName: 'Direct' };

  const [activeStream, setActiveStream] = useState<StreamItem>(cachedStream || fallbackStream);
  const [activeUrl, setActiveUrl] = useState(streamUrl);
  const [subtitles, setSubtitles] = useState<SubtitleItem[]>([]);
  const savedPosition = useRef(0);
  // Resume position: from URL param (initial load) or stream-switch (savedPosition ref)
  const resumePosition = posRaw ? Number(posRaw) : undefined;

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    if (!currentProfile) { router.replace('/profiles'); return; }
    if (!streamUrl) { router.back(); return; }
  }, [user, currentProfile, isLoading, streamUrl]);

  // Fetch subtitles from all subtitle addons
  useEffect(() => {
    if (!addons || addons.length === 0) return;
    fetchSubtitlesFromAll(resolved.type, resolved.id, addons)
      .then(setSubtitles)
      .catch(() => {});
  }, [resolved.type, resolved.id, addons]);

  function handleSwitchStream(newStream: StreamItem) {
    if (!newStream.url) return;
    const video = document.querySelector('video');
    savedPosition.current = video?.currentTime || 0;
    setActiveStream(newStream);
    setActiveUrl(newStream.url);
  }

  if (!streamUrl) return null;

  return (
    <Player
      streamUrl={activeUrl}
      streams={allStreams}
      currentStream={activeStream}
      title={displayTitle}
      mediaId={resolved.id}
      mediaType={resolved.type}
      startPosition={savedPosition.current > 0 ? savedPosition.current : resumePosition}
      subtitles={subtitles}
      onSwitchStream={handleSwitchStream}
      onBack={() => router.back()}
    />
  );
}
