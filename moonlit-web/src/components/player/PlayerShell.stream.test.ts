import { describe, expect, it } from 'vitest';

import { prepareStreamForPlayback, prepareStreamForPlaybackAsync } from './PlayerShell.stream';
import type { StreamItem } from '@/lib/types';

describe('prepareStreamForPlayback', () => {
  it('routes AIOStreams elfmagic playback through the media proxy as HLS', () => {
    const stream: StreamItem = {
      url: 'https://aiostreams.elfhosted.com/playback/token/elfmagic/file',
      title: 'From S01E06 H.264 AAC',
    };

    const prepared = prepareStreamForPlayback(stream, '');

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playerType: 'vidstack',
      shouldPreflight: true,
    });
    expect(prepared?.playbackUrl).toBe(`/api/media-proxy?url=${encodeURIComponent(stream.url)}`);
    expect(prepared?.playbackStream.behaviorHints?.webPlayableType).toBe('application/x-mpegurl');
  });

  it('routes non-elfmagic AIOStreams playback through the media proxy as MP4', () => {
    const stream: StreamItem = {
      url: 'https://aiostreams.elfhosted.com/playback/token/movie.mp4',
      title: 'Movie 1080p H.264 AAC',
    };

    const prepared = prepareStreamForPlayback(stream, '');

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playerType: 'vidstack',
      shouldPreflight: true,
    });
    expect(prepared?.playbackUrl).toBe(`/api/media-proxy?url=${encodeURIComponent(stream.url)}`);
    expect(prepared?.playbackStream.behaviorHints?.webPlayableType).toBe('video/mp4');
  });

  it('preflights direct non-HLS MP4 streams', () => {
    const stream: StreamItem = {
      url: 'https://cdn.example.com/movie.mp4',
      title: 'Movie 1080p H.264 AAC',
    };

    expect(prepareStreamForPlayback(stream, '')).toMatchObject({
      rawUrl: stream.url,
      playbackUrl: stream.url,
      playerType: 'vidstack',
      shouldPreflight: true,
    });
  });

  it('preflights the remux URL for incompatible streams when a remux server is enabled', () => {
    const stream: StreamItem = {
      url: 'https://cdn.example.com/movie.mkv',
      title: 'Movie 2160p HEVC TrueHD',
    };

    const prepared = prepareStreamForPlayback(stream, 'https://streaming.example.com');

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playerType: 'vidstack',
      shouldPreflight: true,
    });
    expect(prepared?.playbackUrl).toContain('https://streaming.example.com/hlsv2/');
    expect(prepared?.playbackUrl).toContain('/master.m3u8?');
    expect(prepared?.playbackStream.behaviorHints?.webPlayableType).toBe('application/x-mpegurl');
  });

  it('selects Mediabunny for MKV streams and keeps the raw URL', () => {
    const stream: StreamItem = {
      url: 'https://cdn.example.com/movie.mkv',
      title: 'Movie 1080p H.264 AAC.mkv',
    };

    expect(prepareStreamForPlayback(stream, 'https://streaming.example.com')).toMatchObject({
      rawUrl: stream.url,
      playbackUrl: stream.url,
      playbackStream: stream,
      playerType: 'mediabunny',
      shouldPreflight: false,
    });
  });

  it('keeps plain 4K MP4 streams on Vidstack even when the Mediabunny probe would succeed', async () => {
    const stream: StreamItem = {
      url: 'https://cdn.example.com/movie.mp4',
      title: 'Movie 2160p 4K H.264 AAC',
    };

    const prepared = await prepareStreamForPlaybackAsync(stream, {
      serverUrl: '',
      probeMediabunny: async () => ({ playable: true, transport: 'direct' }),
    });

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playbackUrl: stream.url,
      playerType: 'vidstack',
      routeReason: 'vidstack-direct',
      shouldPreflight: true,
    });
  });

  it('keeps opaque AIOStreams 4K on Vidstack proxy even when Mediabunny can probe it', async () => {
    const stream: StreamItem = {
      url: 'https://aiostreams.elfhosted.com/playback/token/movie.mp4',
      title: 'Movie 2160p 4K H.264 AAC',
    };

    const prepared = await prepareStreamForPlaybackAsync(stream, {
      serverUrl: '',
      probeMediabunny: async (url) => ({
        playable: true,
        transport: url.startsWith('/api/media-proxy') ? 'proxy' : 'direct',
      }),
    });

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playerType: 'vidstack',
      routeReason: 'vidstack-proxy',
      shouldPreflight: true,
    });
    expect(prepared?.playbackUrl).toBe(`/api/media-proxy?url=${encodeURIComponent(stream.url)}`);
  });

  it('keeps AIOStreams on Vidstack proxy even when metadata looks like MKV', async () => {
    const stream: StreamItem = {
      url: 'https://aiostreams.elfhosted.com/playback/token/movie',
      title: 'Movie 2160p 4K H.264 AAC.mkv',
    };

    const prepared = await prepareStreamForPlaybackAsync(stream, {
      serverUrl: '',
      probeMediabunny: async () => ({ playable: true, transport: 'proxy' }),
    });

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playerType: 'vidstack',
      routeReason: 'vidstack-proxy',
      shouldPreflight: true,
    });
    expect(prepared?.playbackUrl).toBe(`/api/media-proxy?url=${encodeURIComponent(stream.url)}`);
  });

  it('routes AIOStreams through Vidstack proxy before sync MKV player selection', () => {
    const stream: StreamItem = {
      url: 'https://aiostreams.elfhosted.com/playback/token/movie',
      title: 'Movie 2160p 4K H.264 AAC.mkv',
    };

    const prepared = prepareStreamForPlayback(stream, '');

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playerType: 'vidstack',
      routeReason: 'vidstack-proxy',
      shouldPreflight: true,
    });
    expect(prepared?.playbackUrl).toBe(`/api/media-proxy?url=${encodeURIComponent(stream.url)}`);
  });

  it('falls back to Vidstack proxy for non-4K AIOStreams when Mediabunny probing fails', async () => {
    const stream: StreamItem = {
      url: 'https://aiostreams.elfhosted.com/playback/token/movie.mp4',
      title: 'Movie 1080p H.264 AAC',
    };

    const prepared = await prepareStreamForPlaybackAsync(stream, {
      serverUrl: '',
      probeMediabunny: async () => ({ playable: false, reason: 'probe failed' }),
    });

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playerType: 'vidstack',
      routeReason: 'vidstack-proxy',
      shouldPreflight: true,
    });
    expect(prepared?.playbackUrl).toBe(`/api/media-proxy?url=${encodeURIComponent(stream.url)}`);
  });


  it('selects server transcode for unsupported 4K streams when the Mediabunny probe fails and a server is configured', async () => {
    const stream: StreamItem = {
      url: 'https://cdn.example.com/movie.mp4',
      title: 'Movie 2160p 4K HEVC Dolby Vision TrueHD',
    };

    const prepared = await prepareStreamForPlaybackAsync(stream, {
      serverUrl: 'https://streaming.example.com',
      probeMediabunny: async () => ({ playable: false, reason: 'unsupported-codecs' }),
    });

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playerType: 'vidstack',
      routeReason: 'server-transcode',
      shouldPreflight: true,
    });
    expect(prepared?.playbackUrl).toContain('https://streaming.example.com/hlsv2/');
    expect(prepared?.playbackStream.behaviorHints?.webPlayableType).toBe('application/x-mpegurl');
  });

  it('returns an actionable unplayable result for unsupported 4K streams without a server', async () => {
    const stream: StreamItem = {
      url: 'https://cdn.example.com/movie.mp4',
      title: 'Movie 2160p 4K HEVC Dolby Vision TrueHD',
    };

    const prepared = await prepareStreamForPlaybackAsync(stream, {
      serverUrl: '',
      probeMediabunny: async () => ({ playable: false, reason: 'unsupported-codecs' }),
    });

    expect(prepared).toMatchObject({
      rawUrl: stream.url,
      playerType: 'vidstack',
      routeReason: 'unsupported',
      unplayableReason: 'This 4K source needs transcoding or another browser-compatible source.',
      shouldPreflight: false,
    });
  });
});
