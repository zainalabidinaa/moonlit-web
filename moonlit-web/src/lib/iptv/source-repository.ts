import type { IPTVChannel, IPTVPlaylist, IPTVPlaylistSource } from './models';
import { parseM3U } from './m3u-parser';
import { fetchLiveChannels, fetchUserInfo, type ResolvedCreds } from './xtream-client';
import { detectSource, middlewareCandidates } from './source-detector';

const SOURCES_KEY = (profileId: string) => `moonlit.iptvSources.${profileId}`;
const CACHE_KEY = (profileId: string) => `moonlit.iptvPlaylists.${profileId}`;
const KEY_SALT_KEY = 'moonlit-iptv-crypto-salt';
const ENC_ALGO = 'AES-GCM';
const KEY_LENGTH = 256;

export class XtreamError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'XtreamError';
  }
}

function getKeySalt(): Uint8Array {
  const saltStr = localStorage.getItem(KEY_SALT_KEY) ?? '';
  if (saltStr) {
    try {
      const bytes = Uint8Array.from(atob(saltStr), c => c.charCodeAt(0));
      if (bytes.length === 32) return bytes;
    } catch { /* regenerate on corruption */ }
  }
  const salt = crypto.getRandomValues(new Uint8Array(32));
  localStorage.setItem(KEY_SALT_KEY, btoa(String.fromCharCode(...salt)));
  return salt;
}

let _keyPromise: Promise<CryptoKey> | null = null;
let _lastSalt = '';

function getCachedKey(): Promise<CryptoKey> | null {
  const currentSalt = localStorage.getItem(KEY_SALT_KEY) ?? '';
  if (_keyPromise && currentSalt === _lastSalt) return _keyPromise;
  _keyPromise = null;
  _lastSalt = '';
  return null;
}

async function importKeyFromSalt(salt: Uint8Array): Promise<CryptoKey> {
  const material = new TextEncoder().encode(salt.reduce((s, b) => s + String.fromCharCode(b), 'moonlit-v2:'));
  return await crypto.subtle.importKey(
    'raw',
    material,
    { name: ENC_ALGO, length: KEY_LENGTH },
    false,
    ['encrypt', 'decrypt'],
  );
}

async function getOrCreateKey(): Promise<CryptoKey> {
  const salt = getKeySalt();
  const saltStr = localStorage.getItem(KEY_SALT_KEY) ?? '';
  const cached = getCachedKey();
  if (cached) return cached;

  _lastSalt = saltStr;
  const promise = importKeyFromSalt(salt)
    .catch(() => {
      const fallbackSalt = getKeySalt();
      return importKeyFromSalt(fallbackSalt);
    })
    .catch(() => {
      const emergencyKey = crypto.getRandomValues(new Uint8Array(32));
      return importKeyFromSalt(emergencyKey);
    });

  _keyPromise = promise;
  return promise;
}

async function encryptSources(sources: IPTVPlaylistSource[]): Promise<string> {
  const key = await getOrCreateKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(JSON.stringify(sources));
  const ciphertext = await crypto.subtle.encrypt({ name: ENC_ALGO, iv }, key, encoded);
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return btoa(String.fromCharCode(...combined));
}

async function decryptSources(encrypted: string): Promise<IPTVPlaylistSource[]> {
  const key = await getOrCreateKey();
  const combined = Uint8Array.from(atob(encrypted), c => c.charCodeAt(0));
  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  const plaintext = await crypto.subtle.decrypt({ name: ENC_ALGO, iv }, key, ciphertext);
  return JSON.parse(new TextDecoder().decode(plaintext));
}

export interface IPTVRepositorySnapshot {
  sources: IPTVPlaylistSource[];
  playlists: Record<string, IPTVPlaylist>;
  refreshing: Set<string>;
  isLoadingEPG: boolean;
  errorMessage: string | null;
}

export type IPTVRepositoryListener = (snap: IPTVRepositorySnapshot) => void;

export class IPTVSourceRepository {
  private _sources: IPTVPlaylistSource[] = [];
  private _playlists: Record<string, IPTVPlaylist> = {};
  private _refreshing = new Set<string>();
  private _isLoadingEPG = false;
  private _errorMessage: string | null = null;
  private _listeners = new Set<IPTVRepositoryListener>();
  private _profileId: string | null = null;

  get sources(): IPTVPlaylistSource[] { return this._sources; }
  get playlists(): Record<string, IPTVPlaylist> { return this._playlists; }
  get refreshing(): Set<string> { return new Set(this._refreshing); }
  get isLoadingEPG(): boolean { return this._isLoadingEPG; }
  get errorMessage(): string | null { return this._errorMessage; }
  get hasSources(): boolean { return this._sources.length > 0; }

  get allChannels(): IPTVChannel[] {
    return this._sources.flatMap(s => this._playlists[s.id]?.channels ?? []);
  }

  on(listener: IPTVRepositoryListener): () => void {
    this._listeners.add(listener);
    return () => { this._listeners.delete(listener); };
  }

  private emit(): void {
    const snap: IPTVRepositorySnapshot = {
      sources: [...this._sources],
      playlists: { ...this._playlists },
      refreshing: new Set(this._refreshing),
      isLoadingEPG: this._isLoadingEPG,
      errorMessage: this._errorMessage,
    };
    for (const fn of this._listeners) fn(snap);
  }

