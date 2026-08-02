import { describe, expect, it } from 'vitest';
import { EPGIndex } from './epg-index';
import { EMPTY_NOW_NEXT } from './models';
import type { EPGChannelMeta, EPGProgram, IPTVChannel } from './models';

function makeChannel(overrides: Partial<IPTVChannel> = {}): IPTVChannel {
  return {
    id: 'src-1',
    tvgId: 'tvg-hbo.us',
    name: 'HBO US',
    url: 'https://example.com/stream.m3u8',
    ...overrides,
  };
}

function makeProgram(overrides: Partial<EPGProgram> & { startMs: number; endMs: number }): EPGProgram {
  return {
    channelTvgId: 'tvg-hbo.us',
    title: 'Untitled',
    ...overrides,
  };
}

const hboMeta: Record<string, EPGChannelMeta> = {
  'tvg-hbo.us': { displayName: 'HBO US', icon: 'https://example.com/hbo.png' },
  'tvg-cnn.us': { displayName: 'CNN', icon: 'https://example.com/cnn.png' },
  'tvg-espn.us': { displayName: 'ESPN', icon: undefined },
};

describe('EPGIndex.findCurrent', () => {
  it('returns correct now/next for a program currently airing', () => {
    const programs: EPGProgram[] = [
      makeProgram({ title: 'Show A', startMs: 1000, endMs: 2000 }),
      makeProgram({ title: 'Show B', startMs: 2000, endMs: 3000 }),
      makeProgram({ title: 'Show C', startMs: 3000, endMs: 4000 }),
    ];
    const result = EPGIndex.findCurrent(programs, 2500);
    expect(result.current!.title).toBe('Show B');
    expect(result.next!.title).toBe('Show C');
  });

  it('returns null current when no program is airing but next exists', () => {
    const programs: EPGProgram[] = [
      makeProgram({ title: 'Show A', startMs: 1000, endMs: 2000 }),
      makeProgram({ title: 'Show B', startMs: 5000, endMs: 6000 }),
    ];
    const result = EPGIndex.findCurrent(programs, 3000);
    expect(result.current).toBeNull();
    expect(result.next!.title).toBe('Show B');
  });

  it('returns empty result for undefined or empty array', () => {
    expect(EPGIndex.findCurrent(undefined, 0)).toEqual(EMPTY_NOW_NEXT);
    expect(EPGIndex.findCurrent([], 0)).toEqual(EMPTY_NOW_NEXT);
  });

  it('returns null next when on the last programme', () => {
    const programs: EPGProgram[] = [
      makeProgram({ title: 'Show A', startMs: 1000, endMs: 2000 }),
    ];
    const result = EPGIndex.findCurrent(programs, 1500);
    expect(result.current!.title).toBe('Show A');
    expect(result.next).toBeNull();
  });

  it('handles time before all programmes', () => {
    const programs: EPGProgram[] = [
      makeProgram({ title: 'Show A', startMs: 5000, endMs: 6000 }),
    ];
    const result = EPGIndex.findCurrent(programs, 0);
    expect(result.current).toBeNull();
    expect(result.next!.title).toBe('Show A');
  });

  it('handles time after all programmes', () => {
    const programs: EPGProgram[] = [
      makeProgram({ title: 'Show A', startMs: 1000, endMs: 2000 }),
    ];
    const result = EPGIndex.findCurrent(programs, 5000);
    expect(result.current).toBeNull();
    expect(result.next).toBeNull();
  });
});

