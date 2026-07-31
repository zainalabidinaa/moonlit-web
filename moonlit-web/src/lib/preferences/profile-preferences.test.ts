import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  DEFAULT_ARTWORK_PREFERENCES,
  DEFAULT_HOME_PREFERENCES,
  DEFAULT_PLAYER_PREFERENCES,
  DEFAULT_SUBTITLE_PREFERENCES,
  PREFERENCE_SCHEMA_VERSIONS,
  ProfilePreferencesRepository,
  normalizeArtworkPreferences,
  normalizeHomePreferences,
  normalizePlayerPreferences,
  normalizeSubtitlePreferences,
  type PreferenceCloudStore,
  type ProfilePreferenceRow,
  type StorageLike,
} from './profile-preferences';

class MemoryStorage implements StorageLike {
  readonly values = new Map<string, string>();
  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) { this.values.set(key, value); }
  removeItem(key: string) { this.values.delete(key); }
}

class FakeCloud implements PreferenceCloudStore {
  readonly rows = new Map<string, ProfilePreferenceRow>();
  readonly reads = vi.fn(async (profileId: string, namespace: string) => this.rows.get(`${profileId}:${namespace}`) ?? null);
  readonly upserts = vi.fn(async (row: ProfilePreferenceRow) => { this.rows.set(`${row.profile_id}:${row.namespace}`, row); });
  read = this.reads;
  upsert = this.upserts;
}

describe('preference normalization', () => {
  it('normalizes home lists and falls back for malformed fields', () => {
    expect(normalizeHomePreferences({
      cinematicModeEnabled: 'yes',
      heroCatalogId: 42,
      disabledHeroRowTitles: [' Trending ', 'Trending', '', 7],
      heroRowOrder: ['Popular', 'Popular', 'Drama'],
      disabledCollectionIds: ['one', 'one', 'two'],
    })).toEqual({
      ...DEFAULT_HOME_PREFERENCES,
      disabledHeroRowTitles: ['Trending'],
      heroRowOrder: ['Popular', 'Drama'],
      disabledCollectionIds: ['one', 'two'],
    });
  });

  it('clamps artwork values to the Mac controls range', () => {
    expect(normalizeArtworkPreferences({
      posterScale: 5,
      posterRadius: -2,
      hoverPreviewEnabled: false,
      hoverPreviewDelaySeconds: 0.05,
    })).toEqual({
      ...DEFAULT_ARTWORK_PREFERENCES,
      posterScale: 2,
      posterRadius: 0,
      hoverPreviewEnabled: false,
      hoverPreviewDelaySeconds: 0.2,
    });
  });

  it('normalizes player choices and bounded timing values', () => {
    expect(normalizePlayerPreferences({
      cacheMode: 'network',
      fallbackSkipSeconds: 999,
      nextEpisodePromptSeconds: 2,
      preferredAudioLanguage: ' SV ',
      preferredSubtitleLanguage: '',
    })).toEqual({
      ...DEFAULT_PLAYER_PREFERENCES,
      fallbackSkipSeconds: 120,
      nextEpisodePromptSeconds: 15,
      preferredAudioLanguage: 'sv',
    });
  });

  it('normalizes the expanded subtitle appearance model', () => {
    expect(normalizeSubtitlePreferences({
      preset: 'boxed',
      fontSize: 100,
      scale: 0.1,
      textColorHex: 'fff',
      outlineColorHex: '#123456',
      backgroundOpacity: 3,
      verticalPosition: -10,
      horizontalAlignment: 'sideways',
      horizontalMargin: 150,
      textBlur: 8,
    })).toEqual({
      ...DEFAULT_SUBTITLE_PREFERENCES,
      preset: 'boxed',
      fontSize: 72,
      scale: 0.5,
      outlineColorHex: '#123456',
      backgroundOpacity: 1,
      verticalPosition: 0,
      horizontalMargin: 100,
      textBlur: 5,
    });
  });
});

