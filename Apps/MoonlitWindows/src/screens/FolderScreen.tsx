import { useState, useEffect, useCallback, useRef } from 'react';
import { motion } from 'framer-motion';
import { Folder } from 'lucide-react';
import { useNavigate } from '@/shell/Shell';
import { loadFolderItems } from '@/lib/collections/repository';
import { fetchCatalog } from '@/lib/stremio';
import { useAmbientColors } from '@/lib/design/artwork-color';
import PosterCard from '@/components/PosterCard';
import MediaCard from '@/components/MediaCard';
import StrokeSpinner from '@/components/StrokeSpinner';
import LoadingView from '@/components/LoadingView';
import type { MetaPreview, CatalogRow } from '@/lib/types';

interface FolderScreenProps {
  rowId: string;
  folderId: string;
  name: string;
}

function isLandscape(items: MetaPreview[]): boolean {
  const folders = items.filter(i => i.id.startsWith('folder_'));
  const media = items.filter(i => !i.id.startsWith('folder_'));
  if (folders.length === 0 || media.length > 0) return false;
  const landscape = folders.filter(f => f.posterShape === 'landscape' || f.banner).length;
  return landscape >= Math.max(1, folders.length / 2);
}

export function FolderScreen({ rowId, folderId, name }: FolderScreenProps) {
  const { navigateTo, navigateToFolder } = useNavigate();
  const [items, setItems] = useState<MetaPreview[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [heroUrl, setHeroUrl] = useState<string | undefined>();
  const [error, setError] = useState<string | null>(null);
  const sentinelRef = useRef<HTMLDivElement>(null);

  const ambientColors = useAmbientColors(heroUrl);

  const landscapeLayout = isLandscape(items);
  const displayRow: CatalogRow = {
    id: folderId || rowId,
    title: name,
    items,
    tileShape: landscapeLayout ? 'landscape' : 'poster',
  };

  const handleItemClick = useCallback((item: MetaPreview) => {
    if (item.id.startsWith('folder_')) {
      navigateToFolder(item.id, item.id, item.name);
    } else {
      navigateTo(item.type, item.id);
    }
  }, [navigateTo, navigateToFolder]);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      setIsLoading(true);
      setError(null);
      try {
        const result = await loadFolderItems(folderId || rowId);
        if (!cancelled) {
          setItems(result.items || []);
          if (result.items?.[0]?.poster) setHeroUrl(result.items[0].poster);
          if (result.items?.[0]?.backdrop) setHeroUrl(result.items[0].backdrop);
          setIsLoading(false);
        }
      } catch (e: any) {
        if (!cancelled) {
          setError(e.message || 'Failed to load folder');
          setIsLoading(false);
        }
      }
    }
    load();
    return () => { cancelled = true; };
  }, [folderId, rowId]);

  useEffect(() => {
    const el = sentinelRef.current;
    if (!el || isLoadingMore) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setIsLoadingMore(true);
          setTimeout(() => setIsLoadingMore(false), 300);
        }
      },
      { threshold: 0.1 }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [items.length]);

  const ambientStyle = ambientColors
    ? {
        background: `radial-gradient(ellipse 60% 50% at 50% 0%, ${ambientColors[0]}33, ${ambientColors[1]}11, transparent 70%)`,
      }
    : {};

  return (
    <div className="min-h-screen bg-moonlit-bg relative">
      <div className="fixed inset-0 pointer-events-none transition-colors duration-700" style={ambientStyle} />
      <div className="relative z-10">
        {isLoading ? (
          <LoadingView />
        ) : (
          <>
            {heroUrl && (
              <div className="relative h-[400px] overflow-hidden">
                <img src={heroUrl} alt="" className="w-full h-full object-cover" />
                <div className="absolute inset-0 bg-gradient-to-b from-transparent via-moonlit-bg/35 via-45% via-moonlit-bg/85 to-moonlit-bg" />
                <div className="absolute bottom-0 left-0 px-7 pb-5">
                  <h1 className="text-[36px] font-black text-white">{name}</h1>
                </div>
              </div>
            )}

            <div className="px-7 pt-6 pb-12">
              {error ? (
                <div className="flex flex-col items-center gap-3 py-20">
                  <Folder size={38} className="text-white/20" />
                  <p className="text-[15px] font-semibold text-white/60">{error}</p>
                </div>
              ) : items.length === 0 && !isLoading ? (
                <div className="flex flex-col items-center gap-3 py-20">
                  <Folder size={38} className="text-white/20" />
                  <p className="text-[15px] font-semibold text-white/60">Nothing here yet</p>
                </div>
              ) : (
                <div
                  className="grid gap-[18px]"
                  style={{
                    gridTemplateColumns: landscapeLayout
                      ? 'repeat(auto-fill, minmax(248px, 1fr))'
                      : 'repeat(auto-fill, minmax(154px, 1fr))',
                  }}
                >
                  {items.map(item => (
                    landscapeLayout ? (
                      <MediaCard
                        key={item.id}
                        item={item}
                        row={displayRow}
                        onClick={() => handleItemClick(item)}
                      />
                    ) : (
                      <PosterCard
                        key={item.id}
                        item={item}
                        onClick={() => handleItemClick(item)}
                      />
                    )
                  ))}
                </div>
              )}

              <div ref={sentinelRef} className="flex justify-center py-7">
                {isLoadingMore && <StrokeSpinner size={17} />}
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
