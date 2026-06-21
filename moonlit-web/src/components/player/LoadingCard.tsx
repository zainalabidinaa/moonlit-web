import { useState, useEffect, useRef } from 'react';

interface LoadingCardProps {
  background?: string;
  poster?: string;
  logo?: string;
  title: string;
  minVisibleMs?: number;
  onMinElapsed?: () => void;
}

export function LoadingCard({
  background, poster, logo, title,
  minVisibleMs = 800, onMinElapsed,
}: LoadingCardProps) {
  const [minElapsed, setMinElapsed] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    timerRef.current = setTimeout(() => {
      setMinElapsed(true);
      onMinElapsed?.();
    }, minVisibleMs);
    return () => { if (timerRef.current) clearTimeout(timerRef.current); };
  }, [minVisibleMs, onMinElapsed]);

  const bgSrc = background || poster;

  return (
    <div className="absolute inset-0 z-30 overflow-hidden bg-black">
      {/* Backdrop */}
      {bgSrc && (
        <>
          <img
            src={bgSrc}
            alt=""
            className="absolute inset-0 w-full h-full object-cover scale-110"
            style={{ filter: 'blur(24px)', opacity: 0.4 }}
            draggable={false}
          />
          <div className="absolute inset-0 bg-gradient-to-t from-black via-black/50 to-black/20" />
        </>
      )}

      {/* Center content */}
      <div className="absolute inset-0 flex flex-col items-center justify-center gap-6 px-8">
        {logo ? (
          <img
            src={logo}
            alt={title}
            className="max-h-28 max-w-sm object-contain drop-shadow-2xl animate-breathing-pulse select-none"
            draggable={false}
          />
        ) : (
          <h2 className="text-3xl font-black text-white text-center drop-shadow-2xl animate-breathing-pulse leading-tight">
            {title}
          </h2>
        )}

        {/* Loading indicator */}
        <div className="flex items-center gap-3 rounded-full border border-white/10 bg-black/40 px-4 py-2 backdrop-blur-xl">
          <span className="h-2 w-2 rounded-full bg-moonlit-accent animate-pulse" />
          <span className="text-sm font-semibold text-white/60">Loading</span>
        </div>
      </div>
    </div>
  );
}