describe('ProfilePreferencesRepository', () => {
  let storage: MemoryStorage;
  let cloud: FakeCloud;
  let repository: ProfilePreferencesRepository;
  let nowMs: number;

  beforeEach(() => {
    storage = new MemoryStorage();
    cloud = new FakeCloud();
    nowMs = Date.parse('2026-07-31T12:00:00.000Z');
    repository = new ProfilePreferencesRepository({ storage, cloud, now: () => new Date(nowMs) });
  });

  it('isolates local caches by profile and namespace', async () => {
    await repository.save('profile-a', 'artwork', { ...DEFAULT_ARTWORK_PREFERENCES, posterScale: 1.3 });
    await repository.save('profile-b', 'artwork', { ...DEFAULT_ARTWORK_PREFERENCES, posterScale: 0.8 });

    cloud.reads.mockRejectedValue(new Error('offline'));

    await expect(repository.load('profile-a', 'artwork')).resolves.toMatchObject({ value: { posterScale: 1.3 } });
    await expect(repository.load('profile-b', 'artwork')).resolves.toMatchObject({ value: { posterScale: 0.8 } });
  });

  it('uses and caches a cloud row only when it is newer', async () => {
    await repository.save('profile-a', 'home', { ...DEFAULT_HOME_PREFERENCES, cinematicModeEnabled: false });
    cloud.rows.set('profile-a:home', {
      profile_id: 'profile-a',
      namespace: 'home',
      schema_version: PREFERENCE_SCHEMA_VERSIONS.home,
      value: { ...DEFAULT_HOME_PREFERENCES, heroCatalogId: 'cloud-hero' },
      updated_at: '2026-07-31T13:00:00.000Z',
    });

    const result = await repository.load('profile-a', 'home');

    expect(result).toMatchObject({ source: 'cloud', value: { heroCatalogId: 'cloud-hero' } });
    cloud.reads.mockRejectedValue(new Error('offline'));
    await expect(repository.load('profile-a', 'home')).resolves.toMatchObject({ value: { heroCatalogId: 'cloud-hero' } });
  });

  it('keeps a save made during an in-flight cloud read authoritative', async () => {
    await repository.save('profile-a', 'subtitles', {
      ...DEFAULT_SUBTITLE_PREFERENCES,
      fontSize: 24,
    });

    let resolveCloudRead: ((row: ProfilePreferenceRow | null) => void) | undefined;
    cloud.reads.mockImplementationOnce(() => new Promise(resolve => {
      resolveCloudRead = resolve;
    }));

    const activation = repository.load('profile-a', 'subtitles');
    await vi.waitFor(() => expect(resolveCloudRead).toBeTypeOf('function'));

    nowMs = Date.parse('2026-07-31T14:00:00.000Z');
    await repository.save('profile-a', 'subtitles', {
      ...DEFAULT_SUBTITLE_PREFERENCES,
      fontSize: 42,
    });

    resolveCloudRead?.({
      profile_id: 'profile-a',
      namespace: 'subtitles',
      schema_version: PREFERENCE_SCHEMA_VERSIONS.subtitles,
      value: { ...DEFAULT_SUBTITLE_PREFERENCES, fontSize: 30 },
      updated_at: '2026-07-31T13:00:00.000Z',
    });

    await expect(activation).resolves.toMatchObject({
      source: 'local',
      value: { fontSize: 42 },
    });
    expect(repository.loadCached('profile-a', 'subtitles').value.fontSize).toBe(42);
  });

  it('keeps a newer local row and reconciles it to cloud', async () => {
    await repository.save('profile-a', 'player', { ...DEFAULT_PLAYER_PREFERENCES, autoSkipIntros: true });
    cloud.upserts.mockClear();
    cloud.rows.set('profile-a:player', {
      profile_id: 'profile-a',
      namespace: 'player',
      schema_version: PREFERENCE_SCHEMA_VERSIONS.player,
      value: DEFAULT_PLAYER_PREFERENCES,
      updated_at: '2026-07-31T11:00:00.000Z',
    });

    const result = await repository.load('profile-a', 'player');

    expect(result).toMatchObject({ source: 'local', value: { autoSkipIntros: true }, synced: true });
    expect(cloud.upserts).toHaveBeenCalledWith(expect.objectContaining({ value: expect.objectContaining({ autoSkipIntros: true }) }));
  });

  it('writes locally before an offline cloud save and reports pending sync', async () => {
    cloud.upserts.mockRejectedValue(new Error('offline'));

    const result = await repository.save('profile-a', 'home', {
      ...DEFAULT_HOME_PREFERENCES,
      cinematicModeEnabled: false,
    });

    expect(result).toMatchObject({ source: 'local', synced: false });
    cloud.reads.mockRejectedValue(new Error('offline'));
    await expect(repository.load('profile-a', 'home')).resolves.toMatchObject({ value: { cinematicModeEnabled: false } });
  });

  it('keeps guest preferences local and never calls cloud', async () => {
    await repository.save(null, 'artwork', { ...DEFAULT_ARTWORK_PREFERENCES, posterRadius: 18 });
    const result = await repository.load(null, 'artwork');

    expect(result).toMatchObject({ source: 'guest-local', value: { posterRadius: 18 }, synced: false });
    expect(cloud.reads).not.toHaveBeenCalled();
    expect(cloud.upserts).not.toHaveBeenCalled();
  });

  it('imports the existing subtitle and collection keys once into the active profile', async () => {
    storage.setItem('moonlit_subtitle_preferences', JSON.stringify({
      size: 'large', color: 'yellow', backgroundOpacity: 70, position: 'high',
    }));
    storage.setItem('moonlit.collectionDisplayPreferences', JSON.stringify({
      disabledCollectionIds: ['hidden'], expandedCollectionIds: ['open'], hiddenFolderIds: ['folder'],
    }));

    const subtitles = await repository.load('profile-a', 'subtitles');
    const home = await repository.load('profile-a', 'home');

    expect(subtitles.value).toMatchObject({ fontSize: 30, textColorHex: '#FFFF00', backgroundOpacity: 0.7, verticalPosition: 200 });
    expect(home.value).toMatchObject({
      disabledCollectionIds: ['hidden'], expandedCollectionIds: ['open'], hiddenFolderIds: ['folder'],
    });
    expect(storage.getItem('moonlit_subtitle_preferences')).toBeNull();
    expect(storage.getItem('moonlit.collectionDisplayPreferences')).toBeNull();

    storage.setItem('moonlit_subtitle_preferences', JSON.stringify({ size: 'small' }));
    const secondRepository = new ProfilePreferencesRepository({ storage, cloud, now: () => new Date(nowMs) });
    await expect(secondRepository.load('profile-b', 'subtitles')).resolves.toMatchObject({ value: DEFAULT_SUBTITLE_PREFERENCES });
  });

  it('retains every legacy source and the import marker when a destination write fails', async () => {
    storage.setItem('moonlit_subtitle_preferences', JSON.stringify({ size: 'large' }));
    storage.setItem('moonlit.collectionDisplayPreferences', JSON.stringify({
      disabledCollectionIds: ['hidden'],
    }));
    const originalSetItem = storage.setItem.bind(storage);
    storage.setItem = (key, value) => {
      if (key === 'moonlit.preferences.profile-a.home') throw new Error('quota exceeded');
      originalSetItem(key, value);
    };

    await repository.load('profile-a', 'subtitles');

    expect(storage.getItem('moonlit_subtitle_preferences')).not.toBeNull();
    expect(storage.getItem('moonlit.collectionDisplayPreferences')).not.toBeNull();
    expect(storage.getItem('moonlit.preferences.legacy-imported.v1')).toBeNull();
  });

  it('falls back to normalized defaults when local data is corrupt and cloud is offline', async () => {
    storage.setItem('moonlit.preferences.profile-a.home', '{bad json');
    cloud.reads.mockRejectedValue(new Error('offline'));

    await expect(repository.load('profile-a', 'home')).resolves.toEqual({
      value: DEFAULT_HOME_PREFERENCES,
      source: 'default',
      synced: false,
    });
  });
});
