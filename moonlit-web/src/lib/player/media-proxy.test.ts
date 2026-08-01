import { describe, expect, it } from 'vitest';

import { buildMediaProxyUrl, parseMediaProxyHeaders } from './media-proxy';

describe('legacy media proxy client surface', () => {
  it('cannot serialize credentials or arbitrary targets into a proxy URL', () => {
    expect(() => buildMediaProxyUrl('http://169.254.169.254/latest', {
      Authorization: 'Bearer secret',
      Cookie: 'session=secret',
    })).toThrow(/disabled/i);
  });

  it('does not deserialize caller-controlled forwarding headers', () => {
    expect(parseMediaProxyHeaders('{"Authorization":"Bearer secret"}')).toEqual({});
  });
});
