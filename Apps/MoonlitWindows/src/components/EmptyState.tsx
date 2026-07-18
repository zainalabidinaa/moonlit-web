import type { ReactNode } from 'react';

interface EmptyStateProps {
  icon: ReactNode;
  title: string;
  message?: string;
  action?: { label: string; onClick: () => void };
}

export default function EmptyState({ icon, title, message, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center gap-4 py-16 px-6">
      <div className="glass-circle w-12 h-12 flex items-center justify-center text-white/70">
        {icon}
      </div>
      <h3 className="text-[17px] font-bold text-white text-center">{title}</h3>
      {message && (
        <p className="text-[14px] text-white/60 text-center max-w-xs">{message}</p>
      )}
      {action && (
        <button type="button" onClick={action.onClick} className="btn-primary mt-2">
          {action.label}
        </button>
      )}
    </div>
  );
}
