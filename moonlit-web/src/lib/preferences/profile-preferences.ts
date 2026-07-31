import type { SupabaseClient } from '@supabase/supabase-js';

import { supabase } from '@/lib/supabase';

export type PreferenceNamespace = 'home' | 'artwork' | 'player' | 'subtitles';

export interface HomePreferences {
  cinematicModeEnabled: boolean;
  heroCatalogId: string | null;
  disabledHeroRowTitles: string[];
  heroRowOrder: string[];
  disabledCollectionIds: string[];
  expandedCollectionIds: string[];
  hiddenFolderIds: string[];
}

export interface ArtworkPreferences {
  posterScale: number;
  posterRadius: number;
  artworkHaloEnabled: boolean;
  hoverPreviewEnabled: boolean;
  hoverPreviewDelaySeconds: number;
}

export type PlayerEnginePreference = 'auto' | 'native' | 'mpv';
export type PlayerCacheMode = 'memory' | 'disk' | 'off';

export interface PlayerPreferences {
  autoplayNextEpisode: boolean;
  nextEpisodePromptSeconds: number;
  showSkipIntroButton: boolean;
  autoSkipIntros: boolean;
  useIntroDb: boolean;
  fallbackSkipEnabled: boolean;
  fallbackSkipSeconds: number;
  showTimelineHighlights: boolean;
  cacheMode: PlayerCacheMode;
  autoplayPreviews: boolean;
  playPreviewSound: boolean;
  anime4KEnabled: boolean;
  showOnlyCompatibleFormats: boolean;
  usePerTypePlayers: boolean;
  moviePlayer: PlayerEnginePreference;
  seriesPlayer: PlayerEnginePreference;
  livePlayer: PlayerEnginePreference;
  preferredAudioLanguage: string | null;
  preferredSubtitleLanguage: string | null;
}

export type SubtitlePreset = 'standard' | 'boxed' | 'classic' | 'minimal';
export type SubtitleAlignment = 'left' | 'center' | 'right';

export interface SubtitlePreferences {
  preset: SubtitlePreset;
  fontSize: number;
  scale: number;
  isBold: boolean;
  isItalic: boolean;
  textColorHex: string;
  outlineColorHex: string;
  backgroundColorHex: string;
  backgroundOpacity: number;
  verticalPosition: number;
  horizontalAlignment: SubtitleAlignment;
  horizontalMargin: number;
  textBlur: number;
  scaleWithWindowSize: boolean;
}

export interface PreferencesByNamespace {
  home: HomePreferences;
  artwork: ArtworkPreferences;
  player: PlayerPreferences;
  subtitles: SubtitlePreferences;
}

export const PREFERENCE_SCHEMA_VERSIONS = {
  home: 1,
  artwork: 1,
  player: 1,
  subtitles: 1,
} as const satisfies Record<PreferenceNamespace, number>;

export const DEFAULT_HOME_PREFERENCES: HomePreferences = {
  cinematicModeEnabled: true,
  heroCatalogId: null,
  disabledHeroRowTitles: [],
  heroRowOrder: [],
  disabledCollectionIds: [],
  expandedCollectionIds: [],
  hiddenFolderIds: [],
};

export const DEFAULT_ARTWORK_PREFERENCES: ArtworkPreferences = {
  posterScale: 1,
  posterRadius: 12,
  artworkHaloEnabled: true,
  hoverPreviewEnabled: true,
  hoverPreviewDelaySeconds: 0.7,
};

export const DEFAULT_PLAYER_PREFERENCES: PlayerPreferences = {
  autoplayNextEpisode: false,
  nextEpisodePromptSeconds: 30,
  showSkipIntroButton: true,
  autoSkipIntros: false,
  useIntroDb: true,
  fallbackSkipEnabled: true,
  fallbackSkipSeconds: 85,
  showTimelineHighlights: true,
  cacheMode: 'memory',
  autoplayPreviews: true,
  playPreviewSound: false,
  anime4KEnabled: false,
  showOnlyCompatibleFormats: false,
  usePerTypePlayers: false,
  moviePlayer: 'auto',
  seriesPlayer: 'auto',
  livePlayer: 'auto',
  preferredAudioLanguage: null,
  preferredSubtitleLanguage: null,
};

