import { describe, expect, it } from 'vitest';

import { selectSubtitleAddonUrls } from './stremio';
import type { AddonManifest } from './types';

describe('selectSubtitleAddonUrls', () => {
  it('uses declared subtitle addons and the public fallback without probing stream-only addons', () => {
    const addons: AddonManifest[] = [
      {
        id: 'streams',
        name: 'Streams',
        version: '1.0.0',
        transportUrl: 'https://streams.example.com',
        resources: ['stream'],
      },
      {
        id: 'subs',
        name: 'Subtitles',
        version: '1.0.0',
        transportUrl: 'https://subs.example.com',
        resources: [{ name: 'subtitles', types: ['series'] }],
      },
    ];

    expect(selectSubtitleAddonUrls('series', addons)).toEqual([
      'https://subs.example.com',
      'https://opensubtitles-v3.strem.io',
    ]);
  });
});
