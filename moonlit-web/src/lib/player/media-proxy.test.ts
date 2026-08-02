import { describe, expect, it } from 'vitest';

import { buildMediaProxyUrl, parseMediaProxyHeaders } from './media-proxy';

describe('media proxy client surface', () => {
  it('builds a session-scoped proxy URL', () => {
    const url = buildMediaProxyUrl('https://example.com/stream.ts', 'session-123');
    expect(url).toContain('/api/media-proxy');
    expect(url).toContain('session-123');
    expect(url).toContain(encodeURIComponent('https://example.com/stream.ts'));
  });

  it('decodes valid forwarded headers', () => {
    const headers = parseMediaProxyHeaders('{"User-Agent":"VLC/3.0"}');
    expect(headers).toEqual({ 'User-Agent': 'VLC/3.0' });
  });

  it('returns empty for null or invalid input', () => {
    expect(parseMediaProxyHeaders(null)).toEqual({});
    expect(parseMediaProxyHeaders('not-json')).toEqual({});
    expect(parseMediaProxyHeaders('')).toEqual({});
  });
});