export const DEFAULT_SUBTITLE_PREFERENCES: SubtitlePreferences = {
  preset: 'standard',
  fontSize: 32,
  scale: 1,
  isBold: false,
  isItalic: false,
  textColorHex: '#FFFFFF',
  outlineColorHex: '#000000',
  backgroundColorHex: '#000000',
  backgroundOpacity: 0,
  verticalPosition: 100,
  horizontalAlignment: 'center',
  horizontalMargin: 19,
  textBlur: 0,
  scaleWithWindowSize: true,
};

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function bool(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function boundedNumber(value: unknown, fallback: number, min: number, max: number): number {
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.min(max, Math.max(min, value))
    : fallback;
}

function boundedInteger(value: unknown, fallback: number, min: number, max: number): number {
  return Math.round(boundedNumber(value, fallback, min, max));
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value
    .filter((item): item is string => typeof item === 'string')
    .map(item => item.trim())
    .filter(Boolean))];
}

function nullableLanguage(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim().toLowerCase();
  return /^[a-z]{2,3}$/.test(normalized) ? normalized : null;
}

function hexColor(value: unknown, fallback: string): string {
  return typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value)
    ? value.toUpperCase()
    : fallback;
}

export function normalizeHomePreferences(value: unknown): HomePreferences {
  const input = record(value);
  return {
    cinematicModeEnabled: bool(input.cinematicModeEnabled, DEFAULT_HOME_PREFERENCES.cinematicModeEnabled),
    heroCatalogId: typeof input.heroCatalogId === 'string' && input.heroCatalogId.trim()
      ? input.heroCatalogId.trim()
      : null,
    disabledHeroRowTitles: stringList(input.disabledHeroRowTitles),
    heroRowOrder: stringList(input.heroRowOrder),
    disabledCollectionIds: stringList(input.disabledCollectionIds),
    expandedCollectionIds: stringList(input.expandedCollectionIds),
    hiddenFolderIds: stringList(input.hiddenFolderIds),
  };
}

export function normalizeArtworkPreferences(value: unknown): ArtworkPreferences {
  const input = record(value);
  return {
    posterScale: boundedNumber(input.posterScale, DEFAULT_ARTWORK_PREFERENCES.posterScale, 0.6, 2),
    posterRadius: boundedInteger(input.posterRadius, DEFAULT_ARTWORK_PREFERENCES.posterRadius, 0, 40),
    artworkHaloEnabled: bool(input.artworkHaloEnabled, DEFAULT_ARTWORK_PREFERENCES.artworkHaloEnabled),
    hoverPreviewEnabled: bool(input.hoverPreviewEnabled, DEFAULT_ARTWORK_PREFERENCES.hoverPreviewEnabled),
    hoverPreviewDelaySeconds: boundedNumber(input.hoverPreviewDelaySeconds, DEFAULT_ARTWORK_PREFERENCES.hoverPreviewDelaySeconds, 0.2, 2),
  };
}

