import type { IPTVChannel, XtreamCredentials, XtreamServerCaps, XtreamShortEpgEntry } from './models';

const USER_AGENT = 'IPTVSmartersPro/3.1.5';

export class XtreamError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'XtreamError';
  }
}

export interface ResolvedCreds {
  base: string;
  username: string;
  password: string;
}

function asString(value: unknown): string | undefined {
  if (typeof value === 'string') return value;
  if (typeof value === 'number') return Number.isInteger(value) ? String(value) : String(value);
  if (typeof value === 'boolean') return value ? '1' : '0';
  return undefined;
}

function asInt(value: unknown): number | undefined {
  if (typeof value === 'number') return Math.floor(value);
  if (typeof value === 'string') {
    const n = parseInt(value, 10);
    if (!isNaN(n)) return n;
    const f = parseFloat(value);
    if (!isNaN(f)) return Math.floor(f);
  }
  if (typeof value === 'boolean') return value ? 1 : 0;
  return undefined;
}

function asDouble(value: unknown): number | undefined {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const f = parseFloat(value);
    if (!isNaN(f)) return f;
  }
  return undefined;
}

function nonEmpty(s: string | undefined | null): string | undefined {
  if (!s) return undefined;
  return s.trim() || undefined;
}

function decodeBase64(input: string | undefined): string {
  if (!input) return '';
  const raw = input.trim();
  if (!raw) return '';
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(raw) || raw.length % 4 !== 0) return raw;
  try {
    const decoded = atob(raw);
    const trimmed = decoded.trim();
    if (!trimmed) return raw;
    for (let i = 0; i < trimmed.length; i++) {
      const c = trimmed.charCodeAt(i);
      if (c < 0x20 && c !== 0x09 && c !== 0x0a && c !== 0x0d) return raw;
    }
    return trimmed;
  } catch {
    return raw;
  }
}

async function fetchJSON(url: string): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20_000);
  try {
    const response = await fetch(url, {
      headers: { 'User-Agent': USER_AGENT },
      signal: controller.signal,
    });
    if (!response.ok) throw new XtreamError(`Xtream server returned HTTP ${response.status}.`);
    return await response.json();
  } catch (err) {
    if (err instanceof XtreamError) throw err;
    throw new XtreamError(err instanceof Error ? err.message : 'Network error');
  } finally {
    clearTimeout(timeout);
  }
}

function apiUrl(
  creds: ResolvedCreds,
  action?: string,
  extra: Record<string, string> = {},
): string {
  const url = new URL(`${creds.base}/player_api.php`);
  url.searchParams.set('username', creds.username);
  url.searchParams.set('password', creds.password);
  if (action) url.searchParams.set('action', action);
  for (const [key, value] of Object.entries(extra).sort(([a], [b]) => a.localeCompare(b))) {
    url.searchParams.set(key, value);
  }
  return url.toString();
}

function deriveStreamBase(creds: ResolvedCreds, serverInfo: unknown): string {
  const info = serverInfo as Record<string, unknown> | undefined;
  if (!info) return creds.base;
  const protocol = asString(info['server_protocol'])?.toLowerCase();
  if (protocol !== 'https') return creds.base;
  const host = new URL(creds.base).hostname;
  const port = nonEmpty(asString(info['https_port'])) || nonEmpty(asString(info['port']));
  return port ? `https://${host}:${port}` : `https://${host}`;
}

function pickContainer(pref: 'ts' | 'm3u8', allowed: string[]): 'ts' | 'm3u8' {
  if (!allowed.length) return pref;
  if (allowed.includes(pref)) return pref;
  if (allowed.includes('ts')) return 'ts';
  if (allowed.includes('m3u8')) return 'm3u8';
  return pref;
}

