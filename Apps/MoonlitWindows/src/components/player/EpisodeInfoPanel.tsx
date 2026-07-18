import { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { X } from 'lucide-react';
import type { MetaVideo } from '@/lib/types';

interface EpisodeInfoPanelProps {
  episode: MetaVideo;
  guestStars?: string[];
  directors?: string[];
  writers?: string[];
  onClose: () => void;
}

export default function EpisodeInfoPanel({
  episode,
  guestStars,
  directors,
  writers,
  onClose,
}: EpisodeInfoPanelProps) {
  const [appeared, setAppeared] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => setAppeared(true), 10);
    return () => clearTimeout(t);
  }, []);

  const stillUrl = episode.thumbnail;

  return (
    <motion.div
      className="fixed inset-0 z-50 flex items-center justify-center p-6"
      initial={{ opacity: 0 }}
      animate={{ opacity: appeared ? 1 : 0 }}
      transition={{ duration: 0.22 }}
      onClick={onClose}
    >
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" />

      <motion.div
        className="relative bg-player-elevated border border-player-edge shadow-ml-panel rounded-ml-lg overflow-hidden"
        style={{ maxWidth: 560, maxHeight: '86vh' }}
        initial={{ scale: 0.96 }}
        animate={{ scale: appeared ? 1 : 0.96 }}
        transition={{ duration: 0.22, ease: 'easeOut' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="overflow-y-auto max-h-[86vh] p-[22px] space-y-5">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-[10px] font-semibold tracking-[2.4px] text-player-ink-muted mb-1">
                ABOUT THIS EPISODE
              </p>
              <h2 className="text-[16px] font-semibold text-player-ink line-clamp-2">
                {episode.title}
              </h2>
            </div>
            <button
              type="button"
              onClick={onClose}
              className="w-9 h-9 rounded-full bg-[#323335] border border-white/10 flex items-center justify-center text-white/60 hover:text-white flex-shrink-0"
              aria-label="Close"
            >
              <X size={13} />
            </button>
          </div>

          <div className="relative rounded-ml-ctl overflow-hidden h-[168px]">
            {stillUrl ? (
              <img
                src={stillUrl}
                alt={episode.title}
                className="w-full h-full object-cover"
              />
            ) : (
              <div className="w-full h-full bg-[#191B1C]" />
            )}
            <div className="absolute inset-0 bg-gradient-to-t from-black/55 to-transparent" />
            <p className="absolute bottom-3 left-3 text-[11px] font-bold tracking-wide text-white/90 drop-shadow-md">
              S{episode.season ?? 0} · E{episode.episode ?? 0}
            </p>
          </div>

          {episode.overview && (
            <p className="text-[13px] text-player-ink-muted leading-relaxed">
              {episode.overview}
            </p>
          )}

          {(directors?.length || writers?.length) && (
            <div className="space-y-2">
              {directors?.length ? (
                <CrewRow label="DIRECTOR" names={directors} />
              ) : null}
              {writers?.length ? (
                <CrewRow label="WRITER" names={writers} />
              ) : null}
            </div>
          )}

          {guestStars?.length ? (
            <div>
              <div className="border-t border-white/10 pt-4 mb-3">
                <span className="text-[11px] font-semibold tracking-[1.6px] text-white/45">
                  CAST & GUEST STARS
                </span>
              </div>
              <div className="flex flex-wrap gap-3">
                {guestStars.map((name, i) => (
                  <span
                    key={i}
                    className="text-[11px] font-medium text-player-ink bg-white/5 rounded-full px-3 py-1"
                  >
                    {name}
                  </span>
                ))}
              </div>
            </div>
          ) : null}
        </div>
      </motion.div>
    </motion.div>
  );
}

function CrewRow({ label, names }: { label: string; names: string[] }) {
  return (
    <div className="flex gap-3">
      <span className="text-[10px] font-semibold tracking-[1px] text-white/40 w-[74px] flex-shrink-0 pt-px">
        {label}
      </span>
      <span className="text-[12.5px] text-player-ink-muted">
        {names.join(', ')}
      </span>
    </div>
  );
}
