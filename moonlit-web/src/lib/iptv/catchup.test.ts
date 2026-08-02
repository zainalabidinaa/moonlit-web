import { describe, expect, it } from 'vitest';
import { buildCatchupURL, channelHasCatchup, detectCatchupType } from './catchup';
import type { IPTVChannel } from './models';

function makeChannel(overrides: Partial<IPTVChannel> = {}): IPTVChannel {
  return {
    id: 'ch1',
    name: 'Test Channel',
    url: 'https://example.com/stream/1.m3u8',
    ...overrides,
  };
}

describe('detectCatchupType', () => {
  it("returns 'xtream' for a channel with catchupType='xc'", () => {
    expect(detectCatchupType(makeChannel({ catchupType: 'xc' }))).toBe('xtream');
  });

  it("returns 'flussonic' for catchupType='flussonic'", () => {
    expect(detectCatchupType(makeChannel({ catchupType: 'flussonic' }))).toBe('flussonic');
  });

  it("returns 'default' when catchupSource is set but no catchupType", () => {
    expect(detectCatchupType(makeChannel({ catchupSource: '?utc={utc}' }))).toBe('default');
  });

  it('returns null for channel with no catchup config', () => {
    expect(detectCatchupType(makeChannel())).toBeNull();
  });

  it("returns 'xtream' when URL matches xtream live pattern even without catchupType", () => {
    expect(
      detectCatchupType(
        makeChannel({ url: 'https://tv.example.com/live/user/pass/42.ts', catchupType: undefined }),
      ),
    ).toBe('xtream');
  });
});

describe('channelHasCatchup', () => {
  it('returns true when channel has catchup config', () => {
    expect(channelHasCatchup(makeChannel({ catchupType: 'xc' }))).toBe(true);
  });

  it('returns false when channel has no catchup config', () => {
    expect(channelHasCatchup(makeChannel())).toBe(false);
  });
});

describe('buildCatchupURL', () => {
  it('builds correct timeshift URL for xtream type', () => {
    const channel = makeChannel({
      url: 'https://tv.example.com/live/user/pass/42.ts',
      catchupType: 'xc',
    });
    const result = buildCatchupURL(channel, 1700000000000, 1700003600000);
    expect(result).toMatch(/^https:\/\/tv\.example\.com\/timeshift\/user\/pass\/60\/\d{4}-\d{2}-\d{2}:\d{2}-\d{2}\/42\.ts$/);
  });

  it('builds archive URL for flussonic type', () => {
    const channel = makeChannel({
      url: 'https://tv.example.com/stream/playlist.m3u8',
      catchupType: 'flussonic',
    });
    const result = buildCatchupURL(channel, 1700000000000, 1700003600000);
    expect(result).toBe('https://tv.example.com/stream/playlist-1700000000-3600.m3u8');
  });

  it("substitutes template variables like ${start} and {utc} in catchup-source", () => {
    const channel = makeChannel({
      url: 'https://tv.example.com/stream/1.m3u8',
      catchupType: 'default',
      catchupSource: 'https://archive.example.com/${start}/record.ts?t={utc}',
    });
    const result = buildCatchupURL(channel, 1700000000000, 1700003600000);
    expect(result).toBe('https://archive.example.com/1700000000/record.ts?t=1700000000');
  });

  it('substitutes ${duration} variable in catchup-source', () => {
    const channel = makeChannel({
      url: 'https://tv.example.com/stream/1.m3u8',
      catchupType: 'default',
      catchupSource: 'https://archive.example.com/${duration}/chunk.ts',
    });
    const result = buildCatchupURL(channel, 1700000000000, 1700003600000);
    expect(result).toBe('https://archive.example.com/3600/chunk.ts');
  });

  it('appends relative catchup-source to channel URL', () => {
    const channel = makeChannel({
      url: 'https://tv.example.com/stream/1.m3u8',
      catchupType: 'default',
      catchupSource: '?play={utc}',
    });
    const result = buildCatchupURL(channel, 1700000000000, 1700003600000);
    expect(result).toBe('https://tv.example.com/stream/1.m3u8?play=1700000000');
  });

  it('returns undefined for channel without catchup', () => {
    expect(buildCatchupURL(makeChannel(), 1700000000000, 1700003600000)).toBeUndefined();
  });
});
