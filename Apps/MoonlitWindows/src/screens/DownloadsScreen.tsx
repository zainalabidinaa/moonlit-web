import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { ArrowDownCircle, Play, Trash2, Tv, Film } from 'lucide-react';
import EmptyState from '@/components/EmptyState';

interface DownloadItem {
  mediaId: string;
  type: 'movie' | 'series';
  name: string;
  poster?: string;
  quality?: string;
  url: string;
  state: 'queued' | 'downloading' | 'paused' | 'completed' | 'failed';
  progress: number;
  totalBytes: number;
  receivedBytes: number;
  createdAt: number;
}

const STORAGE_KEY = 'moonlit.downloads';

function loadDownloads(): DownloadItem[] {
  try { return JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]'); }
  catch { return []; }
}

function saveDownloads(items: DownloadItem[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
}

function byteString(bytes: number): string {
  if (bytes <= 0) return '-';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function statusLine(item: DownloadItem): string {
  switch (item.state) {
    case 'queued': return 'Queued';
    case 'downloading': {
      const pct = Math.round(item.progress * 100);
      return `Downloading ${pct}% · ${byteString(item.receivedBytes)} / ${byteString(item.totalBytes)}`;
    }
    case 'paused': return 'Paused';
    case 'completed': {
      const parts = [item.quality, byteString(item.totalBytes)].filter(Boolean);
      return parts.join(' · ');
    }
    case 'failed': return 'Failed';
  }
}

export function DownloadsScreen() {
  const [items, setItems] = useState<DownloadItem[]>([]);

  useEffect(() => {
    const downloads = loadDownloads();
    setItems(downloads.sort((a, b) => b.createdAt - a.createdAt));
  }, []);

  const handleDelete = useCallback((index: number) => {
    const newItems = [...items];
    newItems.splice(index, 1);
    setItems(newItems);
    saveDownloads(newItems);
  }, [items]);

  const handlePlay = useCallback((item: DownloadItem) => {
    alert(`Play: ${item.name}`);
  }, []);

  return (
    <div className="min-h-screen bg-moonlit-bg">
      {items.length === 0 ? (
        <EmptyState
          icon={<ArrowDownCircle size={24} />}
          title="No downloads yet"
          message="Downloaded titles play offline and appear here."
        />
      ) : (
        <div className="max-w-[800px] mx-auto px-5 pt-24 pb-12">
          <div className="flex flex-col gap-2.5">
            {items.map((item, i) => (
              <div
                key={`${item.mediaId}-${i}`}
                className="flex items-center gap-3.5 p-3 bg-moonlit-surface rounded-lg"
              >
                <div className="w-[60px] h-[90px] rounded-md overflow-hidden shrink-0 bg-moonlit-elevated">
                  {item.poster ? (
                    <img src={item.poster} alt={item.name} className="w-full h-full object-cover" />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-white/30">
                      {item.type === 'series' ? <Tv size={20} /> : <Film size={20} />}
                    </div>
                  )}
                </div>

                <div className="flex flex-col gap-1.5 flex-1 min-w-0">
                  <span className="text-[15px] font-semibold text-white truncate">{item.name}</span>
                  <span className="text-[12px] text-white/40">{statusLine(item)}</span>
                  {(item.state === 'downloading' || item.state === 'queued') && (
                    <div className="w-full max-w-[260px] h-1.5 bg-white/[0.08] rounded-full overflow-hidden">
                      <motion.div
                        className="h-full bg-harbor-gold rounded-full"
                        style={{ width: `${Math.max(0, Math.min(item.progress * 100, 100))}%` }}
                      />
                    </div>
                  )}
                </div>

                <div className="flex items-center gap-2.5 shrink-0">
                  {item.state === 'completed' && (
                    <button
                      type="button"
                      onClick={() => handlePlay(item)}
                      className="w-[34px] h-[34px] rounded-full bg-moonlit-elevated flex items-center justify-center text-white hover:bg-white/[0.1] transition-colors"
                      title="Play offline"
                    >
                      <Play size={14} />
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={() => handleDelete(i)}
                    className="w-[34px] h-[34px] rounded-full bg-moonlit-elevated flex items-center justify-center text-white/60 hover:text-red-400 transition-colors"
                    title="Delete download"
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
