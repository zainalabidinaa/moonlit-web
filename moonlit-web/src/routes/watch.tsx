import { useEffect } from 'react';
import { useParams, useSearch } from '@tanstack/react-router';
import { usePlayer } from '@/app/PlayerProvider';

export default function WatchPage() {
  const { type, id } = useParams({ strict: false }) as { type: string; id: string };
  const search = useSearch({ strict: false }) as {
    url?: string; cid?: string; title?: string;
    logo?: string; poster?: string; pos?: number;
  };
  const { open } = usePlayer();

  useEffect(() => {
    open({
      type,
      id,
      streamUrl: search.url || undefined,
      metadata: {
        mediaId: id,
        mediaType: type,
        title: search.title || decodeURIComponent(id),
        logo: search.logo,
        poster: search.poster,
      },
      startPosition: search.pos,
    });
  }, []);

  return null;
}
