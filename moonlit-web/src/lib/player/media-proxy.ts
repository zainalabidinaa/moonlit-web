const BLOCKED_FORWARD_HEADERS = new Set([
  'connection',
  'content-length',
  'host',
  'range',
  'transfer-encoding',
]);

export function sanitizeMediaRequestHeaders(value: unknown): Record<string, string> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value as Record<string, unknown>)
    .filter(([name, headerValue]) => (
      typeof headerValue === 'string'
      && headerValue.length <= 8_192
      && !BLOCKED_FORWARD_HEADERS.has(name.toLowerCase())
    )) as [string, string][]);
}

export function buildMediaProxyUrl(url: string, requestHeaders?: Record<string, string>): string {
  const params = new URLSearchParams({ url });
  const headers = sanitizeMediaRequestHeaders(requestHeaders);
  if (Object.keys(headers).length > 0) params.set('headers', JSON.stringify(headers));
  return `/api/media-proxy?${params.toString()}`;
}

export function parseMediaProxyHeaders(value: string | null): Record<string, string> {
  if (!value) return {};
  try { return sanitizeMediaRequestHeaders(JSON.parse(value)); } catch { return {}; }
}
