import { useState, useEffect } from 'react';
import type { IPTVChannel, EPGNowNext } from '@/lib/iptv';
import { channelHasCatchup } from '@/lib/iptv';

interface Props {
  channel: IPTVChannel;
  nowNext?: EPGNowNext;
  onClick: (channel: IPTVChannel) => void;
}

export function ChannelTile({ channel, nowNext, onClick }: Props) {
  const showCatchup = channelHasCatchup(channel);
  const current = nowNext?.current;
  const next = nowNext?.next;

  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (!current) return;
    const interval = setInterval(() => setNow(Date.now()), 2000);
    return () => clearInterval(interval);
  }, [current]);

  const progress = current
    ? Math.min(1, Math.max(0, (now - current.startMs) / (current.endMs - current.startMs)))
    : 0;

  return (
    <button
      onClick={() => onClick(channel)}
      className="group relative flex flex-col items-center gap-2 p-3 rounded-ml-lg bg-[#1f1f1f] border border-white/5 hover:border-white/[0.14] hover:shadow-ml-lift transition-all text-left w-[150px]"
    >
      <div className="relative w-[120px] aspect-square rounded-ml-sm overflow-hidden bg-[#2a2a2a] flex items-center justify-center">
        {channel.logo ? (
          <img
            src={channel.logo}
            alt=""
            className="w-full h-full object-contain"
            loading="lazy"
            onError={e => {
              (e.target as HTMLImageElement).style.display = 'none';
              (e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden');
            }}
          />
        ) : null}
        <span className={`text-[10px] text-white/30 font-medium ${channel.logo ? 'hidden' : ''}`}>
          {channel.name.slice(0, 3).toUpperCase()}
        </span>
        <div className="absolute inset-0 ring-1 ring-inset ring-white/[0.04] rounded-ml-sm" />
      </div>

      <div className="w-full min-w-0">
        <p className="text-xs font-medium text-white/80 truncate leading-tight">{channel.name}</p>
        {current && (
          <div className="mt-1 space-y-0.5">
            <p className="text-[10px] text-white/50 truncate leading-tight">{current.title}</p>
            <div className="h-0.5 w-full rounded-full bg-white/10 overflow-hidden">
              <div
                className="h-full rounded-full bg-white/50 transition-[width] duration-[2000ms] ease-linear"
                style={{ width: `${Math.round(progress * 100)}%` }}
              />
            </div>
            {next && (
              <p className="text-[10px] text-white/40 truncate leading-tight">
                Next: {next.title}
              </p>
            )}
          </div>
        )}
      </div>

      {showCatchup && (
        <span className="absolute top-2 right-2 flex h-4 w-4 items-center justify-center rounded-full bg-white/10 text-[8px] text-white/60">
          R
        </span>
      )}

      <div className="absolute inset-0 rounded-ml-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
        <div className="absolute inset-0 rounded-ml-lg bg-gradient-to-t from-white/[0.03] to-transparent" />
      </div>
    </button>
  );
}
