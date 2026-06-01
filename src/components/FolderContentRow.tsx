'use client';

import { useEffect, useState } from 'react';
import { Folder, MetaPreview } from '@/lib/types';
import { MediaRow } from './MediaRow';

interface FolderContentRowProps {
  folder: Folder;
  addonBaseUrl: string;
}

export function FolderContentRow({ folder, addonBaseUrl }: FolderContentRowProps) {
  const [items, setItems] = useState<MetaPreview[]>([]);

  useEffect(() => {
    const catalogs = folder.folder_catalogs;
    if (!catalogs || catalogs.length === 0) return;

    let cancelled = false;

    async function fetchContent() {
      const results = await Promise.allSettled(
        catalogs!.map(c =>
          fetch(`${addonBaseUrl}/catalog/${c.media_type}/${c.catalog_id}.json`)
            .then(r => r.json())
            .then(d => (d.metas || []) as any[])
        )
      );

      if (cancelled) return;

      const merged: MetaPreview[] = [];
      const seen = new Set<string>();
      for (const result of results) {
        if (result.status === 'fulfilled') {
          for (const m of result.value) {
            if (!seen.has(m.id)) {
              seen.add(m.id);
              merged.push({
                id: m.id,
                type: m.type || catalogs![0].media_type,
                name: m.name || 'Unknown',
                poster: m.poster,
                releaseInfo: m.releaseInfo,
                imdbRating: m.imdbRating,
              });
            }
          }
        }
      }
      setItems(merged);
    }

    fetchContent();
    return () => { cancelled = true; };
  }, [folder.id, addonBaseUrl]);

  if (items.length === 0) return null;
  return <MediaRow title={folder.name} items={items} />;
}
