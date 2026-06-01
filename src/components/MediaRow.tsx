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
      style={{ width: '130px' }}
    >
      <div
        className="relative overflow-hidden rounded-xl bg-luna-elevated mb-2"
        style={{ height: '195px' }}
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
          <div className="w-full h-full flex items-center justify-center">
            <span className="text-xs text-white/30 text-center px-2">{item.name}</span>
          </div>
        )}
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors duration-200 flex items-center justify-center">
          <div className="w-10 h-10 rounded-full bg-white/20 backdrop-blur-sm opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
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
      <p className="text-xs font-medium text-luna-muted truncate group-hover:text-white transition-colors">
        {item.name}
      </p>
      {item.releaseInfo && (
        <p className="text-xs text-luna-muted/50 mt-0.5">{item.releaseInfo}</p>
      )}
    </Link>
  );
}

interface MediaRowProps {
  title: string;
  items: MetaPreview[];
  defaultCollapsed?: boolean;
}

export function MediaRow({ title, items, defaultCollapsed = false }: MediaRowProps) {
  const [collapsed, setCollapsed] = useState(defaultCollapsed);
  if (!items || items.length === 0) return null;

  return (
    <section className="mb-10">
      <div className="flex items-center justify-between mb-4">
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="flex items-center gap-2 cursor-pointer group"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
            className={`w-4 h-4 text-luna-muted group-hover:text-white transition-transform duration-200 ${
              collapsed ? '' : 'rotate-90'
            }`}
          >
            <path strokeLinecap="round" strokeLinejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
          </svg>
          <h2 className="text-base font-semibold text-white group-hover:text-white/90 transition-colors">{title}</h2>
        </button>
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="text-xs text-luna-muted hover:text-white transition-colors cursor-pointer"
        >
          {collapsed ? 'Show' : 'Hide'}
        </button>
      </div>
      {!collapsed && (
        <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
          {items.map(item => (
            <MediaCard key={`${item.type}-${item.id}`} item={item} />
          ))}
        </div>
      )}
    </section>
  );
}
