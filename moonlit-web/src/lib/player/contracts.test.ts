import { describe, expect, it } from 'vitest';

import {
  findPlayerTrackByIdentity,
  normalizeAdapterState,
  normalizePlayerLaunch,
  playerTrackIdentity,
  type PlayerLaunch,
  type PlayerTrack,
} from './contracts';

describe('normalizePlayerLaunch', () => {
  it('keeps existing launch sites compatible while normalizing resume and live fields', () => {
    const launch: PlayerLaunch = {
      type: 'series',
      id: 'tt123:2:4',
      streamUrl: 'https://cdn.example/episode.m3u8',
      metadata: {
        mediaId: 'tt123:2:4',
        mediaType: 'series',
        title: 'House of the Dragon',
      },
      startPosition: -12,
    };

    expect(normalizePlayerLaunch(launch)).toMatchObject({
      ...launch,
      startPosition: 0,
      isLive: false,
      preferredTracks: {
        audioId: null,
        subtitleId: null,
        audioLanguage: null,
        subtitleLanguage: null,
      },
    });
  });

  it('preserves expanded episode, headers, and preferred-track launch data', () => {
    const normalized = normalizePlayerLaunch({
      type: 'tv',
      id: 'channel-7',
      streamUrl: 'https://tv.example/live/user/pass/7',
      isLive: true,
      requestHeaders: { Authorization: 'Bearer test' },
      preferredTracks: {
        audioId: 'audio-2',
        subtitleId: 'sub-4',
        audioLanguage: 'en',
        subtitleLanguage: 'sv',
      },
      metadata: {
        mediaId: 'channel-7',
        mediaType: 'tv',
        title: 'Moonlit News',
        secondaryTitle: 'Live',
        season: 2,
        episode: 4,
      },
    });

    expect(normalized.isLive).toBe(true);
    expect(normalized.requestHeaders).toEqual({ Authorization: 'Bearer test' });
    expect(normalized.preferredTracks).toEqual({
      audioId: 'audio-2',
      subtitleId: 'sub-4',
      audioLanguage: 'en',
      subtitleLanguage: 'sv',
      audioIdentity: null,
      subtitleIdentity: null,
    });
    expect(normalized.metadata.secondaryTitle).toBe('Live');
  });

  it.each(['tv', 'live'])('infers live playback for existing %s launch sites', type => {
    const normalized = normalizePlayerLaunch({
      type,
      id: 'channel-7',
      streamUrl: 'https://tv.example/live/user/pass/7',
      metadata: { mediaId: 'channel-7', mediaType: type, title: 'Moonlit News' },
    });

    expect(normalized.isLive).toBe(true);
  });
});

describe('normalizeAdapterState', () => {
  it('clamps adapter-specific values into the renderer-independent contract', () => {
    expect(normalizeAdapterState({
      phase: 'playing',
      position: 140,
      duration: 100,
      buffered: -4,
      volume: 2,
      playbackRate: 0,
    })).toMatchObject({
      phase: 'playing',
      position: 100,
      duration: 100,
      buffered: 0,
      volume: 1,
      playbackRate: 1,
      muted: false,
      audioTracks: [],
      subtitleTracks: [],
    });
  });
});

describe('renderer-neutral track identity', () => {
  it('uses ordinal before fuzzy matching for same-language same-label duplicates', () => {
    const tracks: PlayerTrack[] = [
      { id: 4, kind: 'audio', label: 'English', language: 'en', selected: false },
      { id: 9, kind: 'audio', label: 'English', language: 'en', selected: true },
    ];

    const identity = playerTrackIdentity(tracks[1], tracks);

    expect(findPlayerTrackByIdentity(tracks, identity)?.id).toBe(9);
  });

  it('uses ordinal before fuzzy matching for language-less duplicate subtitles', () => {
    const tracks: PlayerTrack[] = [
      { id: 'embedded-a', kind: 'subtitles', label: 'Signs', selected: false },
      { id: 'embedded-b', kind: 'subtitles', label: 'Signs', selected: true },
    ];

    const identity = playerTrackIdentity(tracks[1], tracks);

    expect(findPlayerTrackByIdentity(tracks, identity)?.id).toBe('embedded-b');
  });
});
