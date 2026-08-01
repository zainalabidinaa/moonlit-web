import { afterEach, describe, expect, it, vi } from 'vitest';

import handler from './media-proxy';

describe('disabled media proxy security boundary', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('never fetches an arbitrary target or accepts credential-bearing query parameters', async () => {
    const fetchSpy = vi.fn(async () => new Response('private metadata'));
    vi.stubGlobal('fetch', fetchSpy);
    const request = new Request(
      'https://moonlit.example/api/media-proxy?url=http%3A%2F%2F169.254.169.254%2Flatest%2Fmeta-data&headers=%7B%22Authorization%22%3A%22Bearer%20secret%22%7D',
    );

    const response = await handler(request);

    expect(response.status).toBe(410);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
