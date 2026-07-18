import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { useNavigate } from '@/shell/Shell';
import { loadFolderItems } from '@/lib/collections/repository';
import PosterCard from '@/components/PosterCard';
import LoadingView from '@/components/LoadingView';
import type { MetaPreview } from '@/lib/types';

interface StreamingServiceScreenProps {
  rowId: string;
  name: string;
}

type ServiceCategory =
  | 'all' | 'movies' | 'tvShows' | 'documentaries' | 'animation'
  | 'family' | 'action' | 'comedy' | 'drama' | 'horror'
  | 'sciFi' | 'thriller' | 'romance';

const CATEGORIES: { key: ServiceCategory; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'movies', label: 'Movies' },
  { key: 'tvShows', label: 'TV Shows' },
  { key: 'documentaries', label: 'Documentaries' },
  { key: 'animation', label: 'Animation' },
  { key: 'family', label: 'Kids & Family' },
  { key: 'action', label: 'Action' },
  { key: 'comedy', label: 'Comedy' },
  { key: 'drama', label: 'Drama' },
  { key: 'horror', label: 'Horror' },
  { key: 'sciFi', label: 'Sci-Fi & Fantasy' },
  { key: 'thriller', label: 'Thriller' },
  { key: 'romance', label: 'Romance' },
];

function normalize(s: string): string {
  return s.toLowerCase().replace(/[^a-z]/g, '');
}

function serviceBrandTint(serviceName: string): string {
  const n = normalize(serviceName);
  if (n.includes('netflix')) return '#E50914';
  if (n.includes('disney')) return '#0E47A1';
  if (n.includes('hulu')) return '#1CE783';
  if (n.includes('prime') || n.includes('amazon')) return '#00A8E1';
  if (n.includes('apple')) return '#FFFFFF';
  if (n.includes('max') || n.includes('hbo')) return '#9B6CFF';
  if (n.includes('paramount')) return '#0064FF';
  if (n.includes('peacock')) return '#FF7112';
  if (n.includes('crunchyroll')) return '#F47521';
  return '#D4AF37';
}

function categoryMatches(item: MetaPreview, cat: ServiceCategory): boolean {
  switch (cat) {
    case 'all': return true;
    case 'movies': return item.type === 'movie';
    case 'tvShows': return item.type === 'series';
    case 'documentaries': return item.genres?.includes('Documentary') === true;
    case 'animation': return item.genres?.includes('Animation') === true;
    case 'family': return item.genres?.includes('Family') === true || item.genres?.includes('Kids') === true;
    case 'action': return item.genres?.includes('Action') === true;
    case 'comedy': return item.genres?.includes('Comedy') === true;
    case 'drama': return item.genres?.includes('Drama') === true;
    case 'horror': return item.genres?.includes('Horror') === true;
    case 'sciFi': return item.genres?.some(g => g === 'Sci-Fi' || g === 'Science Fiction' || g === 'Fantasy') === true;
    case 'thriller': return item.genres?.includes('Thriller') === true;
    case 'romance': return item.genres?.includes('Romance') === true;
  }
}