  async load(profileId: string): Promise<void> {
    this._profileId = profileId;
    this._sources = await this._loadSources();
    this._playlists = await this._loadCache();
    this.emit();

    for (const source of this._sources) {
      if (source.kind !== 'epg' && !this._playlists[source.id]) {
        await this.refresh(source);
      }
    }
  }

  async addSource(source: IPTVPlaylistSource): Promise<void> {
    this._sources.push(source);
    await this._persistSources();
    this.emit();
    if (source.kind !== 'epg') await this.refresh(source);
  }

  async updateSource(source: IPTVPlaylistSource): Promise<void> {
    const idx = this._sources.findIndex(s => s.id === source.id);
    if (idx < 0) return;
    this._sources[idx] = source;
    await this._persistSources();
    this.emit();
    if (source.kind !== 'epg') await this.refresh(source);
  }

  async removeSource(id: string): Promise<void> {
    this._sources = this._sources.filter(s => s.id !== id);
    delete this._playlists[id];
    await this._persistSources();
    await this._persistCache();
    this.emit();
  }

  async refreshAll(): Promise<void> {
    for (const source of this._sources) {
      if (source.kind !== 'epg') await this.refresh(source);
    }
  }

  async refresh(source: IPTVPlaylistSource): Promise<void> {
    if (source.kind === 'epg') return;
    this._refreshing.add(source.id);
    this.emit();
    try {
      const playlist = await this._fetchSource(source);
      this._playlists[source.id] = playlist;
      await this._persistCache();
      this._errorMessage = null;
    } catch (err) {
      this._errorMessage = err instanceof Error ? err.message : String(err);
    } finally {
      this._refreshing.delete(source.id);
      this.emit();
    }
  }

  private async _fetchSource(source: IPTVPlaylistSource): Promise<IPTVPlaylist> {
    const shape = detectSource(source);
    switch (shape.kind) {
      case 'xtream':
        return this._fetchXtream(source, shape.creds);
      case 'm3u':
        return this._fetchM3U(source, shape.url, shape.middleware);
      case 'epg':
        throw new XtreamError('EPG sources cannot be fetched as a playlist.');
      case 'invalid':
        throw new XtreamError(shape.reason);
    }
  }

  private async _fetchXtream(source: IPTVPlaylistSource, creds: ResolvedCreds): Promise<IPTVPlaylist> {
    const caps = await fetchUserInfo(creds);
    const channels = await fetchLiveChannels(creds, source.id, 'ts', caps);
    return this._makePlaylist(source, channels);
  }

  private async _fetchM3U(source: IPTVPlaylistSource, urlStr: string, middleware: boolean): Promise<IPTVPlaylist> {
    const candidates = [urlStr];
    if (middleware) candidates.push(...middlewareCandidates(urlStr));

    let lastError: Error | undefined;
    for (const candidate of candidates) {
      try {
        const text = await this._fetchText(candidate);
        if (!text.trimStart().startsWith('#EXTM3U')) continue;
        const channels = parseM3U(text, source.id);
        return this._makePlaylist(source, channels);
      } catch (err) {
        lastError = err instanceof Error ? err : new Error(String(err));
      }
    }
    throw lastError ?? new XtreamError(`No valid M3U playlist found at ${urlStr}.`);
  }

  private _makePlaylist(source: IPTVPlaylistSource, channels: IPTVChannel[]): IPTVPlaylist {
    const seen = new Set<string>();
    const groups: string[] = [];
    for (const ch of channels) {
      const g = ch.group;
      if (g && !seen.has(g)) {
        seen.add(g);
        groups.push(g);
      }
    }
    return { id: source.id, name: source.name, channels, groups, fetchedAt: Date.now() };
  }

  private async _fetchText(urlString: string): Promise<string> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30_000);
    try {
      const response = await fetch(urlString, {
        headers: { 'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20' },
        signal: controller.signal,
      });
      if (!response.ok) throw new XtreamError(`HTTP ${response.status}`);
      return await response.text();
    } finally {
      clearTimeout(timeout);
    }
  }

  private async _loadSources(): Promise<IPTVPlaylistSource[]> {
    if (!this._profileId) return [];
    const raw = localStorage.getItem(SOURCES_KEY(this._profileId));
    if (!raw) return [];
    try {
      return await decryptSources(raw);
    } catch {
      return [];
    }
  }

  private async _persistSources(): Promise<void> {
    if (!this._profileId) return;
    const encrypted = await encryptSources(this._sources);
    localStorage.setItem(SOURCES_KEY(this._profileId), encrypted);
  }

  private async _loadCache(): Promise<Record<string, IPTVPlaylist>> {
    if (!this._profileId) return {};
    const raw = localStorage.getItem(CACHE_KEY(this._profileId));
    if (!raw) return {};
    try {
      return JSON.parse(raw);
    } catch {
      return {};
    }
  }

  private async _persistCache(): Promise<void> {
    if (!this._profileId) return;
    localStorage.setItem(CACHE_KEY(this._profileId), JSON.stringify(this._playlists));
  }
}

export const iptvRepository = new IPTVSourceRepository();
