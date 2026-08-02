import { afterEach, describe, expect, it, vi } from 'vitest';

import handler from './media-proxy';

describe('media proxy security boundary', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('returns 400 for missing session and url params', async () => {
    const request = new Request('https://moonlit.example/api/media-proxy');
    const response = await handler(request);
    expect(response.status).toBe(400);
  });

  it('returns 401 for expired or missing session', async () => {
    const request = new Request(
      'https://moonlit.example/api/media-proxy?session=fake-session&url=https%3A%2F%2Fexample.com%2Fstream.ts',
    );
    const response = await handler(request);
    expect(response.status).toBe(401);
  });

  it('rejects private IP targets when creating a session', async () => {
    const fetchSpy = vi.fn(async () => new Response('private metadata'));
    vi.stubGlobal('fetch', fetchSpy);
    const request = new Request(
      'https://moonlit.example/api/media-proxy/session',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target: 'http://169.254.169.254/latest/meta-data' }),
      },
    );

    const response = await handler(request);
    expect(response.status).toBe(403);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('rejects non-http/https targets', async () => {
    const request = new Request(
      'https://moonlit.example/api/media-proxy/session',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target: 'file:///etc/passwd' }),
      },
    );

    const response = await handler(request);
    expect(response.status).toBe(400);
  });

  it('rejects localhost targets', async () => {
    const request = new Request(
      'https://moonlit.example/api/media-proxy/session',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target: 'http://localhost:3000/admin' }),
      },
    );

    const response = await handler(request);
    expect(response.status).toBe(403);
  });

  it('rejects private IP targets on direct proxy requests', async () => {
    const fetchSpy = vi.fn(async () => new Response('private metadata'));
    vi.stubGlobal('fetch', fetchSpy);
    const request = new Request(
      'https://moonlit.example/api/media-proxy?url=http%3A%2F%2F169.254.169.254%2Flatest%2Fmeta-data',
    );

    const response = await handler(request);
    expect(response.status).toBe(403);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('forwards simple proxy requests without a session', async () => {
    const fetchSpy = vi.fn(async () =>
      new Response('stream data', { status: 200, headers: { 'Content-Type': 'video/mp4' } }),
    );
    vi.stubGlobal('fetch', fetchSpy);
    const request = new Request(
      'https://moonlit.example/api/media-proxy?url=https%3A%2F%2Fexample.com%2Fstream.mp4',
    );

    const response = await handler(request);
    expect(response.status).toBe(200);
    expect(fetchSpy).toHaveBeenCalledWith(
      expect.stringContaining('example.com'),
      expect.objectContaining({ method: 'GET' }),
    );
  });
});
