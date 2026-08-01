import { describe, expect, it } from 'vitest';

import type { StreamItem } from '@/lib/types';
import type { PlaybackEnvironment } from '@/lib/player/routing';
import { selectStreamPlayback } from './PlayerShell.selection';

const browser: PlaybackEnvironment = {
  chromium: true,
  mediaSource: true,
  nativeHls: false,
  hevc: false,
  hevc10: false,
  av1: false,
  ac3: false,
  eac3: false,
  webCodecs: true,
  mediabunny: true,
  mpv: false,
};

const mediaFixtures: StreamItem[] = [
  { url: 'https://fixtures.example/archive.mkv.zip', title: 'Archive copy' },
  { url: 'https://fixtures.example/dv.mkv', title: '2160p DoVi P5 HEVC E-AC-3' },
  { url: 'https://fixtures.example/av1.mkv', title: '2160p AV1 AAC' },
  { url: 'https://fixtures.example/safe.mp4', title: '1080p H.264 AAC', addonName: 'Fixture Addon' },
];

describe('selectStreamPlayback media fixtures', () => {
  it('skips dead and external-only fixtures and picks the first safe browser route', () => {
    const selection = selectStreamPlayback(mediaFixtures, browser, {
      serverUrl: '',
      showOnlyCompatibleFormats: true,
    });

    expect(selection?.stream.url).toBe('https://fixtures.example/safe.mp4');
    expect(selection?.plan.attempts[0].method).toBe('native');
  });

  it('honors an explicit source and keeps its metadata for server transcoding', () => {
    const explicit = mediaFixtures[1];
    const selection = selectStreamPlayback(mediaFixtures, browser, {
      explicitUrl: explicit.url,
      serverUrl: 'https://stream.example',
    });

    expect(selection?.stream).toBe(explicit);
    expect(selection?.plan.attempts[0].method).toBe('server-transcode');
  });

  it('tries a remembered source before browser score order', () => {
    const remembered: StreamItem = { url: 'https://fixtures.example/remembered.mkv', title: '720p H.264 AAC.mkv' };
    const selection = selectStreamPlayback([...mediaFixtures, remembered], browser, {
      rememberedUrl: remembered.url,
      serverUrl: '',
    });

    expect(selection?.stream).toBe(remembered);
    expect(selection?.plan.attempts[0].method).toBe('chromium-mkv');
  });

  it('keeps an honest external outcome when every fixture is browser-unsafe', () => {
    const selection = selectStreamPlayback(mediaFixtures.slice(0, 3), browser, { serverUrl: '' });

    expect(selection?.plan.outcome).toBe('external');
    expect(selection?.plan.attempts).toEqual([]);
  });
});
