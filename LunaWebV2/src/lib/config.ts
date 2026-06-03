/**
 * App configuration — streaming (remux) server.
 *
 * The remux server is the official Stremio streaming server (see
 * deploy/stremio-server/). It remuxes MKV → HLS and transcodes incompatible
 * audio so any debrid stream plays in the browser.
 *
 * The URL is stored in localStorage so it can be changed in Settings without a
 * redeploy. DEFAULT_STREAMING_SERVER_URL can be hardcoded once you have a stable
 * deployment; until then it's empty (remux disabled → direct play only).
 */

const STORAGE_KEY = 'luna_streaming_server_url';

// Set this to your deployed Railway/Render URL to make it the default for everyone.
// e.g. 'https://luna-stremio-server.up.railway.app'
const DEFAULT_STREAMING_SERVER_URL = 'https://server-fuqr.onrender.com';

/** Returns the configured remux server base URL (no trailing slash), or '' if disabled. */
export function getStreamingServerUrl(): string {
  let url = DEFAULT_STREAMING_SERVER_URL;
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored !== null) url = stored;
  } catch {
    // localStorage unavailable (SSR / privacy mode) — fall back to default
  }
  return url.trim().replace(/\/+$/, '');
}

/** Persist a new remux server URL (empty string disables remux). */
export function setStreamingServerUrl(url: string): void {
  try {
    localStorage.setItem(STORAGE_KEY, url.trim().replace(/\/+$/, ''));
  } catch {
    // ignore
  }
}

/** True when a remux server is configured. */
export function isRemuxEnabled(): boolean {
  return getStreamingServerUrl().length > 0;
}
