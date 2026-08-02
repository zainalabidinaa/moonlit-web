import { describe, expect, it } from 'vitest';
import {
  credsFromSource,
  detectSource,
  middlewareCandidates,
} from './source-detector';
import type { IPTVPlaylistSource } from './models';

function makeSource(overrides: Partial<IPTVPlaylistSource> = {}): IPTVPlaylistSource {
  return {
    id: 'src1',
    name: 'Test Source',
    url: 'https://tv.example.com/get.php?username=user&password=pass',
    kind: 'm3u',
    createdAt: 1700000000000,
    ...overrides,
  };
}

describe('detectSource', () => {
  it('returns m3u shape for m3u kind with valid URL', () => {
    const source = makeSource({ url: 'https://tv.example.com/playlist.m3u' });
    const result = detectSource(source);
    expect(result).toMatchObject({ kind: 'm3u', url: 'https://tv.example.com/playlist.m3u' });
  });

  it('returns xtream shape for xtream kind with valid credentials', () => {
    const source = makeSource({
      kind: 'xtream',
      url: 'https://tv.example.com/',
      xtream: { server: 'https://tv.example.com', username: 'user', password: 'pass' },
    });
    const result = detectSource(source);
    expect(result).toMatchObject({ kind: 'xtream', creds: { base: 'https://tv.example.com', username: 'user', password: 'pass' } });
  });

  it('returns invalid for xtream kind with incomplete credentials', () => {
    const source = makeSource({
      kind: 'xtream',
      url: '',
      xtream: { server: '', username: '', password: '' },
    });
    expect(detectSource(source)).toMatchObject({ kind: 'invalid' });
  });

  it('returns epg shape for epg kind', () => {
    const source = makeSource({
      kind: 'epg',
      url: 'https://tv.example.com/epg.xml',
      epgUrl: 'https://tv.example.com/epg.xml',
    });
    expect(detectSource(source)).toMatchObject({ kind: 'epg', url: 'https://tv.example.com/epg.xml' });
  });

  it('returns invalid for invalid URL', () => {
    const source = makeSource({ url: 'not-a-url' });
    expect(detectSource(source)).toMatchObject({ kind: 'invalid' });
  });
});

describe('credsFromSource', () => {
  it('extracts from explicit xtream field', () => {
    const source = makeSource({
      xtream: { server: 'https://tv.example.com', username: 'user1', password: 'pass1' },
    });
    expect(credsFromSource(source)).toMatchObject({
      base: 'https://tv.example.com',
      username: 'user1',
      password: 'pass1',
    });
  });

  it('extracts from get.php URL params', () => {
    const source = makeSource({
      url: 'https://tv.example.com/get.php?username=testuser&password=testpass',
    });
    expect(credsFromSource(source)).toMatchObject({
      base: 'https://tv.example.com',
      username: 'testuser',
      password: 'testpass',
    });
  });

  it('returns null when neither xtream field nor get.php URL has creds', () => {
    const source = makeSource({ url: 'https://tv.example.com/playlist.m3u' });
    expect(credsFromSource(source)).toBeNull();
  });
});

describe('middlewareCandidates', () => {
  it('generates fallback URLs for middleware URLs', () => {
    const result = middlewareCandidates('https://tv.example.com/get.php?username=user&password=pass');
    expect(result).toContain('https://tv.example.com/iptv/m3u');
  });

  it('generates candidates for direct .m3u URLs', () => {
    const result = middlewareCandidates('https://tv.example.com/playlist.m3u');
    expect(result).toEqual([
      'https://tv.example.com/iptv/m3u',
      'https://tv.example.com/m3u',
      'https://tv.example.com/get.php?type=m3u_plus',
    ]);
  });
});
