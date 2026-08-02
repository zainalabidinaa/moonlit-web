import type { EPGChannelMeta, EPGParseResult, EPGProgram } from './models';

export class XtreamError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'XtreamError';
  }
}

function attrValue(s: string, name: string): string | undefined {
  const needle = `${name}="`;
  let idx = 0;
  while (idx < s.length) {
    const pos = s.indexOf(needle, idx);
    if (pos < 0) return undefined;
    if (pos > 0) {
      const prev = s[pos - 1];
      if (prev !== ' ' && prev !== '\t' && prev !== '\n' && prev !== '\r') {
        idx = pos + needle.length;
        continue;
      }
    }
    const q = s.indexOf('"', pos + needle.length);
    if (q < 0) return undefined;
    return s.slice(pos + needle.length, q);
  }
  return undefined;
}

function childText(block: string, tag: string): string | undefined {
  const open = block.indexOf(`<${tag}`);
  if (open < 0) return undefined;
  const openClose = block.indexOf('>', open + tag.length + 1);
  if (openClose < 0) return undefined;
  const close = block.indexOf(`</${tag}>`, openClose + 1);
  if (close < 0) return undefined;
  const raw = block.slice(openClose + 1, close);
  const decoded = decode(stripCdata(raw)).trim();
  return decoded || undefined;
}

function childAttr(block: string, tag: string, attrName: string): string | undefined {
  const open = block.indexOf(`<${tag}`);
  if (open < 0) return undefined;
  const openClose = block.indexOf('>', open + tag.length + 1);
  if (openClose < 0) return undefined;
  return attrValue(block.slice(open, openClose), attrName);
}

function stripCdata(s: string): string {
  if (!s.includes('<![CDATA[')) return s;
  let result = s;
  while (true) {
    const open = result.indexOf('<![CDATA[');
    if (open < 0) break;
    const close = result.indexOf(']]>', open + 9);
    if (close < 0) break;
    result = result.slice(0, open) + result.slice(open + 9, close) + result.slice(close + 3);
  }
  return result;
}

function decode(s: string): string {
  if (!s.includes('&')) return s;
  let r = s;
  r = r.replace(/&lt;/g, '<');
  r = r.replace(/&gt;/g, '>');
  r = r.replace(/&quot;/g, '"');
  r = r.replace(/&apos;/g, '\'');
  r = decodeNumericEntities(r);
  r = r.replace(/&amp;/g, '&');
  return r;
}

function decodeNumericEntities(s: string): string {
  if (!s.includes('&#')) return s;
  let result = '';
  let i = 0;
  while (i < s.length) {
    if (s[i] === '&' && s[i + 1] === '#') {
      const semi = s.indexOf(';', i + 2);
      if (semi >= 0) {
        let numStr = s.slice(i + 2, semi);
        let radix = 10;
        if (numStr.startsWith('x') || numStr.startsWith('X')) {
          radix = 16;
          numStr = numStr.slice(1);
        }
        const code = parseInt(numStr, radix);
        if (!isNaN(code) && code > 0) {
          result += String.fromCodePoint(code);
          i = semi + 1;
          continue;
        }
      }
    }
    result += s[i];
    i++;
  }
  return result;
}

export function parseXmltvTime(raw: string): number {
  const s = raw.trim();
  if (s.length < 14) return NaN;

  function digits(start: number, end: number): number | null {
    if (end > s.length) return null;
    let v = 0;
    for (let i = start; i < end; i++) {
      const c = s.charCodeAt(i);
      if (c < 48 || c > 57) return null;
      v = v * 10 + (c - 48);
    }
    return v;
  }

  const y = digits(0, 4);
  const mo = digits(4, 6);
  const d = digits(6, 8);
  const h = digits(8, 10);
  const mi = digits(10, 12);
  const sec = digits(12, 14);
  if (y == null || mo == null || d == null || h == null || mi == null || sec == null) return NaN;

  let offsetMin = 0;
  let idx = 14;
  while (idx < s.length && s.charCodeAt(idx) === 32) idx++;
  if (idx < s.length && (s[idx] === '+' || s[idx] === '-')) {
    const sign = s[idx] === '-' ? -1 : 1;
    const hh = digits(idx + 1, idx + 3);
    const mm = digits(idx + 3, idx + 5);
    if (hh != null && mm != null) offsetMin = sign * (hh * 60 + mm);
  }

  const date = new Date(Date.UTC(y, mo - 1, d, h, mi, sec));
  return date.getTime() - offsetMin * 60_000;
}