export function normalizePlayerPreferences(value: unknown): PlayerPreferences {
  const input = record(value);
  const cacheModes: PlayerCacheMode[] = ['memory', 'disk', 'off'];
  const engines: PlayerEnginePreference[] = ['auto', 'native', 'mpv'];
  const engine = (candidate: unknown) => engines.includes(candidate as PlayerEnginePreference)
    ? candidate as PlayerEnginePreference
    : 'auto';

  return {
    autoplayNextEpisode: bool(input.autoplayNextEpisode, DEFAULT_PLAYER_PREFERENCES.autoplayNextEpisode),
    nextEpisodePromptSeconds: boundedInteger(input.nextEpisodePromptSeconds, DEFAULT_PLAYER_PREFERENCES.nextEpisodePromptSeconds, 15, 60),
    showSkipIntroButton: bool(input.showSkipIntroButton, DEFAULT_PLAYER_PREFERENCES.showSkipIntroButton),
    autoSkipIntros: bool(input.autoSkipIntros, DEFAULT_PLAYER_PREFERENCES.autoSkipIntros),
    useIntroDb: bool(input.useIntroDb, DEFAULT_PLAYER_PREFERENCES.useIntroDb),
    fallbackSkipEnabled: bool(input.fallbackSkipEnabled, DEFAULT_PLAYER_PREFERENCES.fallbackSkipEnabled),
    fallbackSkipSeconds: boundedInteger(input.fallbackSkipSeconds, DEFAULT_PLAYER_PREFERENCES.fallbackSkipSeconds, 30, 120),
    showTimelineHighlights: bool(input.showTimelineHighlights, DEFAULT_PLAYER_PREFERENCES.showTimelineHighlights),
    cacheMode: cacheModes.includes(input.cacheMode as PlayerCacheMode)
      ? input.cacheMode as PlayerCacheMode
      : DEFAULT_PLAYER_PREFERENCES.cacheMode,
    autoplayPreviews: bool(input.autoplayPreviews, DEFAULT_PLAYER_PREFERENCES.autoplayPreviews),
    playPreviewSound: bool(input.playPreviewSound, DEFAULT_PLAYER_PREFERENCES.playPreviewSound),
    anime4KEnabled: bool(input.anime4KEnabled, DEFAULT_PLAYER_PREFERENCES.anime4KEnabled),
    showOnlyCompatibleFormats: bool(input.showOnlyCompatibleFormats, DEFAULT_PLAYER_PREFERENCES.showOnlyCompatibleFormats),
    usePerTypePlayers: bool(input.usePerTypePlayers, DEFAULT_PLAYER_PREFERENCES.usePerTypePlayers),
    moviePlayer: engine(input.moviePlayer),
    seriesPlayer: engine(input.seriesPlayer),
    livePlayer: engine(input.livePlayer),
    preferredAudioLanguage: nullableLanguage(input.preferredAudioLanguage),
    preferredSubtitleLanguage: nullableLanguage(input.preferredSubtitleLanguage),
  };
}

export function normalizeSubtitlePreferences(value: unknown): SubtitlePreferences {
  const input = record(value);
  const presets: SubtitlePreset[] = ['standard', 'boxed', 'classic', 'minimal'];
  const alignments: SubtitleAlignment[] = ['left', 'center', 'right'];
  return {
    preset: presets.includes(input.preset as SubtitlePreset)
      ? input.preset as SubtitlePreset
      : DEFAULT_SUBTITLE_PREFERENCES.preset,
    fontSize: boundedInteger(input.fontSize, DEFAULT_SUBTITLE_PREFERENCES.fontSize, 12, 72),
    scale: boundedNumber(input.scale, DEFAULT_SUBTITLE_PREFERENCES.scale, 0.5, 2),
    isBold: bool(input.isBold, DEFAULT_SUBTITLE_PREFERENCES.isBold),
    isItalic: bool(input.isItalic, DEFAULT_SUBTITLE_PREFERENCES.isItalic),
    textColorHex: hexColor(input.textColorHex, DEFAULT_SUBTITLE_PREFERENCES.textColorHex),
    outlineColorHex: hexColor(input.outlineColorHex, DEFAULT_SUBTITLE_PREFERENCES.outlineColorHex),
    backgroundColorHex: hexColor(input.backgroundColorHex, DEFAULT_SUBTITLE_PREFERENCES.backgroundColorHex),
    backgroundOpacity: boundedNumber(input.backgroundOpacity, DEFAULT_SUBTITLE_PREFERENCES.backgroundOpacity, 0, 1),
    verticalPosition: boundedInteger(input.verticalPosition, DEFAULT_SUBTITLE_PREFERENCES.verticalPosition, 0, 200),
    horizontalAlignment: alignments.includes(input.horizontalAlignment as SubtitleAlignment)
      ? input.horizontalAlignment as SubtitleAlignment
      : DEFAULT_SUBTITLE_PREFERENCES.horizontalAlignment,
    horizontalMargin: boundedInteger(input.horizontalMargin, DEFAULT_SUBTITLE_PREFERENCES.horizontalMargin, 0, 100),
    textBlur: boundedNumber(input.textBlur, DEFAULT_SUBTITLE_PREFERENCES.textBlur, 0, 5),
    scaleWithWindowSize: bool(input.scaleWithWindowSize, DEFAULT_SUBTITLE_PREFERENCES.scaleWithWindowSize),
  };
}

