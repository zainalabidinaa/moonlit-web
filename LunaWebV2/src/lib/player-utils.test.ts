import { describe, expect, it } from 'vitest';

import { StreamItem } from './types';
import {
  formatContinueWatchingTitle,
  getStreamUrl,
  getVidstackSourceType,
  streamMatchesUrl,
} from './player-utils';

describe('player utils', () => {
  it('detects HLS streams from m3u8 URLs', () => {
    expect(getVidstackSourceType('https://example.com/movie/master.m3u8')).toBe('application/x-mpegurl');
  });

  it('treats direct/debrid file URLs as direct video instead of HLS', () => {
    expect(getVidstackSourceType('https://debrid.example.com/cache/movie.mp4?token=abc')).toBe('video/mp4');
    expect(getVidstackSourceType('https://debrid.example.com/cache/movie.mkv')).toBe('video/mp4');
  });

  it('reads a playable stream URL from url or externalUrl', () => {
    expect(getStreamUrl({ url: 'https://example.com/a.mp4' })).toBe('https://example.com/a.mp4');
    expect(getStreamUrl({ externalUrl: 'https://example.com/b.mp4' })).toBe('https://example.com/b.mp4');
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
