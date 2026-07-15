/** True when running inside the Tauri desktop shell (Windows/macOS dev). */
export function isDesktop(): boolean {
  return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}
