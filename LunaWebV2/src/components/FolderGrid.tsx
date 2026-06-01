import { Link } from '@tanstack/react-router';
import { HomeCatalogRow } from '@/lib/types';

function CellInner({ coverUrl, title }: { coverUrl: string | null; title: string }) {
  return (
    <>
      {coverUrl ? (
        <img
          src={coverUrl}
          alt={title}
          loading="lazy"
          className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105 rounded-lg"
        />
      ) : (
        <div className="absolute inset-0 bg-gradient-to-br from-white/5 to-white/0" />
      )}
      <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/10 to-transparent" />
      <div className="absolute bottom-0 left-0 right-0 p-2">
        <p className="text-[10px] font-bold text-white leading-tight line-clamp-2">{title}</p>
      </div>
    </>
  );
}

const cellClass = "group relative aspect-[2/3] rounded-lg overflow-hidden bg-luna-elevated cursor-pointer block";

function FolderCell({ row }: { row: HomeCatalogRow }) {
  const coverUrl = row.coverImage || row.items[0]?.poster || null;

  if (row.id.startsWith('folder_')) {
    return (
      <Link
        to="/collections/$folderId"
        params={{ folderId: row.id.slice(7) }}
        className={cellClass}
      >
        <CellInner coverUrl={coverUrl} title={row.title} />
      </Link>
    );
  }

  const firstItem = row.items[0];
  if (!firstItem) return null;

  return (
    <Link
      to="/browse/$type/$id"
      params={{ type: firstItem.type, id: firstItem.id }}
      className={cellClass}
    >
      <CellInner coverUrl={coverUrl} title={row.title} />
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
