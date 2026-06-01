'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '../AuthProvider';
import { useRouter } from 'next/navigation';
import { Sidebar } from '@/components/Sidebar';
import { LibraryItem } from '@/lib/types';
import { getLibrary, toggleLibrary as toggleLib } from '@/lib/services/api';
import Link from 'next/link';

export default function LibraryPage() {
  const { currentProfile, user, isLoading } = useAuth();
  const router = useRouter();
  const [items, setItems] = useState<LibraryItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    if (!currentProfile) { router.replace('/profiles'); return; }
    loadLibrary();
  }, [currentProfile]);

  async function loadLibrary() {
    if (!currentProfile) return;
    setLoading(true);
    const lib = await getLibrary(currentProfile.id);
    setItems(lib);
    setLoading(false);
  }

  async function handleRemove(mediaId: string, mediaType: string) {
    if (!currentProfile) return;
    await toggleLib(currentProfile.id, mediaId, mediaType);
    loadLibrary();
  }

  return (
    <Sidebar>
      <div className="px-6 pt-24 pb-12">
        <div className="flex items-baseline gap-3 mb-6">
          <h1 className="text-xl font-semibold">Library</h1>
          {!loading && items.length > 0 && (
            <span className="text-sm text-white/35">{items.length} saved</span>
          )}
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" />
          </div>
        ) : items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-32 text-white/35">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-10 h-10 mb-4 opacity-40">
              <path fillRule="evenodd" d="M1.5 5.625c0-1.036.84-1.875 1.875-1.875h17.25c1.035 0 1.875.84 1.875 1.875v12.75c0 1.035-.84 1.875-1.875 1.875H3.375A1.875 1.875 0 011.5 18.375V5.625z" clipRule="evenodd" />
            </svg>
            <p className="text-sm text-white/50">Your library is empty</p>
            <p className="text-xs mt-1 text-white/25">Save titles with the watchlist button</p>
          </div>
        ) : (
          <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3">
            {items.map(item => (
              <Link key={item.id} href={`/browse/${item.media_type}/${item.media_id}`} className="group cursor-pointer">
                <div className="relative aspect-[2/3] rounded-lg overflow-hidden bg-luna-elevated mb-2">
                  {item.poster
                    ? <img src={item.poster} alt={item.name || item.media_id} className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105" loading="lazy" />
                    : <div className="absolute inset-0 flex items-center justify-center text-white/15 text-xs text-center px-2">{item.name || item.media_id}</div>}
                  {/* Remove button — only on hover */}
                  <button
                    onClick={e => { e.preventDefault(); handleRemove(item.media_id, item.media_type); }}
                    className="absolute top-2 right-2 w-7 h-7 rounded-full bg-black/60 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity hover:bg-black/80 z-10"
                    aria-label="Remove from library"
                  >
                    <svg className="w-3.5 h-3.5 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M18 6L6 18M6 6l12 12"/></svg>
                  </button>
                </div>
                <p className="text-xs font-medium text-white/80 truncate">{item.name || item.media_id}</p>
                <p className="text-[10px] text-white/35 mt-0.5">{item.media_type === 'series' ? 'Series' : 'Movie'}</p>
              </Link>
            ))}
          </div>
        )}
      </div>
    </Sidebar>
  );
}
