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

export function buildMediaProxyUrl(url: string, requestHeaders?: Record<string, string>): never {
  void url;
  void requestHeaders;
  throw new Error('Media proxy disabled: authenticated opaque proxy sessions are required.');
}

export function parseMediaProxyHeaders(value: string | null): Record<string, string> {
  void value;
  return {};
}