export function StreamingServiceScreen({ rowId, name }: StreamingServiceScreenProps) {
  const { navigateTo } = useNavigate();
  const [items, setItems] = useState<MetaPreview[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [category, setCategory] = useState<ServiceCategory>('all');

  const brandTint = serviceBrandTint(name);

  const handleMediaSelect = useCallback((item: MetaPreview) => {
    navigateTo(item.type, item.id);
  }, [navigateTo]);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const result = await loadFolderItems(rowId);
        if (!cancelled) {
          setItems(result.items || []);
          setIsLoading(false);
        }
      } catch {
        if (!cancelled) setIsLoading(false);
      }
    }
    load();
    return () => { cancelled = true; };
  }, [rowId]);

  const filteredItems = category === 'all' ? items : items.filter(i => categoryMatches(i, category));
  const movieItems = items.filter(i => i.type === 'movie');
  const showItems = items.filter(i => i.type === 'series');

  return (
    <div className="min-h-screen bg-moonlit-bg relative">
      <div className="fixed inset-0 pointer-events-none" style={{
        background: `linear-gradient(to bottom, ${brandTint}6B, ${brandTint}33 45%, transparent 100%)`,
        maskImage: 'linear-gradient(to right, black 40%, transparent 100%)',
      }} />
      <div className="relative z-10">
        {isLoading ? (
          <LoadingView />
        ) : (
          <div className="flex flex-col gap-6 pt-4 pb-12">
            <div className="h-[280px] relative flex items-end px-10 pb-2"
              style={{
                background: `linear-gradient(to bottom, ${brandTint}6B 0%, ${brandTint}33 45%, transparent 100%)`,
                maskImage: 'linear-gradient(to right, black 85%, transparent 100%)',
              }}
            >
              <div className="flex flex-col gap-3.5">
                <span className="text-[13px] font-semibold tracking-[5px] text-harbor-gold/85 uppercase">Popular on</span>
                <h1 className="text-[62px] font-semibold font-serif text-white">{name}</h1>
                <p className="text-[16px] font-medium text-white/60">
                  The most-watched movies and series on {name} right now.
                </p>
              </div>
            </div>

            <div className="overflow-x-auto scrollbar-hide border-b border-white/[0.1]">
              <div className="flex gap-5.5 px-10">
                {CATEGORIES.map(cat => (
                  <button
                    key={cat.key}
                    type="button"
                    onClick={() => setCategory(cat.key)}
                    className={`pb-3 text-[13px] font-semibold whitespace-nowrap transition-colors ${
                      category === cat.key
                        ? 'text-white border-b-2 border-white'
                        : 'text-white/50 hover:text-white/80'
                    }`}
                  >
                    {cat.label}
                  </button>
                ))}
              </div>
            </div>

            {category === 'all' ? (
              <>
                {movieItems.length > 0 && (
                  <>
                    <RankedRail title={`Top 10 Movies on ${name}`} items={movieItems.slice(0, 10)} onClick={handleMediaSelect} />
                    <PosterGrid title="More Movies" items={movieItems.slice(10, 34)} onClick={handleMediaSelect} />
                  </>
                )}
                {showItems.length > 0 && (
                  <>
                    <RankedRail title={`Top 10 Series on ${name}`} items={showItems.slice(0, 10)} onClick={handleMediaSelect} />
                    <PosterGrid title="More Series" items={showItems.slice(10, 34)} onClick={handleMediaSelect} />
                  </>
                )}
              </>
            ) : filteredItems.length === 0 ? (
              <div className="text-center py-16">
                <p className="text-[15px] font-semibold text-white/50">Nothing here yet</p>
              </div>
            ) : (
              <div className="px-10">
                <div className="grid gap-5 justify-center" style={{
                  gridTemplateColumns: 'repeat(auto-fill, minmax(154px, 1fr))',
                }}>
                  {filteredItems.map(item => (
                    <PosterCard key={item.id} item={item} onClick={() => handleMediaSelect(item)} />
                  ))}
                </div>
              </div>
            )}

            <div className="h-12" />
          </div>
        )}
      </div>
    </div>
  );
}

function RankedRail({ title, items, onClick }: { title: string; items: MetaPreview[]; onClick: (item: MetaPreview) => void }) {
  if (items.length === 0) return null;
  return (
    <div>
      <h2 className="text-[24px] font-bold text-white px-10 mb-4">{title}</h2>
      <div className="overflow-x-auto scrollbar-hide">
        <div className="flex gap-5.5 px-10 py-2.5">
          {items.map((item, index) => (
            <div key={item.id} className="relative shrink-0">
              <PosterCard item={item} onClick={() => onClick(item)} />
              <div
                className="absolute -top-2 -left-2 w-[46px] h-[46px] rounded-full flex items-center justify-center shadow-lg"
                style={{
                  background: 'radial-gradient(circle at top left, rgba(0,0,0,0.55), rgba(0,0,0,0.82))',
                  border: '1.2px solid rgba(212,175,55,0.5)',
                }}
              >
                <span className="text-[24px] font-black text-white">{index + 1}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function PosterGrid({ title, items, onClick }: { title: string; items: MetaPreview[]; onClick: (item: MetaPreview) => void }) {
  if (items.length === 0) return null;
  return (
    <div>
      <h2 className="text-[24px] font-bold text-white px-10 mb-4">{title}</h2>
      <div className="px-10">
        <div className="grid gap-5 justify-center" style={{
          gridTemplateColumns: 'repeat(auto-fill, minmax(154px, 1fr))',
        }}>
          {items.map(item => (
            <PosterCard key={item.id} item={item} onClick={() => onClick(item)} />
          ))}
        </div>
      </div>
    </div>
  );
}
