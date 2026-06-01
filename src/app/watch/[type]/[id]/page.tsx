'use client';

import { useEffect, useState, useRef } from 'react';
import { useAuth } from '../../../AuthProvider';
import { useRouter, useSearchParams } from 'next/navigation';
import Player from '@/components/Player';
import { StreamItem } from '@/lib/types';
import { getCachedStreams, getCachedStream } from '@/lib/stream-cache';

export default function WatchPage({ params }: { params: { type: string; id: string } }) {
  const resolved = params;
  const searchParams = useSearchParams();
  const { user, currentProfile, isLoading } = useAuth();
  const router = useRouter();

  const streamUrlRaw = searchParams.get('url');
  const cacheId = searchParams.get('cid');

  const streamUrl = streamUrlRaw ? decodeURIComponent(streamUrlRaw) : '';
  const allStreams: StreamItem[] = cacheId ? (getCachedStreams(cacheId) ?? []) : [];
  const cachedStream = cacheId && streamUrl ? getCachedStream(cacheId, streamUrl) : null;
  const fallbackStream: StreamItem = { url: streamUrl, addonName: 'Direct' };

  const [activeStream, setActiveStream] = useState<StreamItem>(cachedStream || fallbackStream);
  const [activeUrl, setActiveUrl] = useState(streamUrl);
  const savedPosition = useRef(0);

  // Auth guard
  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    if (!currentProfile) { router.replace('/profiles'); return; }
    if (!streamUrl) { router.back(); return; }
  }, [user, currentProfile, isLoading, streamUrl]);

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
      title={decodeURIComponent(resolved.id)}
      mediaId={resolved.id}
      mediaType={resolved.type}
      startPosition={savedPosition.current || undefined}
      onSwitchStream={handleSwitchStream}
      onBack={() => router.back()}
    />
  );
}