describe('EPGIndex.programsFor', () => {
  const programs: EPGProgram[] = [
    makeProgram({ channelTvgId: 'tvg-hbo.us', title: 'HBO Show', startMs: 1000, endMs: 2000 }),
    makeProgram({ channelTvgId: 'tvg-cnn.us', title: 'CNN Show', startMs: 1000, endMs: 2000 }),
  ];

  function makeIndex(progs: EPGProgram[] = programs, meta = hboMeta): EPGIndex {
    return new EPGIndex(progs, meta);
  }

  it('finds by tvg-id', () => {
    const index = makeIndex();
    const ch = makeChannel({ tvgId: 'tvg-hbo.us' });
    const result = index.programsFor(ch);
    expect(result).toHaveLength(1);
    expect(result![0].title).toBe('HBO Show');
  });

  it('falls back to name matching when tvg-id not found', () => {
    const index = makeIndex();
    const ch = makeChannel({ tvgId: undefined, name: 'HBO US' });
    const result = index.programsFor(ch);
    expect(result).toHaveLength(1);
    expect(result![0].title).toBe('HBO Show');
  });

  it('returns undefined when no match found', () => {
    const index = makeIndex();
    const ch = makeChannel({ tvgId: undefined, name: 'Unknown Channel' });
    expect(index.programsFor(ch)).toBeUndefined();
  });

  it('uses override mapping when provided', () => {
    const index = makeIndex();
    const ch = makeChannel({ tvgId: 'tvg-hbo.us', name: 'HBO US' });
    const result = index.programsFor(ch, { 'src-1': 'tvg-cnn.us' });
    expect(result).toHaveLength(1);
    expect(result![0].title).toBe('CNN Show');
  });

  it('override has priority over tvg-id', () => {
    const index = makeIndex();
    const ch = makeChannel({ tvgId: 'tvg-hbo.us' });
    const result = index.programsFor(ch, { 'src-1': 'tvg-cnn.us' });
    expect(result![0].title).toBe('CNN Show');
  });
});

describe('EPGIndex.nameKey', () => {
  it('normalizes case to lowercase', () => {
    expect(EPGIndex.nameKey('HBO')).toBe('hbo');
  });

  it('strips spaces', () => {
    expect(EPGIndex.nameKey('HBO  US')).toBe('hbous');
  });

  it('strips special characters', () => {
    expect(EPGIndex.nameKey('HBO-HD (US)')).toBe('hbohdus');
  });

  it('keeps digits', () => {
    expect(EPGIndex.nameKey('Channel 5 HD')).toBe('channel5hd');
  });
});

describe('EPGIndex.nowNextFor', () => {
  it('returns now/next using current time', () => {
    const now = new Date();
    const past = now.getTime() - 3600_000;
    const future1 = now.getTime() + 3600_000;
    const future2 = now.getTime() + 7200_000;

    const programs: EPGProgram[] = [
      makeProgram({ title: 'Past Show', startMs: past, endMs: future1, channelTvgId: 'tvg-hbo.us' }),
      makeProgram({ title: 'Next Show', startMs: future1, endMs: future2, channelTvgId: 'tvg-hbo.us' }),
    ];
    const index = new EPGIndex(programs, hboMeta);
    const ch = makeChannel({ tvgId: 'tvg-hbo.us' });
    const result = index.nowNextFor(ch, now);
    expect(result.current!.title).toBe('Past Show');
    expect(result.next!.title).toBe('Next Show');
  });

  it('uses current Date when at is not provided', () => {
    const programs: EPGProgram[] = [
      makeProgram({ title: 'Show', startMs: 0, endMs: 9e15, channelTvgId: 'tvg-hbo.us' }),
    ];
    const index = new EPGIndex(programs, hboMeta);
    const ch = makeChannel({ tvgId: 'tvg-hbo.us' });
    const result = index.nowNextFor(ch);
    expect(result.current!.title).toBe('Show');
  });
});

describe('EPGIndex.from', () => {
  it('creates index from parse result', () => {
    const index = EPGIndex.from({
      programs: [
        makeProgram({ channelTvgId: 'tvg-hbo.us', title: 'HBO Show', startMs: 1000, endMs: 2000 }),
      ],
      channelMeta: hboMeta,
    });
    expect(index.isEmpty).toBe(false);
    expect(index.byChannel['tvg-hbo.us']).toHaveLength(1);
  });

  it('reports isEmpty true for empty data', () => {
    const index = EPGIndex.from({ programs: [], channelMeta: {} });
    expect(index.isEmpty).toBe(true);
  });
});
