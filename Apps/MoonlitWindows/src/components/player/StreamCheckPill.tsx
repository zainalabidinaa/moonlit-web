import { useEffect, useState } from 'react';

export function StreamCheckPill({ onPickAnother }: { onPickAnother: () => void }) {
  const [phase, setPhase] = useState<'hidden' | 'shown'>('hidden');
  useEffect(() => {
    const show = setTimeout(() => setPhase('shown'), 4000);
    const hide = setTimeout(() => setPhase('hidden'), 13000);
    return () => { clearTimeout(show); clearTimeout(hide); };
  }, []);
  if (phase !== 'shown') return null;
  return (
    <div className="absolute top-20 left-1/2 -translate-x-1/2 z-20 flex items-center gap-3 rounded-full bg-black/70 border border-white/10 px-4 py-2 text-[13px] text-white/85">
      <span>Does this look right?</span>
      <button type="button" onClick={onPickAnother} className="font-bold text-white hover:underline">
        Pick another source
      </button>
    </div>
  );
}
