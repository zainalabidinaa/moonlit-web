import { describe, it, expect } from 'vitest';
import { reduceMpvEvent, initialMpvState, parseTrackList } from './mpv';

describe('reduceMpvEvent', () => {
  it('updates position and duration from property-change events', () => {
    let s = initialMpvState();
    s = reduceMpvEvent(s, { event: 'property-change', name: 'time-pos', data: 42.5 });
    s = reduceMpvEvent(s, { event: 'property-change', name: 'duration', data: 3600 });
    expect(s.position).toBe(42.5);
    expect(s.duration).toBe(3600);
  });

  it('tracks pause, mute, volume, speed', () => {
    let s = initialMpvState();
    s = reduceMpvEvent(s, { event: 'property-change', name: 'pause', data: true });
    s = reduceMpvEvent(s, { event: 'property-change', name: 'mute', data: true });
    s = reduceMpvEvent(s, { event: 'property-change', name: 'volume', data: 55 });
    s = reduceMpvEvent(s, { event: 'property-change', name: 'speed', data: 1.5 });
    expect(s).toMatchObject({ paused: true, muted: true, volume: 55, speed: 1.5 });
  });

  it('marks loaded on file-loaded and ended on end-file eof', () => {
    let s = reduceMpvEvent(initialMpvState(), { event: 'file-loaded' });
    expect(s.loaded).toBe(true);
    s = reduceMpvEvent(s, { event: 'end-file', reason: 'Eof' });
    expect(s.ended).toBe(true);
    expect(s.error).toBeNull();
  });

  it('captures end-file error reason as error', () => {
    const s = reduceMpvEvent(initialMpvState(), { event: 'end-file', reason: 'Error' });
    expect(s.error).toBe('Playback failed');
  });
});

describe('parseTrackList', () => {
  const raw = [
    { id: 1, type: 'video', selected: true, codec: 'hevc' },
    { id: 1, type: 'audio', selected: true, lang: 'eng', title: 'English 5.1', codec: 'eac3' },
    { id: 2, type: 'audio', selected: false, lang: 'jpn', codec: 'aac' },
    { id: 1, type: 'sub', selected: false, lang: 'eng', title: 'Full', external: false },
  ];
  it('splits audio and subtitle tracks with selection state', () => {
    const t = parseTrackList(raw);
    expect(t.audio).toHaveLength(2);
    expect(t.subs).toHaveLength(1);
    expect(t.audio[0]).toMatchObject({ id: 1, lang: 'eng', selected: true });
    expect(t.audio[0].label).toContain('English 5.1');
  });
  it('handles non-array input gracefully', () => {
    expect(parseTrackList(null)).toEqual({ audio: [], subs: [] });
  });
});