const normalizers = {
  home: normalizeHomePreferences,
  artwork: normalizeArtworkPreferences,
  player: normalizePlayerPreferences,
  subtitles: normalizeSubtitlePreferences,
} satisfies { [K in PreferenceNamespace]: (value: unknown) => PreferencesByNamespace[K] };

function normalize<K extends PreferenceNamespace>(namespace: K, value: unknown): PreferencesByNamespace[K] {
  return normalizers[namespace](value) as PreferencesByNamespace[K];
}

export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface ProfilePreferenceRow {
  profile_id: string;
  namespace: PreferenceNamespace;
  schema_version: number;
  value: unknown;
  updated_at: string;
}

export interface PreferenceCloudStore {
  read(profileId: string, namespace: PreferenceNamespace): Promise<ProfilePreferenceRow | null>;
  upsert(row: ProfilePreferenceRow): Promise<void>;
}

export type PreferenceLoadSource = 'cloud' | 'local' | 'guest-local' | 'default';

export interface PreferenceResult<K extends PreferenceNamespace> {
  value: PreferencesByNamespace[K];
  source: PreferenceLoadSource;
  synced: boolean;
}

interface LocalPreferenceEnvelope {
  schemaVersion: number;
  value: unknown;
  updatedAt: string;
}

const LOCAL_PREFIX = 'moonlit.preferences';
const LEGACY_IMPORT_MARKER = `${LOCAL_PREFIX}.legacy-imported.v1`;
const LEGACY_SUBTITLE_KEY = 'moonlit_subtitle_preferences';
const LEGACY_COLLECTION_KEY = 'moonlit.collectionDisplayPreferences';

function storageKey(profileId: string | null, namespace: PreferenceNamespace): string {
  return `${LOCAL_PREFIX}.${profileId ?? 'guest'}.${namespace}`;
}

