import { describe, it, expect } from 'vitest';
import { sortStreamsForDesktop, pickDesktopStream } from './desktop-selection';
import type { StreamItem } from '@/lib/types';

const s = (over: Partial<StreamItem>): StreamItem => ({ name: 'x', ...over });

describe('sortStreamsForDesktop', () => {
  it('drops streams without a playable URL', () => {
    const out = sortStreamsForDesktop([s({ }), s({ url: 'http://a/1.mkv' })], false);
    expect(out).toHaveLength(1);
    expect(out[0].url).toBe('http://a/1.mkv');
  });
  it('ranks 4K first when prefer4K, else 1080p first', () => {
    const streams = [
      s({ url: 'http://a/1080.mkv', title: '1080p BluRay' }),
      s({ url: 'http://a/2160.mkv', title: '4K 2160p REMUX' }),
    ];
    expect(sortStreamsForDesktop(streams, true)[0].url).toContain('2160');
    expect(sortStreamsForDesktop(streams, false)[0].url).toContain('1080');
  });
});

describe('pickDesktopStream', () => {
  it('prefers the last-played url when present', () => {
    const streams = [s({ url: 'http://a/1' }), s({ url: 'http://a/2' })];
    expect(pickDesktopStream(streams, 'http://a/2')?.url).toBe('http://a/2');
  });
  it('falls back to first sorted stream', () => {
    const streams = [s({ url: 'http://a/1' })];
    expect(pickDesktopStream(streams, null)?.url).toBe('http://a/1');
  });
  it('returns null on empty list', () => {
    expect(pickDesktopStream([], 'http://a')).toBeNull();
  });
});
