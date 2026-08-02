import type { IPTVPlaylistSource } from './models';
import { resolveCreds, parseUrl, type ResolvedCreds } from './xtream-client';

export type IPTVProviderShape =
  | { readonly kind: 'xtream'; readonly creds: ResolvedCreds }
  | { readonly kind: 'm3u'; readonly url: string; readonly middleware: boolean }
  | { readonly kind: 'epg'; readonly url: string }
  | { readonly kind: 'invalid'; readonly reason: string };

const MIDDLEWARE_PATH_PATTERN = /\/(iptv|m3u|playlist|xmltv|threadfin|xteve)\b/;
const RAW_M3U_PATTERN = /\.m3u8?(\?|$)/i;

const MIDDLEWARE_CANDIDATE_PATHS = [
  '/iptv/m3u',
  '/m3u',
  '/playlist.m3u',
  '/get.php?type=m3u_plus',
];

function isMiddlewareURL(urlString: string): boolean {
  let comps: URL;
  try { comps = new URL(urlString); } catch { return false; }
  const path = comps.pathname;
  if (RAW_M3U_PATTERN.test(path)) return false;
  if (MIDDLEWARE_PATH_PATTERN.test(path)) return true;
  const isBareHost = path === '/' || !path;
  return isBareHost && !comps.search;
}

export function middlewareCandidates(forUrl: string): string[] {
  let comps: URL;
  try { comps = new URL(forUrl); } catch { return []; }
  const origin = `${comps.protocol}//${comps.host}${comps.port ? `:${comps.port}` : ''}`;
  return MIDDLEWARE_CANDIDATE_PATHS
    .map(path => origin + path)
    .filter(c => c !== forUrl);
}

export function credsFromSource(source: IPTVPlaylistSource): ResolvedCreds | null {
  if (source.xtream) {
    const resolved = resolveCreds(source.xtream);
    if (resolved) return resolved;
  }
  if (source.url) {
    const parsed = parseUrl(source.url);
    if (parsed) return parsed;
  }
  return null;
}

export function detectSource(source: IPTVPlaylistSource): IPTVProviderShape {
  if (source.kind === 'epg') {
    const url = (source.epgUrl || source.url).trim();
    return url ? { kind: 'epg', url } : { kind: 'invalid', reason: 'EPG source has no URL.' };
  }

  const creds = credsFromSource(source);
  if (creds) return { kind: 'xtream', creds };
  if (source.kind === 'xtream') {
    return { kind: 'invalid', reason: 'Xtream credentials are incomplete. Check server URL, username, and password.' };
  }

  const url = source.url.trim();
  if (!url) return { kind: 'invalid', reason: 'Playlist source has no URL.' };
  if (!/^https?:\/\//i.test(url)) {
    return { kind: 'invalid', reason: 'That does not look like a playlist URL. Use an http(s) M3U link or Xtream server.' };
  }
  return { kind: 'm3u', url, middleware: isMiddlewareURL(url) };
}
