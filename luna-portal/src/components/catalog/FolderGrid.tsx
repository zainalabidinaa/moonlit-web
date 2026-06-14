import type { Collection, Folder } from '../../types';

interface Props {
  collection: Collection;
  folders: Folder[];
  onSelectFolder: (f: Folder) => void;
  onAddFolder: () => void;
  onDragStart: (i: number) => void;
  onDrop: (i: number) => void;
}

export function FolderGrid({ collection, folders, onSelectFolder, onAddFolder, onDragStart, onDrop }: Props) {
  return (
    <div>
      {/* Collection backdrop */}
      <div className="relative mb-6 h-[170px] overflow-hidden rounded-2xl border border-border">
        {collection.backdrop_image ? (
          <img src={collection.backdrop_image} alt="" className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full w-full items-center justify-center bg-surface-2 font-mono text-xs text-faint">
            no backdrop_image set
          </div>
        )}
        <div className="absolute inset-0 flex items-end p-5" style={{ background: 'linear-gradient(0deg,rgba(13,6,4,.92),transparent 60%)' }}>
          <div>
            <p className="font-mono text-[10px] uppercase tracking-widest text-accent">Collection backdrop · backdrop_image</p>
            <h2 className="font-display text-3xl font-extrabold uppercase">{collection.name}</h2>
          </div>
        </div>
      </div>

      <div className="mb-3.5 flex items-center justify-between">
        <h3 className="font-display text-[15px] font-extrabold">
          Folders <span className="font-mono text-xs font-normal text-faint">· click to edit artwork</span>
        </h3>
      </div>

      <div className="grid gap-3.5 [grid-template-columns:repeat(auto-fill,minmax(170px,1fr))]">
        {folders.map((f, i) => (
          <button
            key={f.id}
            draggable
            onDragStart={() => onDragStart(i)}
            onDragOver={(e) => e.preventDefault()}
            onDrop={() => onDrop(i)}
            onClick={() => onSelectFolder(f)}
            className="group overflow-hidden rounded-2xl border border-border bg-bg2 text-left transition-all hover:-translate-y-1 hover:border-accent"
          >
            <div className="relative flex h-[130px] items-center justify-center overflow-hidden">
              {f.cover_image ? (
                <img src={f.cover_image} alt="" className="absolute inset-0 h-full w-full object-cover" />
              ) : (
                <div className="absolute inset-0 bg-surface-2" />
              )}
              <div className="absolute inset-0" style={{ background: 'linear-gradient(0deg,rgba(13,6,4,.7),transparent 50%)' }} />
              {f.title_logo && (
                <img src={f.title_logo} alt="" className="relative z-[2] max-h-[54px] max-w-[78%] object-contain drop-shadow-lg" />
              )}
              <div className="absolute left-2 top-2 z-[3] flex gap-1.5">
                {f.focus_gif && <Badge tone="magenta">GIF</Badge>}
                {f.hero_video_url && <Badge tone="cyan">VIDEO</Badge>}
                {f.title_logo && <Badge>LOGO</Badge>}
              </div>
            </div>
            <div className="flex items-center justify-between p-3">
              <span className="truncate text-[13px] font-semibold text-text">{f.name}</span>
              <span className="font-mono text-[10px] text-faint">{f.tile_shape?.slice(0, 4) || '—'}</span>
            </div>
          </button>
        ))}

        <button
          onClick={onAddFolder}
          className="flex min-h-[178px] items-center justify-center rounded-2xl border border-dashed border-border text-sm text-muted transition-colors hover:border-accent hover:text-accent"
        >
          + Add folder
        </button>
      </div>
    </div>
  );
}

function Badge({ children, tone }: { children: React.ReactNode; tone?: 'magenta' | 'cyan' }) {
  const toneClass =
    tone === 'magenta' ? 'text-magenta border-magenta/40' : tone === 'cyan' ? 'text-cyan border-cyan/40' : 'text-muted border-border';
  return (
    <span className={`rounded-md border bg-bg/70 px-1.5 py-1 font-mono text-[9px] tracking-wide backdrop-blur ${toneClass}`}>
      {children}
    </span>
  );
}
