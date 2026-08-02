import { afterEach, describe, expect, it, vi } from 'vitest';

import handler from './poster-proxy';

describe('poster proxy', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('rejects malformed ids without ever calling fetch', async () => {
    const fetchSpy = vi.fn();
    vi.stubGlobal('fetch', fetchSpy);
    const request = new Request('https://moonlit.example/api/poster-proxy?id=tt-not-real&flags=poster&tag=auto');
    const response = await handler(request);
    expect(response.status).toBe(400);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('rejects a flags value that is not a valid poster-badge suffix', async () => {
    const fetchSpy = vi.fn();
    vi.stubGlobal('fetch', fetchSpy);
    const request = new Request('https://moonlit.example/api/poster-proxy?id=tt1234567&flags=../secrets&tag=auto');
    const response = await handler(request);
    expect(response.status).toBe(400);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('rebuilds the exact btttr.cc URL from validated parts and streams the image through', async () => {
    const fetchSpy = vi.fn(async (url: string) => {
      expect(url).toBe('https://btttr.cc/poster-gq/imdb/poster-default/tt1234567.jpg?tag=auto&rs=IM');
      return new Response('image-bytes', { status: 200, headers: { 'Content-Type': 'image/webp' } });
    });
    vi.stubGlobal('fetch', fetchSpy);
    const request = new Request('https://moonlit.example/api/poster-proxy?id=tt1234567&flags=poster-gq&tag=auto');
    const response = await handler(request);
    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toBe('image/webp');
    expect(response.headers.get('Cache-Control')).toContain('max-age=86400');
    expect(await response.text()).toBe('image-bytes');
  });

  it('never forwards an arbitrary target — only id/flags/tag reach the rebuilt URL', async () => {
    const fetchSpy = vi.fn(async () => new Response('image-bytes', { status: 200, headers: { 'Content-Type': 'image/webp' } }));
    vi.stubGlobal('fetch', fetchSpy);
    const request = new Request('https://moonlit.example/api/poster-proxy?id=tt1234567&flags=poster&tag=auto&url=https://evil.example/steal');
    await handler(request);
    expect(fetchSpy).toHaveBeenCalledWith('https://btttr.cc/poster/imdb/poster-default/tt1234567.jpg?tag=auto&rs=IM', expect.anything());
  });

  it('returns a 502 when the upstream poster request fails', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('not found', { status: 404 })));
    const request = new Request('https://moonlit.example/api/poster-proxy?id=tt1234567&flags=poster&tag=auto');
    const response = await handler(request);
    expect(response.status).toBe(502);
  });

  it('rejects non-GET/HEAD methods', async () => {
    const request = new Request('https://moonlit.example/api/poster-proxy?id=tt1234567&flags=poster&tag=auto', { method: 'POST' });
    const response = await handler(request);
    expect(response.status).toBe(405);
  });
});
