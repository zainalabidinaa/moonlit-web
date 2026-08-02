import type { IPTVChannel } from './models';

const EXTINF = '#EXTINF:';
const EXTGRP = '#EXTGRP:';
const EXTVLCOPT = '#EXTVLCOPT:';
const KODIPROP = '#KODIPROP:';

const decorativeChars = new Set('#=─━▓█▀▄░♦◆■▼▲★☆-_*+~|·•:. \t');

interface PendingEntry {
  title: string;
  attrs: Record<string, string>;
}

function isClosedQuoted(s: string): boolean {
  if (s.length < 2) return false;
  if (!s.startsWith('"')) return true;
  return s.endsWith('"') && (s.match(/"/g)?.length ?? 0) % 2 === 0;
}

function trimQuotes(s: string): string {
  let result = s;
  if (result.startsWith('"')) result = result.slice(1);
  if (result.endsWith('"')) result = result.slice(0, -1);
  return result;
}

function attrTitleSplit(chars: string): number {
  let inQuote = false;
  let lastQuoteClose = -1;
  for (let i = 0; i < chars.length; i++) {
    if (chars[i] === '"') {
      if (inQuote) lastQuoteClose = i;
      inQuote = !inQuote;
    }
  }
  const after = firstUnquotedComma(chars, lastQuoteClose >= 0 ? lastQuoteClose + 1 : 0);
  if (after >= 0) return after;
  return firstUnquotedComma(chars, 0);
}

function firstUnquotedComma(s: string, start: number): number {
  let inQuote = false;
  for (let i = start; i < s.length; i++) {
    const c = s[i];
    if (c === '"') inQuote = !inQuote;
    else if (c === ',' && !inQuote) return i;
  }
  return -1;
}

function parseExtinf(rest: string): PendingEntry {
  const commaIdx = attrTitleSplit(rest);
  const attrsPart = commaIdx >= 0 ? rest.slice(0, commaIdx) : rest;
  const titlePart = commaIdx >= 0 ? rest.slice(commaIdx + 1).trim() : '';
  const tokens = attrsPart.trim().split(/[ \t]+/);
  const attrs: Record<string, string> = {};
  let i = 0;
  while (i < tokens.length) {
    const tok = tokens[i];
    i++;
    if (!tok) continue;
    const eq = tok.indexOf('=');
    if (eq < 0) continue;
    const key = tok.slice(0, eq).toLowerCase();
    let val = tok.slice(eq + 1);
    if (val.startsWith('"')) {
      let combined = val;
      while (!isClosedQuoted(combined) && i < tokens.length) {
        combined += ' ' + tokens[i];
        i++;
      }
      val = trimQuotes(combined);
    }
    attrs[key] = val;
  }
  return { title: titlePart, attrs };
}

function captureVlcOpt(rest: string, attrs: Record<string, string>): void {
  const eq = rest.indexOf('=');
  if (eq < 0) return;
  const key = rest.slice(0, eq).trim().toLowerCase();
  const val = trimQuotes(rest.slice(eq + 1).trim());
  if (!val) return;
  if (key === 'http-user-agent') attrs['vlcopt-user-agent'] = val;
  else if (key === 'http-referrer') attrs['vlcopt-referrer'] = val;
}

function capturePipeOpts(rest: string, attrs: Record<string, string>): void {
  for (const pair of rest.split('&')) {
    if (!pair) continue;
    const eq = pair.indexOf('=');
    if (eq < 0) continue;
    const key = pair.slice(0, eq).trim().toLowerCase();
    let val = pair.slice(eq + 1).trim();
    try { val = decodeURIComponent(val); } catch { /* use raw */ }
    if (!val) continue;
    if (key === 'user-agent' && !attrs['vlcopt-user-agent']) attrs['vlcopt-user-agent'] = val;
    else if ((key === 'referer' || key === 'referrer') && !attrs['vlcopt-referrer']) attrs['vlcopt-referrer'] = val;
    else if (key === 'cookie' && !attrs['vlcopt-cookie']) attrs['vlcopt-cookie'] = val;
  }
}

function buildHeaders(attrs: Record<string, string>): Record<string, string> | undefined {
  const headers: Record<string, string> = {};
  const ua = attrs['vlcopt-user-agent'];
  const ref = attrs['vlcopt-referrer'];
  const cookie = attrs['vlcopt-cookie'];
  if (ua) headers['User-Agent'] = ua;
  if (ref) headers['Referer'] = ref;
  if (cookie) headers['Cookie'] = cookie;
  return Object.keys(headers).length ? headers : undefined;
}

function nonEmpty(s: string | undefined | null): string | undefined {
  if (!s) return undefined;
  return s.trim() || undefined;
}

function isDecorativeRow(name: string): boolean {
  const trimmed = name.trim();
  if (!trimmed) return true;
  if ([...trimmed].every(c => decorativeChars.has(c))) return true;
  return ![...trimmed].some(c => /[a-zA-Z0-9]/.test(c));
}

export function parseM3U(text: string, baseId: string): IPTVChannel[] {
  let content = text;
  if (content.startsWith('\uFEFF')) content = content.slice(1);
  const lines = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
  const out: IPTVChannel[] = [];
  let pending: PendingEntry | null = null;
  let stickyGroup: string | undefined;
  let autoIndex = 0;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;
    if (line.startsWith('#EXTM3U')) continue;

    if (line.startsWith(EXTINF)) {
      pending = parseExtinf(line.slice(EXTINF.length));
      continue;
    }
    if (line.startsWith(EXTGRP)) {
      const g = line.slice(EXTGRP.length).trim();
      stickyGroup = g || undefined;
      if (pending && g) pending.attrs['group-title'] = g;
      continue;
    }
    if (line.startsWith(EXTVLCOPT)) {
      if (pending) captureVlcOpt(line.slice(EXTVLCOPT.length), pending.attrs);
      continue;
    }
    if (line.startsWith(KODIPROP)) continue;
    if (line.startsWith('#')) continue;

    const pipeIdx = line.indexOf('|');
    const url = pipeIdx >= 0 ? line.slice(0, pipeIdx) : line;

    if (!pending) {
      pending = { title: url, attrs: {} };
    }
    if (pipeIdx >= 0) {
      capturePipeOpts(line.slice(pipeIdx + 1), pending.attrs);
    }

    const attrs = pending.attrs;
    const displayName = nonEmpty(attrs['tvg-name']) || pending.title || `Channel ${autoIndex}`;
    if (isDecorativeRow(displayName)) {
      pending = null;
      continue;
    }

    const tvgId = nonEmpty(attrs['tvg-id']) || nonEmpty(attrs['tvg-chno']) || undefined;
    const idKey = tvgId || nonEmpty(attrs['tvg-name']) || pending.title || `ch-${autoIndex}`;
    const id = `${baseId}::${idKey}::${autoIndex}`;
    const logo = nonEmpty(attrs['tvg-logo']) || nonEmpty(attrs['logo']) || undefined;
    const group = nonEmpty(attrs['group-title']) || nonEmpty(attrs['group']) || stickyGroup || undefined;
    const catchupType = nonEmpty(attrs['catchup']) || nonEmpty(attrs['catchup-type']) || undefined;
    const catchupSource = nonEmpty(attrs['catchup-source']) || undefined;
    const catchupDays = attrs['catchup-days'] ? parseInt(attrs['catchup-days'], 10) || undefined : undefined;
    const headers = buildHeaders(attrs);
    autoIndex++;

    out.push({
      id,
      tvgId,
      name: displayName,
      logo,
      group,
      url,
      catchupType,
      catchupSource,
      catchupDays,
      headers,
    });
    pending = null;
  }
  return out;
}

export function deriveEpgUrls(playlistUrl: string): string[] {
  let url: URL;
  try { url = new URL(playlistUrl); } catch { return []; }
  const path = url.pathname;
  if (!path.endsWith('get.php') && !path.endsWith('player_api.php')) return [];
  const username = url.searchParams.get('username');
  const password = url.searchParams.get('password');
  if (!username || !password) return [];
  const base = `${url.protocol}//${url.host}${url.port ? `:${url.port}` : ''}`;
  const xmltv = new URL(`${base}/xmltv.php`);
  xmltv.searchParams.set('username', username);
  xmltv.searchParams.set('password', password);
  const getPhp = new URL(`${base}/get.php`);
  getPhp.searchParams.set('username', username);
  getPhp.searchParams.set('password', password);
  getPhp.searchParams.set('type', 'epg');
  return [xmltv.toString(), getPhp.toString()];
}
