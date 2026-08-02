import { useMemo, useRef, useEffect, useState } from 'react';
import type { EPGProgram, IPTVChannel } from '@/lib/iptv';
import { channelHasCatchup, buildCatchupURL } from '@/lib/iptv';

const HOUR_WIDTH = 180;
const CHANNEL_HEIGHT = 52;
const HOURS_VISIBLE = 6;

interface Props {
  channels: IPTVChannel[];
  programsByChannel: Record<string, EPGProgram[]>;
  onPlayChannel: (channel: IPTVChannel) => void;
  onPlayCatchup: (channel: IPTVChannel, startMs: number, endMs: number) => void;
  onClose: () => void;
}

export function EPGGuide({ channels, programsByChannel, onPlayChannel, onPlayCatchup, onClose }: Props) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [nowMs] = useState(() => Date.now());

  const { channelList, startTime, endTime, gridWidth, nowX } = useMemo(() => {
    const list = channels.filter(ch => programsByChannel[ch.tvgId ?? ''] || programsByChannel[ch.id]);
    const now = new Date();
    const start = new Date(now);
    start.setMinutes(0, 0, 0);
    start.setHours(start.getHours() - 1);
    const end = new Date(start);
    end.setHours(end.getHours() + HOURS_VISIBLE + 2);

    const numHours = (end.getTime() - start.getTime()) / 3_600_000;
    const w = Math.ceil(numHours * HOUR_WIDTH);
    const nowOffset = (now.getTime() - start.getTime()) / 3_600_000 * HOUR_WIDTH;

    return { channelList: list, startTime: start.getTime(), endTime: end.getTime(), gridWidth: w, nowX: nowOffset };
  }, [channels, programsByChannel]);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollLeft = Math.max(0, nowX - 200);
    }
  }, [nowX]);

  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [onClose]);

  const timeLabels = useMemo(() => {
    const labels: { label: string; x: number }[] = [];
    const startHour = new Date(startTime);
    startHour.setMinutes(0, 0, 0);
    if (startHour.getMinutes() !== 0) startHour.setHours(startHour.getHours() + 1);

    while (startHour.getTime() < endTime) {
      const x = (startHour.getTime() - startTime) / 3_600_000 * HOUR_WIDTH;
      labels.push({
        label: startHour.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false }),
        x,
      });
      startHour.setMinutes(startHour.getMinutes() + 30);
    }
    return labels;
  }, [startTime, endTime]);

  return (
    <div className="fixed inset-0 z-[100] flex flex-col bg-[#111111]">
      <div className="flex items-center justify-between px-6 py-3 border-b border-white/10 shrink-0">
        <h2 className="text-base font-semibold text-white">TV Guide</h2>
        <button
          onClick={onClose}
          className="flex h-7 w-7 items-center justify-center rounded text-white/50 hover:bg-white/10 hover:text-white"
          aria-label="Close guide"
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M1 1l12 12M13 1L1 13" />
          </svg>
        </button>
      </div>

      <div className="flex-1 flex flex-col overflow-hidden">
        <div className="flex border-b border-white/10 shrink-0">
          <div className="w-[160px] shrink-0 border-r border-white/10 px-4 py-2">
            <span className="text-[10px] font-bold text-white/30 uppercase tracking-wider">Channel</span>
          </div>
          <div className="flex-1 overflow-hidden" ref={scrollRef}>
            <div className="relative h-7" style={{ width: gridWidth }}>
              {timeLabels.map((t, i) => (
                <span
                  key={i}
                  className="absolute top-1 text-[10px] text-white/30"
                  style={{ left: t.x }}
                >
                  {t.label}
                </span>
              ))}
              <div
                className="absolute top-0 h-full w-px bg-gold/60"
                style={{ left: nowX }}
              />
            </div>
          </div>
        </div>

        <div
          className="flex-1 overflow-auto scrollbar-crisp"
          ref={scrollRef}
          onScroll={e => {
            const gridHeader = (e.target as HTMLElement).previousElementSibling?.querySelector('.flex-1 > div') as HTMLElement;
            const timeHeader = gridHeader?.parentElement;
            if (timeHeader) {
              const container = timeHeader.parentElement;
              if (container) container.scrollLeft = (e.target as HTMLElement).scrollLeft;
            }
          }}
        >
          <div className="flex flex-col" style={{ minWidth: gridWidth }}>
            {channelList.length === 0 && (
              <div className="flex items-center justify-center h-32 text-white/40 text-sm">
                No program data available for these channels.
              </div>
            )}
            {channelList.map(channel => {
              const programs = programsByChannel[channel.tvgId ?? ''] || programsByChannel[channel.id] || [];
              const showCatchup = channelHasCatchup(channel);
              return (
                <div
                  key={channel.id}
                  className="flex border-b border-white/5 hover:bg-white/[0.02] transition-colors"
                  style={{ height: CHANNEL_HEIGHT }}
                >
                  <div className="w-[160px] shrink-0 border-r border-white/10 px-4 py-2 flex items-center gap-2">
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-medium text-white/80 truncate">{channel.name}</p>
                      {channel.group && (
                        <p className="text-[10px] text-white/30 truncate">{channel.group}</p>
                      )}
                    </div>
                  </div>

                  <div className="flex-1 relative overflow-hidden">
                    {programs.map(p => {
                      const left = (p.startMs - startTime) / 3_600_000 * HOUR_WIDTH;
                      const width = Math.max(2, (p.endMs - p.startMs) / 3_600_000 * HOUR_WIDTH);
                      const isLive = nowMs >= p.startMs && nowMs < p.endMs;
                      const isPast = nowMs >= p.endMs;

                      return (
                        <button
                          key={`${p.channelTvgId}-${p.startMs}`}
                          className={`absolute top-1 bottom-1 rounded px-2 flex flex-col justify-center overflow-hidden transition-colors ${
                            isLive
                              ? 'bg-white/15 hover:bg-white/20'
                              : isPast
                                ? 'bg-white/[0.03]'
                                : 'bg-white/[0.03] hover:bg-white/[0.06]'
                          }`}
                          style={{ left: Math.max(0, left), width }}
                          onClick={() => {
                            if (showCatchup && isPast) {
                              const url = buildCatchupURL(channel, p.startMs, p.endMs);
                              if (url) {
                                onPlayCatchup(channel, p.startMs, p.endMs);
                                return;
                              }
                            }
                            if (isLive) {
                              onPlayChannel(channel);
                            } else if (showCatchup && isPast) {
                              onPlayCatchup(channel, p.startMs, p.endMs);
                            }
                          }}
                          title={`${p.title}\n${isPast && showCatchup ? 'Click for catch-up' : ''}`}
                        >
                          <p className={`text-[11px] leading-tight truncate font-medium ${
                            isLive ? 'text-white' : 'text-white/50'
                          }`}>
                            {p.title}
                          </p>
                          <p className="text-[9px] text-white/20 truncate">
                            {new Date(p.startMs).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false })}
                          </p>
                        </button>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
