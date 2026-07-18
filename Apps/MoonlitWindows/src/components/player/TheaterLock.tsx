import { useState } from 'react';
import { Lock, LockOpen } from 'lucide-react';

interface TheaterLockProps {
  visible: boolean;
  onToggle: () => void;
}

export function TheaterLock({ visible, onToggle }: TheaterLockProps) {
  const [showHint, setShowHint] = useState(false);

  if (!visible) return null;

  return (
    <div className="absolute inset-0 z-50 flex items-center justify-center bg-black/60">
      <button
        onClick={() => {
          if (showHint) {
            onToggle();
            setShowHint(false);
          } else {
            setShowHint(true);
          }
        }}
        className="flex flex-col items-center gap-3 cursor-pointer"
      >
        {showHint ? (
          <>
            <LockOpen size={40} strokeWidth={1.5} className="text-white/80" />
            <span className="text-sm font-medium text-white/60">Tap to unlock</span>
          </>
        ) : (
          <Lock size={40} strokeWidth={1.5} className="text-white/80" />
        )}
      </button>
    </div>
  );
}
