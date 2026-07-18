import { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { X, Star } from 'lucide-react';
import type { MetaPreview } from '@/lib/types';

interface TitleInfoPanelProps {
  item: MetaPreview;
  onClose: () => void;
  onOpenDetail: () => void;
}

export default function TitleInfoPanel({
  item,
  onClose,
  onOpenDetail,
}: TitleInfoPanelProps) {
  const [appeared, setAppeared] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => setAppeared(true), 10);
    return () => clearTimeout(t);
  }, []);

  const bgUrl = item.background ?? item.poster;

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
        className="relative bg-[#0E0D0C] border border-white/10 shadow-ml-panel rounded-ml-lg overflow-hidden"
        style={{ maxWidth: 560 }}
        initial={{ scale: 0.96 }}
        animate={{ scale: appeared ? 1 : 0.96 }}
        transition={{ duration: 0.22, ease: 'easeOut' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="relative overflow-hidden" style={{ maxHeight: '80vh' }}>
          {bgUrl && (
            <div className="relative h-32 -mb-1">
              <img
                src={bgUrl}
                alt=""
                className="w-full h-full object-cover"
              />
              <div className="absolute inset-0 bg-gradient-to-r from-[#0E0D0C]/85 to-transparent" />
              <div className="absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-[#0E0D0C]" />
            </div>
          )}

          <div className="relative p-6 pt-0">
            <div className="flex items-start justify-between mb-4">
              <p className="text-[10px] font-bold tracking-[3px] text-white/50 mt-4">
                ABOUT THIS TITLE
              </p>
              <button
                type="button"
                onClick={onClose}
                className="w-[34px] h-[34px] rounded-full bg-white/10 flex items-center justify-center text-white/85 hover:text-white flex-shrink-0 mt-3"
                aria-label="Close"
              >
                <X size={13} />
              </button>
            </div>

            <div className="flex gap-5">
              {item.poster && (
                <img
                  src={item.poster}
                  alt={item.name}
                  className="w-[100px] h-[150px] object-cover rounded-ml-card shadow-lg flex-shrink-0"
                />
              )}

              <div className="flex flex-col gap-2 min-w-0">
                <h2 className="text-[20px] font-bold text-white line-clamp-2">
                  {item.name}
                </h2>

                {item.releaseInfo && (
                  <span className="text-[13px] font-medium text-white/65">
                    {item.releaseInfo}
                  </span>
                )}

                {item.imdbRating && (
                  <div className="flex items-center gap-1.5">
                    <span className="text-[9px] font-black text-black bg-moonlit-gold px-[5px] py-0.5 rounded-[3px]">
                      IMDb
                    </span>
                    <span className="text-[13px] font-bold text-white/90">
                      {item.imdbRating}
                    </span>
                  </div>
                )}

                {item.genres && item.genres.length > 0 && (
                  <div className="flex gap-1.5 flex-wrap">
                    {item.genres.slice(0, 3).map((g) => (
                      <span
                        key={g}
                        className="text-[11.5px] font-medium text-white/75 bg-white/8 rounded-full px-3 py-1.5"
                      >
                        {g}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            </div>

            {item.description && (
              <p className="text-[13px] text-white/70 leading-relaxed mt-4 line-clamp-3">
                {item.description}
              </p>
            )}

            <button
              type="button"
              className="btn-primary mt-4 w-full justify-center flex items-center gap-2 text-[13px] font-bold"
              onClick={onOpenDetail}
            >
              Open Full Details
            </button>
          </div>
        </div>
      </motion.div>
    </motion.div>
  );
}
