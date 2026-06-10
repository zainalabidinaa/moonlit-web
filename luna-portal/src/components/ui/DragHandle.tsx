export function DragHandle() {
  return (
    <div className="cursor-grab active:cursor-grabbing text-muted hover:text-text transition-colors px-1 select-none">
      <svg width="12" height="20" viewBox="0 0 12 20" fill="currentColor">
        <circle cx="3" cy="4" r="1.5" /><circle cx="9" cy="4" r="1.5" />
        <circle cx="3" cy="10" r="1.5" /><circle cx="9" cy="10" r="1.5" />
        <circle cx="3" cy="16" r="1.5" /><circle cx="9" cy="16" r="1.5" />
      </svg>
    </div>
  );
}
