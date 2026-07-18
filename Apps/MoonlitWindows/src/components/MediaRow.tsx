import { ChevronRight } from 'lucide-react';
import PosterCard from './PosterCard';
import ShimmerCard from './ShimmerCard';
import type { MetaPreview } from '@/lib/types';

interface MediaRowProps {
  title: string;
  items: MetaPreview[];
  layout?: 'standard' | 'heroBanner' | 'cardStack' | 'cinematic' | 'topTen';
  onItemClick: (item: MetaPreview) => void;
  onShowMore?: () => void;
  isLoading?: boolean;
}

export default function MediaRow({
  title,
  items,
  layout = 'standard',
  onItemClick,
  onShowMore,
  isLoading,
}: MediaRowProps) {
  return (
    <div className="flex flex-col gap-[10px]">
      <div className="flex items-center gap-[10px] px-[32px]">
        <h2 className="text-[21px] font-bold text-white">{title}</h2>
        {onShowMore && (
          <button
            type="button"
            onClick={onShowMore}
            className="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center hover:bg-white/15 transition-colors"
            aria-label={`Show more ${title}`}
          >
            <ChevronRight size={13} className="text-white/80" />
          </button>
        )}
      </div>

      <div className="overflow-x-auto scrollbar-hide">
        <div className="flex gap-[18px] px-[32px] py-3 -my-3">
          {isLoading
            ? Array.from({ length: 8 }).map((_, i) => (
                <ShimmerCard key={i} />
              ))
            : items.map((item) => (
                <PosterCard
                  key={item.id}
                  item={item}
                  onClick={() => onItemClick(item)}
                />
              ))}
        </div>
      </div>
    </div>
  );
}
