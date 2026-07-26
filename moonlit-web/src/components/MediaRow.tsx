import { MetaPreview } from '@/lib/types';
import { Link } from '@tanstack/react-router';
import { useState } from 'react';

function MediaCard({ item }: { item: MetaPreview }) {
  const [imgError, setImgError] = useState(false);

  return (
    <div className="media-card" style={{ width: 160 }}>
      <Link
        to="/browse/$type/$id"
        params={{ type: item.type, id: item.id }}
        className="block"
      >
        <div className="relative w-full aspect-[2/3] overflow-hidden rounded bg-[#2a2a2a] mb-2 border border-white/[0.06]">
          {item.poster && !imgError ? (
            <img
              src={item.poster}
              alt={item.name}
              loading="lazy"
              className="w-full h-full object-cover"
              onError={() => setImgError(true)}
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center bg-[#2a2a2a]">
              <span className="text-xs text-white/15 text-center px-3 line-clamp-3">{item.name}</span>
            </div>
          )}

          {item.imdbRating && (
            <span className="absolute top-1.5 right-1.5 rating-badge">
              ★ {item.imdbRating}
            </span>
          )}
        </div>

        <p className="text-[13px] font-medium text-[#b3b3b3] truncate group-hover:text-white transition-colors leading-tight">
          {item.name}
        </p>
        {item.releaseInfo && (
          <p className="text-[11px] text-white/30 mt-0.5 leading-tight">{item.releaseInfo}</p>
        )}
      </Link>
    </div>
  );
}

interface MediaRowProps {
  title: string;
  items: MetaPreview[];
  viewAllHref?: string;
  titleLogo?: string;
}

export function MediaRow({ title, items, viewAllHref, titleLogo }: MediaRowProps) {
  return (
    <section className="mb-10">
      <div className="flex items-center justify-between mb-4">
        {titleLogo ? (
          <img src={titleLogo} alt={title} className="h-6 object-contain object-left" />
        ) : (
          <h2 className="text-[17px] font-bold text-white">{title}</h2>
        )}
        {viewAllHref && (
          <Link
            to={viewAllHref as any}
            className="text-[13px] text-[#b3b3b3] hover:text-white font-medium transition-colors"
          >
            Explore All
          </Link>
        )}
      </div>
      {items && items.length > 0 ? (
        <div className="flex gap-2.5 overflow-x-auto py-2 -my-2 scrollbar-hide">
          {items.map(item => (
            <MediaCard key={`${item.type}-${item.id}`} item={item} />
          ))}
        </div>
      ) : (
        <p className="text-[13px] text-white/25 italic">Loading...</p>
      )}
    </section>
  );
}
