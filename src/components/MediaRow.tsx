'use client';

import { MetaPreview } from '@/lib/types';
import Link from 'next/link';
import { useState } from 'react';

function MediaCard({ item }: { item: MetaPreview }) {
  const [imgError, setImgError] = useState(false);

  return (
    <Link
      href={`/browse/${item.type}/${item.id}`}
      className="flex-shrink-0 group cursor-pointer"
    >
      <div
        className="relative w-[168px] md:w-[188px] aspect-[2/3] overflow-hidden rounded-xl bg-luna-elevated mb-2"
      >
        {item.poster && !imgError ? (
          <img
            src={item.poster}
            alt={item.name}
            loading="lazy"
            className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
            onError={() => setImgError(true)}
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center bg-luna-elevated">
            <span className="text-xs text-white/20 text-center px-3 line-clamp-3">{item.name}</span>
          </div>
        )}
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors duration-300 flex items-center justify-center">
          <div className="w-11 h-11 rounded-full bg-white/20 backdrop-blur-sm opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-center justify-center">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 ml-0.5">
              <path fillRule="evenodd" d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.348c1.295.712 1.295 2.573 0 3.285L7.28 19.991c-1.25.687-2.779-.217-2.779-1.643V5.653z" clipRule="evenodd" />
            </svg>
          </div>
        </div>
        {item.imdbRating && (
          <div className="absolute top-2 right-2 bg-black/60 backdrop-blur-sm rounded px-1.5 py-0.5">
            <span className="text-xs font-medium text-yellow-400">{item.imdbRating}</span>
          </div>
        )}
      </div>
      <p className="text-sm font-semibold text-white/90 truncate group-hover:text-white transition-colors">
        {item.name}
      </p>
      {item.releaseInfo && (
        <p className="text-xs text-luna-muted/60 mt-0.5">{item.releaseInfo}</p>
      )}
    </Link>
  );
}

interface MediaRowProps {
  title: string;
  items: MetaPreview[];
}

export function MediaRow({ title, items }: MediaRowProps) {
  if (!items || items.length === 0) return null;

  return (
    <section className="mb-10">
      <h2 className="text-xl font-bold tracking-tight text-white mb-4">{title}</h2>
      <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
        {items.map(item => (
          <MediaCard key={`${item.type}-${item.id}`} item={item} />
        ))}
      </div>
    </section>
  );
}
