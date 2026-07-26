import { MetaPreview } from '@/lib/types';
import { Link } from '@tanstack/react-router';
import { useState } from 'react';
import { motion } from 'framer-motion';
import { SPRING, TILE_HOVER_SCALE } from '@/lib/design/motion';

function MediaCard({ item }: { item: MetaPreview }) {
  const [imgError, setImgError] = useState(false);
  return (
    <motion.div whileHover={{ scale: TILE_HOVER_SCALE }} transition={SPRING.tileHover} className="flex-shrink-0 cursor-pointer">
      <Link to="/browse/$type/$id" params={{ type: item.type, id: item.id }} className="block">
        <div className="relative w-[172px] md:w-[196px] lg:w-[216px] aspect-[2/3] overflow-hidden rounded-ml-card bg-moonlit-elevated mb-2 border border-white/5 hover:border-white/[0.14] hover:shadow-ml-card transition-shadow duration-300">
          {item.poster && !imgError ? (
            <img src={item.poster} alt={item.name} loading="lazy" className="w-full h-full object-cover" onError={() => setImgError(true)} />
          ) : (
            <div className="w-full h-full flex items-center justify-center bg-moonlit-elevated"><span className="text-xs text-white/15 text-center px-3 line-clamp-3">{item.name}</span></div>
          )}
          {item.imdbRating && <span className="absolute top-1.5 right-1.5 rating-badge">★ {item.imdbRating}</span>}
        </div>
        <p className="text-[13px] font-medium text-white/80 truncate hover:text-white transition-colors leading-tight">{item.name}</p>
        {item.releaseInfo && <p className="text-[11px] text-white/30 mt-0.5 leading-tight">{item.releaseInfo}</p>}
      </Link>
    </motion.div>
  );
}

interface MediaRowProps { title: string; items: MetaPreview[]; titleLogo?: string; }

export function MediaRow({ title, items, titleLogo }: MediaRowProps) {
  return (
    <section className="mb-11">
      <div className="flex items-center gap-3 mb-4">
        {titleLogo ? <img src={titleLogo} alt={title} className="h-6 object-contain object-left" /> : <h2 className="section-title">{title}</h2>}
      </div>
      {items && items.length > 0 ? (
        <div className="flex gap-3 overflow-x-auto py-3 -my-3 scrollbar-hide -mx-1 px-1">
          {items.map(item => <MediaCard key={`${item.type}-${item.id}`} item={item} />)}
        </div>
      ) : <p className="text-[13px] text-white/25 italic">Loading...</p>}
    </section>
  );
}
