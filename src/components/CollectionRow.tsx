import { Collection } from '@/lib/types';
import { FolderTile } from './FolderTile';

interface CollectionRowProps {
  collection: Collection;
}

export function CollectionRow({ collection }: CollectionRowProps) {
  if (!collection.folders || collection.folders.length === 0) return null;

  const showGlow = collection.focus_glow_enabled ?? true;

  return (
    <section className="mb-10">
      <h2 className="text-xl font-bold tracking-tight text-white mb-4">{collection.name}</h2>
      <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-hide">
        {[...collection.folders]
          .sort((a, b) => a.sort_order - b.sort_order)
          .map(folder => (
            <FolderTile key={folder.id} folder={folder} showGlow={showGlow} />
          ))}
      </div>
    </section>
  );
}
