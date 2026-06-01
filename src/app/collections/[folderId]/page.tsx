'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { useAuth } from '../../AuthProvider';
import { useRouter } from 'next/navigation';
import { Sidebar } from '@/components/Sidebar';
import { MetaPreview, Folder } from '@/lib/types';
import { getFolder, getSystemAddon } from '@/lib/services/api';
import Link from 'next/link';

export default function FolderDetailPage() {
  const { folderId } = useParams<{ folderId: string }>();
  const { user, isLoading } = useAuth();
  const router = useRouter();
  const [folder, setFolder] = useState<Folder | null>(null);
  const [items, setItems] = useState<MetaPreview[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    loadFolder();
  }, [folderId, isLoading]);

  async function loadFolder() {
    setLoading(true);
    setError('');
    try {
      const [folderData, addonData] = await Promise.all([
        getFolder(folderId),
        getSystemAddon()
      ]);

      if (!folderData) { setError('Folder not found.'); setLoading(false); return; }
      if (!addonData) { setError('No system addon configured.'); setLoading(false); return; }

      setFolder(folderData);

      const baseUrl = addonData.manifest_url.replace('/manifest.json', '');
      const catalogs = folderData.folder_catalogs || [];

      const results = await Promise.allSettled(
        catalogs.map(c =>
          fetch(`${baseUrl}/catalog/${c.media_type}/${c.catalog_id}.json`)
            .then(r => r.json())
            .then(d => (d.metas || []) as MetaPreview[])
        )
      );

      const merged: MetaPreview[] = [];
      const seen = new Set<string>();
      for (const result of results) {
        if (result.status === 'fulfilled') {
          for (const item of result.value) {
            if (!seen.has(item.id)) { seen.add(item.id); merged.push(item); }
          }
        }
      }
      setItems(merged);
    } catch (e) {
      setError('Failed to load content.');
    }
    setLoading(false);
  }

  if (loading) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" />
        </div>
      </Sidebar>
    );
  }

  if (error) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <p className="text-luna-muted text-sm">{error}</p>
        </div>
      </Sidebar>
    );
  }

  return (
    <Sidebar>
      <div className="px-6 pt-24 pb-12">
        <div className="mb-8">
          <h1 className="text-2xl font-bold text-white">{folder?.name}</h1>
          <p className="text-sm text-luna-muted mt-1">{items.length} titles</p>
        </div>

        <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-7 gap-3">
          {items.map(item => (
            <Link
              key={item.id}
              href={`/browse/${item.type}/${item.id}`}
              className="media-card group"
            >
              <div className="media-card-inner h-52 mb-2">
                {item.poster ? (
                  <img
                    src={item.poster}
                    alt={item.name}
                    className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                    loading="lazy"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center">
                    <span className="text-luna-muted text-xs text-center px-2">{item.name}</span>
                  </div>
                )}
                <div className="media-card-overlay group-hover:opacity-100" />
                {item.imdbRating && (
                  <span className="absolute top-2 right-2 bg-black/70 backdrop-blur-sm text-xs font-medium px-1.5 py-0.5 rounded text-white/90">
                    ★ {item.imdbRating}
                  </span>
                )}
              </div>
              <p className="text-xs text-luna-muted truncate group-hover:text-white transition-colors duration-200">
                {item.name}
              </p>
            </Link>
          ))}
        </div>

        {items.length === 0 && (
          <div className="flex flex-col items-center justify-center py-32 text-luna-muted">
            <p className="text-sm">No content in this folder.</p>
            <p className="text-xs mt-1 opacity-60">Check the catalog configuration in the admin panel.</p>
          </div>
        )}
      </div>
    </Sidebar>
  );
}