export function resolveCreds(creds: XtreamCredentials): ResolvedCreds | null {
  const trimmedServer = creds.server.trim().replace(/\/+$/, '');
  const user = creds.username.trim();
  const pass = creds.password.trim();
  if (!/^https?:\/\//i.test(trimmedServer) || !user || !pass) return null;
  let url: URL;
  try { url = new URL(trimmedServer); } catch { return null; }
  return { base: `${url.protocol}//${url.host}${url.port ? `:${url.port}` : ''}`, username: user, password: pass };
}

export function parseUrl(urlString: string): ResolvedCreds | null {
  let comps: URL;
  try { comps = new URL(urlString); } catch { return null; }
  const path = comps.pathname;
  if (!/(\bget\.php\b|\bplayer_api\.php\b)$/i.test(path)) return null;
  const user = comps.searchParams.get('username');
  const pass = comps.searchParams.get('password');
  if (!user || !pass) return null;
  return { base: `${comps.protocol}//${comps.host}${comps.port ? `:${comps.port}` : ''}`, username: user, password: pass };
}

export function buildLiveStreamURL(
  creds: ResolvedCreds,
  streamId: string,
  container: 'ts' | 'm3u8',
  streamBase?: string,
): string {
  const base = streamBase || creds.base;
  const user = encodeURIComponent(creds.username);
  const pass = encodeURIComponent(creds.password);
  return `${base}/live/${user}/${pass}/${streamId}.${container}`;
}

export async function fetchUserInfo(creds: ResolvedCreds): Promise<XtreamServerCaps> {
  const url = apiUrl(creds);
  const raw = await fetchJSON(url);
  const dict = raw as Record<string, unknown>;
  const info = dict['user_info'] as Record<string, unknown> | undefined;
  if (!info) throw new XtreamError('Xtream login did not return account info. Check the server URL.');
  if (asInt(info['auth']) === 0) throw new XtreamError('Xtream rejected these credentials (auth failed).');
  const status = asString(info['status'])?.toLowerCase();
  if (status === 'expired') throw new XtreamError('This Xtream account is expired.');
  if (status === 'banned') throw new XtreamError('This Xtream account is banned.');
  if (status === 'disabled') throw new XtreamError('This Xtream account is disabled.');
  const allowedFormats = ((info['allowed_output_formats'] as unknown[]) ?? [])
    .map(f => asString(f)?.toLowerCase())
    .filter(Boolean) as string[];
  const streamBase = deriveStreamBase(creds, dict['server_info']);
  return { allowedFormats, streamBase };
}

export async function fetchLiveChannels(
  creds: ResolvedCreds,
  baseId: string,
  container: 'ts' | 'm3u8' = 'ts',
  caps?: XtreamServerCaps,
): Promise<IPTVChannel[]> {
  const resolvedContainer = pickContainer(container, caps?.allowedFormats ?? []);
  const streamBase = caps?.streamBase ?? creds.base;
  const categoriesURL = apiUrl(creds, 'get_live_categories');
  const streamsURL = apiUrl(creds, 'get_live_streams');

  const [categoriesRaw, streamsRaw] = await Promise.all([
    fetchJSON(categoriesURL),
    fetchJSON(streamsURL),
  ]);

  const categoryName: Record<string, string> = {};
  if (Array.isArray(categoriesRaw)) {
    for (const row of categoriesRaw as Record<string, unknown>[]) {
      const id = asString(row['category_id']);
      if (id) categoryName[id] = asString(row['category_name']) ?? '';
    }
  }

  if (!Array.isArray(streamsRaw)) return [];
  const out: IPTVChannel[] = [];
  for (const row of streamsRaw as Record<string, unknown>[]) {
    const streamId = asString(row['stream_id']);
    if (!streamId) continue;
    const tvgId = nonEmpty(asString(row['epg_channel_id'])) || undefined;
    const catId = asString(row['category_id']);
    const group = catId && categoryName[catId] ? categoryName[catId] : undefined;
    const url = buildLiveStreamURL(creds, streamId, resolvedContainer, streamBase);

    let catchupType: string | undefined;
    let catchupDays: number | undefined;
    const archive = asInt(row['tv_archive'] as unknown);
    if (archive && archive > 0) {
      catchupType = 'xtream';
      const days = asInt(row['tv_archive_duration'] as unknown);
      if (days && days > 0) catchupDays = days;
    }

    const name = nonEmpty(asString(row['name'])) || `Stream ${streamId}`;
    const logo = nonEmpty(asString(row['stream_icon'])) || undefined;

    out.push({
      id: `${baseId}::xt::${streamId}`,
      tvgId,
      name,
      logo,
      group,
      url,
      catchupType,
      catchupDays,
    });
  }
  return out;
}

export async function fetchShortEpg(
  creds: ResolvedCreds,
  streamId: string,
  limit: number = 8,
): Promise<XtreamShortEpgEntry[]> {
  const url = apiUrl(creds, 'get_short_epg', { stream_id: streamId, limit: String(limit) });
  let raw: unknown;
  try { raw = await fetchJSON(url); } catch { return []; }
  const dict = raw as Record<string, unknown> | undefined;
  if (!dict) return [];
  const listings = dict['epg_listings'] as Record<string, unknown>[] | undefined;
  if (!listings) return [];
  const out: XtreamShortEpgEntry[] = [];
  for (const row of listings) {
    const start = asDouble(row['start_timestamp']);
    const stop = asDouble(row['stop_timestamp']);
    if (!start || !stop) continue;
    const startMs = start * 1000;
    const endMs = stop * 1000;
    if (endMs <= startMs) continue;
    out.push({
      title: decodeBase64(asString(row['title'])) || 'Untitled',
      description: nonEmpty(decodeBase64(asString(row['description']))) || undefined,
      startMs,
      endMs,
    });
  }
  return out;
}
