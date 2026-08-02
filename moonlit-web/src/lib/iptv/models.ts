export type IPTVSourceKind = 'm3u' | 'xtream' | 'epg';

export const IPTV_SOURCE_KIND_LABELS: Record<IPTVSourceKind, string> = {
  m3u: 'M3U Playlist',
  xtream: 'Xtream Codes',
  epg: 'EPG Only',
};

export interface XtreamCredentials {
  server: string;
  username: string;
  password: string;
}

export interface IPTVPlaylistSource {
  id: string;
  name: string;
  url: string;
  epgUrl?: string;
  kind: IPTVSourceKind;
  xtream?: XtreamCredentials;
  createdAt: number;
}

export interface IPTVChannel {
  id: string;
  readonly tvgId?: string;
  readonly name: string;
  readonly logo?: string;
  readonly group?: string;
  readonly url: string;
  readonly catchupType?: string;
  readonly catchupSource?: string;
  readonly catchupDays?: number;
  readonly headers?: Record<string, string>;
}

export interface IPTVPlaylist {
  id: string;
  name: string;
  channels: IPTVChannel[];
  groups: string[];
  fetchedAt: number;
}

export const PLAYLIST_UNGROUPED = 'Ungrouped';

export function channelsByGroup(playlist: IPTVPlaylist): { group: string; channels: IPTVChannel[] }[] {
  const buckets = new Map<string, IPTVChannel[]>();
  for (const channel of playlist.channels) {
    const key = channel.group || PLAYLIST_UNGROUPED;
    const list = buckets.get(key) || [];
    list.push(channel);
    buckets.set(key, list);
  }
  const ordered: { group: string; channels: IPTVChannel[] }[] = [];
  for (const group of playlist.groups) {
    const items = buckets.get(group);
    if (items && items.length) {
      ordered.push({ group, channels: items });
      buckets.delete(group);
    }
  }
  const ungrouped = buckets.get(PLAYLIST_UNGROUPED);
  if (ungrouped && ungrouped.length) {
    ordered.push({ group: PLAYLIST_UNGROUPED, channels: ungrouped });
  }
  return ordered;
}

export interface EPGProgram {
  channelTvgId: string;
  title: string;
  description?: string;
  category?: string;
  iconUrl?: string;
  startMs: number;
  endMs: number;
}

export function epgProgramId(p: EPGProgram): string {
  return `${p.channelTvgId}-${Math.floor(p.startMs)}`;
}

export interface EPGChannelMeta {
  displayName?: string;
  icon?: string;
}

export interface EPGParseResult {
  programs: EPGProgram[];
  channelMeta: Record<string, EPGChannelMeta>;
}

export interface EPGNowNext {
  current: EPGProgram | null;
  next: EPGProgram | null;
}

export const EMPTY_NOW_NEXT: EPGNowNext = { current: null, next: null };

export interface XtreamShortEpgEntry {
  title: string;
  description?: string;
  startMs: number;
  endMs: number;
}

export interface XtreamServerCaps {
  allowedFormats: string[];
  streamBase: string;
}

export type CatchupType =
  | 'default'
  | 'append'
  | 'shift'
  | 'flussonic'
  | 'xtream';
