import { Star } from 'lucide-react';

interface RatingBadgeProps {
  rating: string | number;
  compact?: boolean;
}

export default function RatingBadge({ rating, compact }: RatingBadgeProps) {
  const display = String(rating).replace('/10', '');

  return (
    <span className={`rating-badge ${compact ? 'text-[9px] gap-0.5 px-1.5 py-0.5' : ''}`}>
      <Star size={compact ? 8 : 10} className="text-moonlit-gold fill-moonlit-gold shrink-0" />
      <span
        className="font-black text-moonlit-gold"
        style={{ fontSize: compact ? 8 : 10 }}
      >
        IMDb
      </span>
      <span
        className="font-semibold text-white"
        style={{ fontSize: compact ? 10 : 13 }}
      >
        {display}
      </span>
    </span>
  );
}
