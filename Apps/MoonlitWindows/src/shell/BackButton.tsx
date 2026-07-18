import { ButtonHTMLAttributes } from 'react';

export function BackButton({ label = 'Back', onClick }: { label?: string; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="fixed top-4 left-4 z-[60] glass-dark-capsule px-3 py-1.5 flex items-center gap-1.5 text-[13px] font-semibold text-white/85 hover:text-white"
    >
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M10 3L5 8l5 5" />
      </svg>
      {label}
    </button>
  );
}
