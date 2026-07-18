/// Platform-aware networking.
/// In the browser, Stremio addon calls go through the `/api/stremio/*` Vercel
/// edge proxies (CORS + SRT→VTT). In the Tauri desktop shell there is no such
/// server — requests are made DIRECTLY to the addon via the Tauri HTTP client
/// (native reqwest, immune to CORS).
import { isDesktop } from './index';

export type StremioRoute = 'manifest' | 'catalog' | 'meta' | 'stream' | 'subtitles';

/** fetch that works cross-origin on desktop (Tauri) and normally in browsers. */
export async function platformFetch(url: string, init?: RequestInit): Promise<Response> {
  if (isDesktop()) {
    const { fetch: tauriFetch } = await import('@tauri-apps/plugin-http');
    return tauriFetch(url, init);
  }
  return fetch(url, init);
}

function srtToVtt(srt: string): string {
  return (
    'WEBVTT\n\n' +
    srt
      .replace(/\r\n/g, '\n')
      .replace(/\r/g, '\n')
      .replace(/^\d+\n/gm, '')
      .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2')
      .trim()
  );
}

/** Build the direct upstream URL for a stremio route (mirrors the edge fns). */
export function stremioUpstreamUrl(
  route: StremioRoute,
  p: { url: string; type?: string; id?: string; extras?: Record<string, string> },
): string {
  const base = p.url.replace(/\/manifest\.json(\?.*)?$/, '').replace(/\/$/, '');
  switch (route) {
    case 'manifest':
      return p.url.includes('manifest.json') ? p.url : `${base}/manifest.json`;
    case 'catalog': {
      if (p.extras && Object.keys(p.extras).length > 0) {
        const extraParts = Object.entries(p.extras)
          .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
          .join('&');
        return `${base}/catalog/${p.type}/${p.id}/${extraParts}.json`;
      }
      return `${base}/catalog/${p.type}/${p.id}.json`;
    }
    case 'meta':
      return `${base}/meta/${p.type}/${p.id}.json`;
    case 'stream':
      return `${base}/stream/${p.type}/${p.id}.json`;
    case 'subtitles':
      return `${base}/subtitles/${p.type}/${p.id}.json`;
  }
}

/**
 * Fetch a Stremio addon resource. Desktop: direct native call.
 * Browser: through the `/api/stremio/*` proxy.
 */
export async function stremioFetch(
  route: StremioRoute,
  p: { url: string; type?: string; id?: string; extras?: Record<string, string> },
): Promise<Response> {
  if (isDesktop()) {
    return platformFetch(stremioUpstreamUrl(route, p));
  }
  const params = new URLSearchParams({ url: p.url });
  if (p.type) params.set('type', p.type);
  if (p.id) params.set('id', p.id);
  if (p.extras && Object.keys(p.extras).length > 0) params.set('extras', JSON.stringify(p.extras));
  return fetch(`/api/stremio/${route}?${params}`);
}

/** Subtitle URL for the WEB player (<track> needs VTT). Desktop mpv uses raw URLs. */
export function subtitleTrackUrl(rawUrl: string): string {
  if (isDesktop()) return rawUrl;
  return `/api/stremio/vtt?url=${encodeURIComponent(rawUrl)}`;
}

/** Fetch subtitle text and normalize to VTT (desktop-side equivalent of the vtt proxy). */
export async function fetchSubtitleAsVtt(rawUrl: string): Promise<string> {
  const res = await platformFetch(rawUrl);
  if (!res.ok) throw new Error(`Subtitle fetch failed (${res.status})`);
  const text = await res.text();
  return text.trimStart().startsWith('WEBVTT') ? text : srtToVtt(text);
}