function timestamp(value: string): number {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function legacySubtitlePreferences(value: unknown): SubtitlePreferences {
  const input = record(value);
  const sizes: Record<string, number> = { small: 18, medium: 24, large: 30, xlarge: 38 };
  const colors: Record<string, string> = {
    white: '#FFFFFF', yellow: '#FFFF00', cyan: '#4AD8FF', green: '#4AFF6A',
  };
  const positions: Record<string, number> = { low: 100, medium: 150, high: 200 };
  const opacity = typeof input.backgroundOpacity === 'number'
    ? Math.min(1, Math.max(0, input.backgroundOpacity / 100))
    : DEFAULT_SUBTITLE_PREFERENCES.backgroundOpacity;
  const textColorHex = colors[String(input.color)] ?? DEFAULT_SUBTITLE_PREFERENCES.textColorHex;

  return normalizeSubtitlePreferences({
    ...DEFAULT_SUBTITLE_PREFERENCES,
    preset: textColorHex === '#FFFF00' ? 'classic' : opacity > 0 ? 'boxed' : 'standard',
    fontSize: sizes[String(input.size)] ?? DEFAULT_SUBTITLE_PREFERENCES.fontSize,
    textColorHex,
    backgroundOpacity: opacity,
    verticalPosition: positions[String(input.position)] ?? DEFAULT_SUBTITLE_PREFERENCES.verticalPosition,
  });
}

export class ProfilePreferencesRepository {
  private readonly storage: StorageLike;
  private readonly cloud?: PreferenceCloudStore;
  private readonly now: () => Date;

  constructor(options: { storage: StorageLike; cloud?: PreferenceCloudStore; now?: () => Date }) {
    this.storage = options.storage;
    this.cloud = options.cloud;
    this.now = options.now ?? (() => new Date());
  }

  loadCached<K extends PreferenceNamespace>(profileId: string | null, namespace: K): PreferenceResult<K> {
    this.importLegacyPreferences(profileId);
    const local = this.readLocal(profileId, namespace);
    return local
      ? { value: local.value, source: profileId ? 'local' : 'guest-local', synced: false }
      : { value: normalize(namespace, {}), source: 'default', synced: false };
  }

  async load<K extends PreferenceNamespace>(profileId: string | null, namespace: K): Promise<PreferenceResult<K>> {
    this.importLegacyPreferences(profileId);
    const local = this.readLocal(profileId, namespace);

    if (!profileId || !this.cloud) {
      return local
        ? { value: local.value, source: profileId ? 'local' : 'guest-local', synced: false }
        : { value: normalize(namespace, {}), source: 'default', synced: false };
    }

    let cloudRow: ProfilePreferenceRow | null;
    try {
      cloudRow = await this.cloud.read(profileId, namespace);
    } catch {
      const currentLocal = this.readLocal(profileId, namespace);
      return currentLocal
        ? { value: currentLocal.value, source: 'local', synced: false }
        : { value: normalize(namespace, {}), source: 'default', synced: false };
    }

    const currentLocal = this.readLocal(profileId, namespace);

    if (cloudRow && (!currentLocal || timestamp(cloudRow.updated_at) > timestamp(currentLocal.updatedAt))) {
      const value = normalize(namespace, cloudRow.value);
      this.writeLocal(profileId, namespace, {
        schemaVersion: PREFERENCE_SCHEMA_VERSIONS[namespace],
        value,
        updatedAt: cloudRow.updated_at,
      });
      return { value, source: 'cloud', synced: true };
    }

    if (currentLocal) {
      let synced = !!cloudRow;
      if (!cloudRow || timestamp(currentLocal.updatedAt) > timestamp(cloudRow.updated_at)) {
        try {
          await this.cloud.upsert(this.toCloudRow(profileId, namespace, currentLocal));
          synced = true;
        } catch {
          synced = false;
        }
      }
      return { value: currentLocal.value, source: 'local', synced };
    }

    return { value: normalize(namespace, {}), source: 'default', synced: !!cloudRow };
  }

  async save<K extends PreferenceNamespace>(
    profileId: string | null,
    namespace: K,
    value: PreferencesByNamespace[K],
  ): Promise<PreferenceResult<K>> {
    const normalized = normalize(namespace, value);
    const envelope = {
      schemaVersion: PREFERENCE_SCHEMA_VERSIONS[namespace],
      value: normalized,
      updatedAt: this.now().toISOString(),
    };
    this.writeLocal(profileId, namespace, envelope);

    if (!profileId || !this.cloud) {
      return { value: normalized, source: profileId ? 'local' : 'guest-local', synced: false };
    }

    try {
      await this.cloud.upsert(this.toCloudRow(profileId, namespace, envelope));
      return { value: normalized, source: 'local', synced: true };
    } catch {
      return { value: normalized, source: 'local', synced: false };
    }
  }

  private readLocal<K extends PreferenceNamespace>(profileId: string | null, namespace: K): (LocalPreferenceEnvelope & { value: PreferencesByNamespace[K] }) | null {
    try {
      const raw = this.storage.getItem(storageKey(profileId, namespace));
      if (!raw) return null;
      const envelope = JSON.parse(raw) as Partial<LocalPreferenceEnvelope>;
      if (typeof envelope.updatedAt !== 'string' || timestamp(envelope.updatedAt) === 0) return null;
      return {
        schemaVersion: PREFERENCE_SCHEMA_VERSIONS[namespace],
        value: normalize(namespace, envelope.value),
        updatedAt: envelope.updatedAt,
      };
    } catch {
      return null;
    }
  }

  private writeLocal<K extends PreferenceNamespace>(profileId: string | null, namespace: K, envelope: LocalPreferenceEnvelope): boolean {
    try {
      this.storage.setItem(storageKey(profileId, namespace), JSON.stringify(envelope));
      return true;
    } catch {
      // Cloud persistence may still succeed when local storage is unavailable.
      return false;
    }
  }

  private toCloudRow<K extends PreferenceNamespace>(profileId: string, namespace: K, envelope: LocalPreferenceEnvelope): ProfilePreferenceRow {
    return {
      profile_id: profileId,
      namespace,
      schema_version: PREFERENCE_SCHEMA_VERSIONS[namespace],
      value: normalize(namespace, envelope.value),
      updated_at: envelope.updatedAt,
    };
  }

  private importLegacyPreferences(profileId: string | null): void {
    try {
      if (this.storage.getItem(LEGACY_IMPORT_MARKER)) return;
      const importedAt = this.now().toISOString();
      const subtitleRaw = this.storage.getItem(LEGACY_SUBTITLE_KEY);
      const collectionRaw = this.storage.getItem(LEGACY_COLLECTION_KEY);
      let destinationsWritten = true;

      if (subtitleRaw && !this.storage.getItem(storageKey(profileId, 'subtitles'))) {
        try {
          destinationsWritten = this.writeLocal(profileId, 'subtitles', {
            schemaVersion: PREFERENCE_SCHEMA_VERSIONS.subtitles,
            value: legacySubtitlePreferences(JSON.parse(subtitleRaw)),
            updatedAt: importedAt,
          }) && destinationsWritten;
        } catch {
          destinationsWritten = false;
        }
      }

      if (collectionRaw && !this.storage.getItem(storageKey(profileId, 'home'))) {
        try {
          const legacyCollections = record(JSON.parse(collectionRaw));
          destinationsWritten = this.writeLocal(profileId, 'home', {
            schemaVersion: PREFERENCE_SCHEMA_VERSIONS.home,
            value: normalizeHomePreferences({
              disabledCollectionIds: legacyCollections.disabledCollectionIds,
              expandedCollectionIds: legacyCollections.expandedCollectionIds,
              hiddenFolderIds: legacyCollections.hiddenFolderIds,
            }),
            updatedAt: importedAt,
          }) && destinationsWritten;
        } catch {
          destinationsWritten = false;
        }
      }

      if (!destinationsWritten) return;

      this.storage.removeItem(LEGACY_SUBTITLE_KEY);
      this.storage.removeItem(LEGACY_COLLECTION_KEY);
      this.storage.setItem(LEGACY_IMPORT_MARKER, importedAt);
    } catch {
      // Private browsing may make localStorage unavailable.
    }
  }
}

export class SupabasePreferenceCloudStore implements PreferenceCloudStore {
  constructor(private readonly client: SupabaseClient) {}

  async read(profileId: string, namespace: PreferenceNamespace): Promise<ProfilePreferenceRow | null> {
    const { data, error } = await this.client
      .from('profile_preferences')
      .select('profile_id, namespace, schema_version, value, updated_at')
      .eq('profile_id', profileId)
      .eq('namespace', namespace)
      .maybeSingle();
    if (error) throw error;
    return data as ProfilePreferenceRow | null;
  }

  async upsert(row: ProfilePreferenceRow): Promise<void> {
    const { error } = await this.client
      .from('profile_preferences')
      .upsert(row, { onConflict: 'profile_id,namespace' });
    if (error) throw error;
  }
}

export function createProfilePreferencesRepository(storage: StorageLike = localStorage): ProfilePreferencesRepository {
  return new ProfilePreferencesRepository({
    storage,
    cloud: new SupabasePreferenceCloudStore(supabase),
  });
}
