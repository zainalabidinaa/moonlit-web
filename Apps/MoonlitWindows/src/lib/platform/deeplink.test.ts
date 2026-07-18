import { describe, it, expect } from 'vitest';
import { parseMoonlitUrl } from './deeplink';

describe('parseMoonlitUrl', () => {
  it('parses action and params from a trakt callback', () => {
    const result = parseMoonlitUrl('moonlit://trakt-callback?code=abc123&state=xyz');
    expect(result).toEqual({
      action: 'trakt-callback',
      params: { code: 'abc123', state: 'xyz' },
    });
  });

  it('returns null for non-moonlit schemes', () => {
    expect(parseMoonlitUrl('https://example.com')).toBeNull();
  });

  it('returns null for malformed input', () => {
    expect(parseMoonlitUrl('not a url')).toBeNull();
  });

  it('returns null when there is no host (aligns with Rust parser)', () => {
    expect(parseMoonlitUrl('moonlit:///orphan-path')).toBeNull();
    expect(parseMoonlitUrl('moonlit:opaque-form')).toBeNull();
  });
});
