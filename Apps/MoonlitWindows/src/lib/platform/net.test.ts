import { describe, it, expect } from 'vitest';
import { stremioUpstreamUrl } from './net';

describe('stremioUpstreamUrl', () => {
  const base = 'https://addon.example.com';

  it('builds manifest url, normalizing trailing manifest.json', () => {
    expect(stremioUpstreamUrl('manifest', { url: `${base}/manifest.json` })).toBe(`${base}/manifest.json`);
    expect(stremioUpstreamUrl('manifest', { url: base })).toBe(`${base}/manifest.json`);
  });

  it('builds catalog url without extras', () => {
    expect(stremioUpstreamUrl('catalog', { url: base, type: 'movie', id: 'top' }))
      .toBe(`${base}/catalog/movie/top.json`);
  });

  it('builds catalog url with encoded extras', () => {
    expect(stremioUpstreamUrl('catalog', { url: base, type: 'movie', id: 'top', extras: { genre: 'Sci-Fi', skip: '20' } }))
      .toBe(`${base}/catalog/movie/top/genre=Sci-Fi&skip=20.json`);
  });

  it('builds stream/meta/subtitles urls and strips manifest suffix from base', () => {
    expect(stremioUpstreamUrl('stream', { url: `${base}/manifest.json`, type: 'series', id: 'tt1:1:2' }))
      .toBe(`${base}/stream/series/tt1:1:2.json`);
    expect(stremioUpstreamUrl('meta', { url: `${base}/`, type: 'movie', id: 'tt2' }))
      .toBe(`${base}/meta/movie/tt2.json`);
    expect(stremioUpstreamUrl('subtitles', { url: base, type: 'movie', id: 'tt3' }))
      .toBe(`${base}/subtitles/movie/tt3.json`);
  });
});
