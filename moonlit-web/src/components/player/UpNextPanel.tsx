/* eslint-disable react-refresh/only-export-components */
import { useEffect, useState } from 'react';
import { X } from 'lucide-react';
import { usePlayer } from '@/app/PlayerProvider';
import { fetchMeta } from '@/lib/stremio';
import { useAuth } from '@/app/AuthProvider';
import type { MetaDetail } from '@/lib/types';

interface EpisodeRef { id: string; season: number; episode: number; title?: string; thumbnail?: string; overview?: string }

export function parseEpisodeId(mediaId: string): { imdb: string; season: number; episode: number } | null {
  const m = mediaId.match(/^(tt\d+):(\d+):(\d+)$/);
  return m ? { imdb: m[1], season: Number(m[2]), episode: Number(m[3]) } : null;
}

export function findAdjacent(videos: EpisodeRef[], season: number, episode: number, dir: 1 | -1): EpisodeRef | null {
  const ordered = [...videos].sort((a, b) => a.season - b.season || a.episode - b.episode);
  const idx = ordered.findIndex((v) => v.season === season && v.episode === episode);
  if (idx === -1) return null;
  return ordered[idx + dir] ?? null;
}

export function UpNextPanel({ mediaId, mediaType, onClose, embedded = false }: {
  mediaId: string; mediaType: string; onClose: () => void; embedded?: boolean;
}) {
  const { open } = usePlayer();
  const { currentProfile } = useAuth();
  const [meta, setMeta] = useState<MetaDetail | null>(null);
  const [season, setSeason] = useState<number>(parseEpisodeId(mediaId)?.season ?? 1);
  const cur = parseEpisodeId(mediaId);

  // Simple addon list from localStorage — matches how the app stores manifests
  const getAddons = () => {
    try {
      const key = currentProfile ? `moonlit.addons.${currentProfile.id}` : 'moonlit.addons';
      const raw = localStorage.getItem(key);
      if (!raw) return [];
      return JSON.parse(raw).map((a: { url?: string; transportUrl?: string }) => a.transportUrl ?? a.url ?? '').filter(Boolean) as string[];
    } catch { return []; }
  };

  useEffect(() => {
    (async () => {
      if (!cur || !currentProfile) return;
      const addonUrls = getAddons();
      for (const baseUrl of addonUrls) {
        const m = await fetchMeta(baseUrl.replace(/\/manifest\.json$/, ''), 'series', cur.imdb).catch(() => null);
        if (m?.videos?.length) { setMeta(m); return; }
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mediaId]);

  const episodes: EpisodeRef[] = (meta?.videos ?? [])
    .map((v) => ({
      id: v.id, season: v.season ?? 0, episode: v.episode ?? 0,
      title: v.title, thumbnail: v.thumbnail, overview: v.overview,
    }))
    .filter((v) => v.season > 0);
  const seasons = [...new Set(episodes.map((e) => e.season))].sort((a, b) => a - b);

  const playEpisode = (ep: EpisodeRef) => {
    onClose();
    open({
      type: mediaType, id: `${cur?.imdb}:${ep.season}:${ep.episode}`,
      metadata: {
        mediaId: `${cur?.imdb}:${ep.season}:${ep.episode}`, mediaType,
        title: ep.title ?? `S${ep.season} E${ep.episode}`, poster: ep.thumbnail,
      },
    });
  };

  return (
    <div className={embedded
      ? 'min-h-full'
      : 'absolute inset-y-0 right-0 z-30 w-[440px] overflow-y-auto border-l border-player-edge bg-player-elevated p-4 shadow-ml-panel'}>
      {!embedded && <div className="flex items-center justify-between pb-3">
        <div className="text-[14px] font-bold text-white">Up Next</div>
        <button type="button" aria-label="Close" onClick={onClose} className="text-white/60 hover:text-white"><X size={16} aria-hidden /></button>
      </div>}
      {seasons.length > 1 && (
        <div className="flex gap-1 overflow-x-auto pb-3">
          {seasons.map((sn) => (
            <button key={sn} type="button" onClick={() => setSeason(sn)}
              className={`shrink-0 rounded-full px-3 py-1 text-[12px] font-semibold ${season === sn ? 'bg-white text-black' : 'bg-white/10 text-white/70'}`}>
              Season {sn}
            </button>
          ))}
        </div>
      )}
      {episodes.filter((e) => e.season === season).map((ep) => {
        const isCurrent = cur?.season === ep.season && cur?.episode === ep.episode;
        return (
          <button key={ep.id} type="button" onClick={() => !isCurrent && playEpisode(ep)}
            className={`mb-2 flex w-full gap-3 rounded-xl p-2 text-left ${isCurrent ? 'bg-white/15 ring-1 ring-white/30' : 'hover:bg-white/8'}`}>
            {ep.thumbnail && <img src={ep.thumbnail} alt="" className="h-16 w-28 shrink-0 rounded-lg object-cover" />}
            <div className="min-w-0">
              <div className="truncate text-[13px] font-semibold text-white">E{ep.episode} · {ep.title ?? 'Episode'}</div>
              {ep.overview && <div className="line-clamp-2 text-[11px] text-white/50">{ep.overview}</div>}
            </div>
          </button>
        );
      })}
      {episodes.length === 0 && <div className="text-[12px] text-white/40">No episode data available.</div>}
    </div>
  );
}
