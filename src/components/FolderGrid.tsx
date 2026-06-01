'use client';

import Link from 'next/link';
import { HomeCatalogRow } from '@/lib/types';

function FolderCell({ row }: { row: HomeCatalogRow }) {
  const coverUrl = row.coverImage || row.items[0]?.poster || null;

  // Rows from Supabase collections have id like "folder_{uuid}"
  // Rows from addon manifests have id like "addonId_type_catalogId"
  const href = row.id.startsWith('folder_')
    ? `/collections/${row.id.slice(7)}`
    : row.items[0]
    ? `/browse/${row.items[0].type}/${row.items[0].id}`
    : null;

  if (!href) return null;

  return (
    <Link href={href} className="group relative aspect-[2/3] rounded-lg overflow-hidden bg-luna-elevated cursor-pointer block">
      {coverUrl ? (
        <img
          src={coverUrl}
          alt={row.title}
          loading="lazy"
          className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105 rounded-lg"
        />
      ) : (
        <div className="absolute inset-0 bg-gradient-to-br from-white/5 to-white/0" />
      )}
      <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/10 to-transparent" />
      <div className="absolute bottom-0 left-0 right-0 p-2">
        <p className="text-[10px] font-bold text-white leading-tight line-clamp-2">{row.title}</p>
      </div>
    </Link>
  );
}

interface FolderGridProps {
  collectionTitle: string;
  rows: HomeCatalogRow[];
}

export function FolderGrid({ collectionTitle, rows }: FolderGridProps) {
  if (rows.length === 0) return null;

  return (
    <section>
      <h2 className="text-base font-bold text-white mb-4">{collectionTitle}</h2>
      <div className="grid grid-cols-4 sm:grid-cols-6 md:grid-cols-8 gap-2">
        {rows.map((row) => (
          <FolderCell key={row.id} row={row} />
        ))}
      </div>
    </section>
  );
}
