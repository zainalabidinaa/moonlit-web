import { isDesktop } from '@/lib/platform';

async function win() {
  const { getCurrentWindow } = await import('@tauri-apps/api/window');
  return getCurrentWindow();
}

/**
 * Desktop-only chrome: a top drag strip plus minimize/maximize/close buttons.
 * Renders nothing in the browser. Styling gets the full Mac-parity treatment
 * in Phase 2; this is functional chrome only.
 */
export function WindowControls() {
  if (!isDesktop()) return null;

  return (
    <>
      <div
        data-tauri-drag-region
        className="fixed top-0 left-0 right-0 h-8 z-[90]"
      />
      <div className="fixed top-2 right-3 z-[100] flex items-center gap-1">
        <button
          aria-label="Minimize"
          onClick={async () => (await win()).minimize()}
          className="w-8 h-8 rounded-lg flex items-center justify-center text-white/60 hover:text-white hover:bg-white/10"
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <path d="M1 5h8" stroke="currentColor" strokeWidth="1.2" />
          </svg>
        </button>
        <button
          aria-label="Maximize"
          onClick={async () => (await win()).toggleMaximize()}
          className="w-8 h-8 rounded-lg flex items-center justify-center text-white/60 hover:text-white hover:bg-white/10"
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <rect x="1.5" y="1.5" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="1.2" />
          </svg>
        </button>
        <button
          aria-label="Close"
          onClick={async () => (await win()).close()}
          className="w-8 h-8 rounded-lg flex items-center justify-center text-white/60 hover:text-white hover:bg-red-500/80"
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <path d="M1.5 1.5l7 7M8.5 1.5l-7 7" stroke="currentColor" strokeWidth="1.2" />
          </svg>
        </button>
      </div>
    </>
  );
}
