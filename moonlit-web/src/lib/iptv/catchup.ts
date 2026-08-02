import type { CatchupType, IPTVChannel } from './models';

const XTREAM_LIVE_PATTERN = /^(https?:\/\/[^/]+)\/(?:live\/)?([^/]+)\/([^/]+)\/(\d+)\.(\w+)(?:\?|$)/;

export function detectCatchupType(channel: IPTVChannel): CatchupType | null {
  const raw = (channel.catchupType ?? '').toLowerCase().trim();
  switch (raw) {
    case 'flussonic':
    case 'fs':
      return 'flussonic';
    case 'xc':
    case 'xtream':
      return 'xtream';
    case 'append':
      return 'append';
    case 'shift':
    case 'timeshift':
      return 'shift';
    case 'default':
      return 'default';
  }
  if (channel.catchupSource) return 'default';
  if (XTREAM_LIVE_PATTERN.test(channel.url)) return 'xtream';
  return null;
}

export function channelHasCatchup(channel: IPTVChannel): boolean {
  return detectCatchupType(channel) !== null;
}

function strftime(fmt: string, date: Date): string {
  const utc = {
    Y: date.getUTCFullYear().toString(),
    m: String(date.getUTCMonth() + 1).padStart(2, '0'),
    d: String(date.getUTCDate()).padStart(2, '0'),
    H: String(date.getUTCHours()).padStart(2, '0'),
    M: String(date.getUTCMinutes()).padStart(2, '0'),
    S: String(date.getUTCSeconds()).padStart(2, '0'),
  };
  return fmt
    .replace(/Y/g, utc.Y)
    .replace(/m/g, utc.m)
    .replace(/d/g, utc.d)
    .replace(/H/g, utc.H)
    .replace(/M/g, utc.M)
    .replace(/S/g, utc.S);
}

function fillTemplate(tpl: string, startSec: number, endSec: number, nowSec: number, duration: number): string {
  const offset = Math.max(0, nowSec - startSec);
  const startDate = new Date(startSec * 1000);

  let out = tpl;
  out = out.replace(/\$\{(?:start|utc):([^}]+)\}/gi, (_, fmt) => strftime(fmt, startDate));
  out = out.replace(/\{(?:utc|start):([^}]+)\}/gi, (_, fmt) => strftime(fmt, startDate));

  const map: Record<string, string> = {
    start: String(startSec), utc: String(startSec), timestamp: String(startSec),
    end: String(endSec), utcend: String(endSec),
    now: String(nowSec), lutc: String(nowSec), timenow: String(nowSec),
    duration: String(duration), dur: String(duration),
    offset: String(offset),
    'duration-minutes': String(Math.ceil(duration / 60)),
  };

  out = out.replace(/\$\{(\w[\w-]*)\}/gi, (_, key: string) => map[key.toLowerCase()] ?? `\${${key}}`);
  out = out.replace(/\{(\w[\w-]*)\}/gi, (_, key: string) => map[key.toLowerCase()] ?? `{${key}}`);

  return out;
}

function flussonicURL(base: string, start: number, duration: number): string | undefined {
  const q = base.indexOf('?');
  const path = q >= 0 ? base.slice(0, q) : base;
  const query = q >= 0 ? base.slice(q) : '';

  const match = /^(.*)\/([^/]+)\.(m3u8|ts|mpd)$/i.exec(path);
  if (match) {
    const dir = match[1];
    const file = match[2];
    const ext = match[3];
    const stem = (file === 'mpegts' || file === 'mono') ? 'index' : file;
    return `${dir}/${stem}-${start}-${duration}.${ext}${query}`;
  }
  const trimmed = path.replace(/\/+$/, '');
  return `${trimmed}/archive-${start}-${duration}.ts${query}`;
}

export function buildCatchupURL(
  channel: IPTVChannel,
  startMs: number,
  endMs: number,
  nowMs: number = Date.now(),
): string | undefined {
  const type = detectCatchupType(channel);
  if (!type) return undefined;
  const startSec = Math.floor(startMs / 1000);
  const endSec = Math.floor(endMs / 1000);
  const nowSec = Math.floor(nowMs / 1000);
  const duration = Math.max(60, endSec - startSec);

  switch (type) {
    case 'flussonic': {
      return flussonicURL(channel.url, startSec, duration);
    }
    case 'xtream': {
      const m = XTREAM_LIVE_PATTERN.exec(channel.url);
      if (!m) return undefined;
      const host = m[1], user = m[2], pass = m[3], id = m[4];
      const mins = Math.ceil(duration / 60);
      const stamp = strftime('Y-m-d:H-M', new Date(startSec * 1000));
      return `${host}/timeshift/${user}/${pass}/${mins}/${stamp}/${id}.ts`;
    }
    case 'default':
    case 'append':
    case 'shift': {
      if (channel.catchupSource) {
        const src = channel.catchupSource;
        if (/^https?:\/\//i.test(src)) {
          return fillTemplate(src, startSec, endSec, nowSec, duration);
        }
        const filled = fillTemplate(src, startSec, endSec, nowSec, duration);
        if (src.startsWith('?') || src.startsWith('&')) {
          return channel.url + filled;
        }
        const sep = channel.url.includes('?') ? '&' : '?';
        return channel.url + sep + filled;
      }
      const sep = channel.url.includes('?') ? '&' : '?';
      return `${channel.url}${sep}utc=${startSec}&lutc=${nowSec}`;
    }
  }
  return undefined;
}
