import { MetaPreview } from '@/lib/types';
import { Link } from '@tanstack/react-router';
import { useState } from 'react';

function MediaCard({ item }: { item: MetaPreview }) {
  const [imgError, setImgError] = useState(false);

  return (
    <Link
      to="/browse/$type/$id"
      params={{ type: item.type, id: item.id }}
      className="flex-shrink-0 group cursor-pointer"
    >
      <div className="relative w-[152px] md:w-[168px] aspect-[2/3] overflow-hidden rounded-xl bg-moonlit-elevated mb-2.5">
        {item.poster && !imgError ? (
          <img
            src={item.poster}
            alt={item.name}
            loading="lazy"
            className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
            onError={() => setImgError(true)}
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center bg-moonlit-elevated">
            <span className="text-xs text-white/20 text-center px-3 line-clamp-3">{item.name}</span>
          </div>
        )}

        {/* Hover overlay */}
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/45 transition-colors duration-300 flex items-center justify-center">
          <div className="w-11 h-11 rounded-full bg-white/20 backdrop-blur-sm opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-center justify-center shadow-lg">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 ml-0.5">
              <path fillRule="evenodd" d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.348c1.295.712 1.295 2.573 0 3.285L7.28 19.991c-1.25.687-2.779-.217-2.779-1.643V5.653z" clipRule="evenodd" />
            </svg>
          </div>
        </div>

        {/* IMDb rating chip */}
        {item.imdbRating && (
          <div className="absolute top-2 right-2 bg-black/60 backdrop-blur-sm rounded-md px-1.5 py-0.5">
            <span className="text-[10px] font-bold text-yellow-400">★ {item.imdbRating}</span>
          </div>
        )}
      </div>

      <p className="text-[13px] font-semibold text-white/85 truncate group-hover:text-white transition-colors leading-tight">
        {item.name}
      </p>
      {item.releaseInfo && (
        <p className="text-[11px] text-white/35 mt-0.5 leading-tight">{item.releaseInfo}</p>
      )}
    </Link>
  );
}

interface MediaRowProps {
  title: string;
  items: MetaPreview[];
  viewAllHref?: string;
}

export function MediaRow({ title, items, viewAllHref }: MediaRowProps) {
  if (!items || items.length === 0) return null;

  return (
    <section className="mb-10">
      <div className="flex items-baseline justify-between mb-4 pr-1">
        <h2 className="text-[17px] font-bold tracking-tight text-white">{title}</h2>
        {viewAllHref && (
          <Link
            to={viewAllHref as any}
            className="text-[12px] font-semibold text-white/40 hover:text-white/70 transition-colors flex-shrink-0"
          >
            View all →
          </Link>
        )}
      </div>
      <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-hide -mx-1 px-1">
        {items.map(item => (
          <MediaCard key={`${item.type}-${item.id}`} item={item} />
        ))}
      </div>
    </section>
  );
}