function parseChannel(block: string, channelMeta: Record<string, EPGChannelMeta>): void {
  const id = attrValue(block, 'id');
  if (!id) return;
  const displayName = childText(block, 'display-name') || undefined;
  const icon = childAttr(block, 'icon', 'src') || undefined;
  if (channelMeta[id] && !displayName && !icon) return;
  channelMeta[id] = { displayName, icon };
}

function parseProgramme(block: string): EPGProgram | undefined {
  const start = attrValue(block, 'start');
  const stop = attrValue(block, 'stop');
  const channel = attrValue(block, 'channel');
  if (!start || !stop || !channel) return undefined;
  const startMs = parseXmltvTime(start);
  const endMs = parseXmltvTime(stop);
  if (isNaN(startMs) || isNaN(endMs) || endMs <= startMs) return undefined;
  return {
    channelTvgId: channel,
    title: childText(block, 'title') || 'Untitled',
    description: childText(block, 'desc') || undefined,
    category: childText(block, 'category') || undefined,
    iconUrl: childAttr(block, 'icon', 'src') || undefined,
    startMs,
    endMs,
  };
}

export function parseXMLTV(text: string): EPGParseResult {
  const programs: EPGProgram[] = [];
  const channelMeta: Record<string, EPGChannelMeta> = {};

  let cursor = 0;
  while (cursor < text.length) {
    const chIdx = text.indexOf('<channel ', cursor);
    const prIdx = text.indexOf('<programme', cursor);
    if (chIdx < 0 && prIdx < 0) break;

    const channelFirst = chIdx >= 0 && (prIdx < 0 || chIdx < prIdx);

    if (channelFirst) {
      const close = text.indexOf('</channel>', chIdx);
      if (close < 0) break;
      parseChannel(text.slice(chIdx, close + 10), channelMeta);
      cursor = close + 10;
    } else {
      const openClose = text.indexOf('>', prIdx);
      if (openClose < 0) break;
      const endTag = text.indexOf('</programme>', openClose);
      if (endTag < 0) break;
      const program = parseProgramme(text.slice(prIdx, endTag + 12));
      if (program) programs.push(program);
      cursor = endTag + 12;
    }
  }

  return { programs, channelMeta };
}

export async function fetchAndParseXMLTV(urlString: string): Promise<EPGParseResult> {
  let url: URL;
  try { url = new URL(urlString); } catch { throw new XtreamError(`Invalid EPG URL: ${urlString}`); }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);
  try {
    const response = await fetch(url.toString(), {
      headers: {
        'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
        'Accept': 'application/xml, text/xml, application/octet-stream, */*',
      },
      signal: controller.signal,
    });
    if (!response.ok) throw new XtreamError(`EPG fetch failed: HTTP ${response.status}`);
    const contentType = response.headers.get('content-type') || '';
    let arrayBuffer: ArrayBuffer | undefined;
    if (urlString.endsWith('.gz') || urlString.endsWith('.xml.gz') || contentType.includes('gzip')) {
      arrayBuffer = await response.arrayBuffer();
      const decompressed = await decompressGzip(arrayBuffer);
      return parseXMLTV(new TextDecoder().decode(decompressed));
    }
    const text = await response.text();
    return parseXMLTV(text);
  } catch (err) {
    if (err instanceof XtreamError) throw err;
    throw new XtreamError(err instanceof Error ? err.message : 'Network error');
  } finally {
    clearTimeout(timeout);
  }
}

async function decompressGzip(buffer: ArrayBuffer): Promise<Uint8Array> {
  const ds = new DecompressionStream('gzip');
  const writer = ds.writable.getWriter();
  const reader = ds.readable.getReader();
  writer.write(buffer);
  writer.close();
  const chunks: Uint8Array[] = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }
  const totalLength = chunks.reduce((sum, c) => sum + c.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const c of chunks) {
    result.set(c, offset);
    offset += c.length;
  }
  return result;
}
