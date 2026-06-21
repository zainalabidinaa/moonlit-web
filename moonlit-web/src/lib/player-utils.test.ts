import { describe, expect, it } from 'vitest';

import { StreamItem } from './types';
import {
  getFallbackSourceType,
  formatContinueWatchingTitle,
  getPlayableStreamUrl,
  sortStreamsForBrowserPlayback,
  getStreamUrl,
  getInitialSourceType,
  streamMatchesUrl,
} from './player-utils';

describe('player utils', () => {
  it('detects HLS streams from m3u8 URLs', () => {
    expect(getInitialSourceType('https://example.com/movie/master.m3u8')).toBe('application/x-mpegurl');
  });

  it('uses video/mp4 by default for unknown URLs to avoid hls.js failing on direct mp4/webm content', () => {
    expect(getInitialSourceType('https://cdn.example.com/movie.mp4')).toBe('video/mp4');
    expect(getInitialSourceType('https://example.com/cache/movie.mkv')).toBe('video/mp4');
  });

  it('starts known debrid/CDN domains as HLS because they often hide HLS behind signed URLs', () => {
    expect(getInitialSourceType('https://real-debrid.com/cache/movie.mp4?token=abc')).toBe('application/x-mpegurl');
    expect(getInitialSourceType('https://alldebrid.com/stream/xyz')).toBe('application/x-mpegurl');
  });

  it('detects HLS from URL path patterns regardless of domain', () => {
    expect(getInitialSourceType('https://unknown-cdn.example.com/stream/master.m3u8')).toBe('application/x-mpegurl');
    expect(getInitialSourceType('https://unknown-cdn.example.com/manifest')).toBe('application/x-mpegurl');
    expect(getInitialSourceType('https://unknown-cdn.example.com/playlist.m3u8')).toBe('application/x-mpegurl');
    expect(getInitialSourceType('https://unknown-cdn.example.com/live/hls/stream')).toBe('application/x-mpegurl');
  });

  it('starts streams with proxyHeaders as HLS regardless of URL', () => {
    expect(getInitialSourceType('https://unknown-cdn.example.com/movie.mp4', {
      behaviorHints: { proxyHeaders: { request: { 'Origin': 'https://example.com' } } }
    })).toBe('application/x-mpegurl');
  });

  it('uses verified stream playable type when provided by the stream API', () => {
    expect(getInitialSourceType('https://example.com/playback/token', { behaviorHints: { webPlayableType: 'video/mp4' } })).toBe('video/mp4');
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

  it('prefers browser-friendly H264 sources over 4K HEVC MKV sources', () => {
    const streams: StreamItem[] = [
      { url: 'https://example.com/hevc.mkv', name: '4K WEB-DL', behaviorHints: { filename: 'Movie.2160p.DV.HDR.H.265.Atmos.mkv' } },
      { url: 'https://example.com/h264', name: '720P WEB-DL', behaviorHints: { filename: 'Movie.720p.WEB-DL.H.264.AAC' } },
    ];

    expect(sortStreamsForBrowserPlayback(streams)[0].url).toBe('https://example.com/h264');
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
