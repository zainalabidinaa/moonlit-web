import { Trophy } from 'lucide-react';

interface AwardBadgeProps {
  asset: string;
  caption: string;
  isWinner: boolean;
}

export default function AwardBadge({ asset, caption, isWinner }: AwardBadgeProps) {
  const tint = '#D4AF37';

  return (
    <div className="flex flex-col items-center gap-[5px]">
      <div className="flex items-center gap-[-2px]">
        {isWinner && (
          <span className="text-[44px] leading-none" style={{ color: tint }}>
            &#127942;
          </span>
        )}
        <span
          className="text-[50px] leading-none select-none"
          style={{ color: tint }}
        >
          {asset}
        </span>
        {isWinner && (
          <span className="text-[44px] leading-none" style={{ color: tint }}>
            &#127942;
          </span>
        )}
      </div>
      <span className="text-[10px] font-semibold text-white/85 line-clamp-1 shadow-md">
        {caption}
      </span>
    </div>
  );
}
