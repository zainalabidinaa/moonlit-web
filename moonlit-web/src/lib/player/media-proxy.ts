const SOURCE_HEADER_ALLOWLIST = new Set(['authorization']);

export function sanitizeSourceRequestHeaders(value: unknown): Record<string, string> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value as Record<string, unknown>)
    .filter(([name, headerValue]) => (
      typeof headerValue === 'string'
      && headerValue.length <= 4_096
      && SOURCE_HEADER_ALLOWLIST.has(name.toLowerCase())
    )) as [string, string][]);
}

export function sanitizeMediaRequestHeaders(value: unknown): Record<string, string> {
  return sanitizeSourceRequestHeaders(value);
}

export function headersForExactOrigin(
  value: unknown,
  sourceUrl: string,
  requestUrl: string,
): Record<string, string> {
  try {
    const source = new URL(sourceUrl);
    const request = new URL(requestUrl, source);
    if (!['http:', 'https:'].includes(source.protocol) || request.origin !== source.origin) return {};
    return sanitizeSourceRequestHeaders(value);
  } catch {
    return {};
  }
}

let _sessionId: string | null = null;
let _sessionTarget: string | null = null;
let _sessionCreatedAt = 0;

const SESSION_TTL_MS = 3_300_000;

export async function ensureProxySession(
  targetUrl: string,
  requestHeaders?: Record<string, string>,
): Promise<string | null> {
  if (_sessionId && _sessionTarget === targetUrl && Date.now() - _sessionCreatedAt < SESSION_TTL_MS) {
    return _sessionId;
  }
  try {
    const proxyBase = window.location.origin;
    const resp = await fetch(`${proxyBase}/api/media-proxy/session`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ target: targetUrl, headers: requestHeaders ?? {} }),
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    _sessionId = data.session;
    _sessionTarget = targetUrl;
    _sessionCreatedAt = Date.now();
    return _sessionId;
  } catch {
    return null;
  }
}

export function buildMediaProxyUrl(url: string, sessionId: string): string {
  const proxyBase = typeof window !== 'undefined' ? window.location.origin : '';
  return `${proxyBase}/api/media-proxy?session=${encodeURIComponent(sessionId)}&url=${encodeURIComponent(url)}`;
}

export function parseMediaProxyHeaders(value: string | null): Record<string, string> {
  if (!value) return {};
  try {
    return JSON.parse(value);
  } catch {
    return {};
  }
}
