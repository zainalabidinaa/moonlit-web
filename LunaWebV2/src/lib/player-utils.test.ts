import { describe, expect, it } from 'vitest';

import { StreamItem } from './types';
import {
  getFallbackSourceType,
  formatContinueWatchingTitle,
  getPlayableStreamUrl,
  getStreamUrl,
  getInitialSourceType,
  streamMatchesUrl,
} from './player-utils';

describe('player utils', () => {
  it('detects HLS streams from m3u8 URLs', () => {
    expect(getInitialSourceType('https://example.com/movie/master.m3u8')).toBe('application/x-mpegurl');
  });

  it('starts unknown direct/debrid URLs as HLS because some providers hide HLS behind signed URLs', () => {
    expect(getInitialSourceType('https://debrid.example.com/cache/movie.mp4?token=abc')).toBe('application/x-mpegurl');
    expect(getInitialSourceType('https://debrid.example.com/cache/movie.mkv')).toBe('application/x-mpegurl');
  });

  it('falls back from HLS to direct video after provider error', () => {
    expect(getFallbackSourceType('application/x-mpegurl')).toBe('video/mp4');
    expect(getFallbackSourceType('video/mp4')).toBeNull();
  });

  it('reads a playable stream URL from url or externalUrl', () => {
    expect(getStreamUrl({ url: 'https://example.com/a.mp4' })).toBe('https://example.com/a.mp4');
    expect(getStreamUrl({ externalUrl: 'https://example.com/b.mp4' })).toBe('https://example.com/b.mp4');
  });

  it('does not treat externalUrl as playable inside the video player', () => {
    expect(getPlayableStreamUrl({ url: 'https://example.com/a.mp4' })).toBe('https://example.com/a.mp4');
    expect(getPlayableStreamUrl({ externalUrl: 'https://example.com/player-page' })).toBeUndefined();
  });

  it('matches cached streams by url or externalUrl', () => {
    const stream: StreamItem = { externalUrl: 'https://example.com/direct.mp4', addonName: 'AIOStreams' };

    expect(streamMatchesUrl(stream, 'https://example.com/direct.mp4')).toBe(true);
  });

  it('formats old Continue Watching series episode ids with readable titles', () => {
    expect(formatContinueWatchingTitle({ mediaId: 'tt9813792:1:2', mediaType: 'series', name: 'Running Point' })).toBe('Running Point - Episode 2');
  });

  it('falls back cleanly when Continue Watching metadata is still missing', () => {
    expect(formatContinueWatchingTitle({ mediaId: 'tt9813792:1:2', mediaType: 'series' })).toBe('tt9813792 - Episode 2');
    expect(formatContinueWatchingTitle({ mediaId: 'tt34611082', mediaType: 'movie' })).toBe('tt34611082');
  });
});
