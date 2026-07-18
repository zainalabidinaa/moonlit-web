import { useState } from 'react';
import { motion } from 'framer-motion';
import { Eye } from 'lucide-react';
import { SPRING } from '@/lib/design/motion';
import type { MetaVideo } from '@/lib/types';

interface EpisodeRowProps {
  episode: MetaVideo;
  seasonNumber: number;
  progressFraction?: number;
  isWatched: boolean;
  onToggleWatched: () => void;
  onPlay: () => void;
}

export default function EpisodeRow({
  episode,
  seasonNumber,
  progressFraction,
  isWatched,
  onToggleWatched,
  onPlay,
}: EpisodeRowProps) {
  const [hovering, setHovering] = useState(false);

  const episodeLabel = episode.episode != null ? `${episode.episode}` : '-';
  const metaParts: string[] = [];
  if (episode.episode != null) metaParts.push(`S${seasonNumber} E${episode.episode}`);
  else metaParts.push(`S${seasonNumber}`);
  if (episode.released) metaParts.push(episode.released);
  const metaLine = metaParts.join(' · ');

  const thumbWidth = 260;
  const thumbHeight = 146;

  return (
    <div
      className="flex flex-col gap-2 cursor-pointer"
      style={{ width: thumbWidth }}
      onClick={onPlay}
    >
      <motion.div
        className="relative overflow-hidden bg-moonlit-elevated flex-shrink-0"
        style={{ width: thumbWidth, height: thumbHeight, borderRadius: 10 }}
        animate={{ scale: hovering ? 1.02 : 1 }}
        transition={SPRING.detailRow}
        onMouseEnter={() => setHovering(true)}
        onMouseLeave={() => setHovering(false)}
      >
        {episode.thumbnail ? (
          <img
            src={episode.thumbnail}
            alt={episode.title}
            className="w-full h-full object-cover"
          />
        ) : null}

        <div className="absolute top-2 left-2">
          <span className="text-[11px] font-bold text-white bg-black/78 px-[7px] py-1 rounded-full">
            {episodeLabel}
          </span>
        </div>

        {isWatched && (
          <div className="absolute top-2 right-2 text-[21px] text-emerald-400 drop-shadow-[0_2px_5px_rgba(0,0,0,0.55)] font-bold">
            <Eye size={18} className="fill-emerald-400/40" />
          </div>
        )}

        {progressFraction != null && progressFraction > 0 && !isWatched && (
          <div className="absolute bottom-1 left-1 right-1">
            <div className="h-[3px] rounded-full bg-white/28 overflow-hidden">
              <div
                className="h-full rounded-full bg-white"
                style={{ width: `${Math.min(Math.max(progressFraction, 0), 1) * 100}%` }}
              />
            </div>
          </div>
        )}
      </motion.div>

      <div className="flex gap-2" style={{ width: thumbWidth }}>
        <div className="flex-1 min-h-[72px]">
          <p className="text-[14px] font-semibold text-white line-clamp-1">{episode.title}</p>
          <p className="text-[12px] font-medium text-white/50">{metaLine}</p>
          {episode.overview && (
            <p className="text-[12px] font-medium text-white/70 line-clamp-2 mt-[2px]">{episode.overview}</p>
          )}
        </div>
        <button
          type="button"
          className="flex-shrink-0 w-[26px] h-[26px] rounded-full flex items-center justify-center mt-1"
          style={{
            background: isWatched ? 'rgba(255,255,255,0.14)' : 'rgba(255,255,255,0.06)',
            border: '1px solid rgba(255,255,255,0.12)',
          }}
          onClick={(e) => {
            e.stopPropagation();
            onToggleWatched();
          }}
        >
          <Eye size={12} className={isWatched ? 'text-white' : 'text-white/60'} />
        </button>
      </div>
    </div>
  );
}
