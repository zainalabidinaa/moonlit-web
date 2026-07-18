import { useEffect, useState } from 'react';

export function ResumePrompt({ seconds, onStartOver }: { seconds: number; onStartOver: () => void }) {
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    const t = setTimeout(() => setVisible(false), 8000);
    return () => clearTimeout(t);
  }, []);
  if (!visible || seconds < 10) return null;
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60).toString().padStart(2, '0');
  return (
    <div className="absolute bottom-28 left-1/2 -translate-x-1/2 z-20 flex items-center gap-3 rounded-full bg-black/70 border border-white/10 px-4 py-2 text-[13px] text-white/85">
      <span>Resuming from {m}:{s}</span>
      <button
        type="button"
        onClick={() => { setVisible(false); onStartOver(); }}
        className="font-bold text-white hover:underline"
      >
        Start over
      </button>
    </div>
  );
}
