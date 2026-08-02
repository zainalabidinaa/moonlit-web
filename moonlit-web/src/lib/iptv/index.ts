export type {
  IPTVSourceKind,
  XtreamCredentials,
  IPTVPlaylistSource,
  IPTVChannel,
  IPTVPlaylist,
  EPGProgram,
  EPGChannelMeta,
  EPGParseResult,
  EPGNowNext,
  XtreamShortEpgEntry,
  XtreamServerCaps,
  CatchupType,
} from './models';
export {
  IPTV_SOURCE_KIND_LABELS,
  PLAYLIST_UNGROUPED,
  channelsByGroup,
  EMPTY_NOW_NEXT,
  epgProgramId,
} from './models';
export { parseM3U, deriveEpgUrls } from './m3u-parser';
export {
  XtreamError,
  resolveCreds,
  parseUrl,
  buildLiveStreamURL,
  fetchUserInfo,
  fetchLiveChannels,
  fetchShortEpg,
  type ResolvedCreds,
} from './xtream-client';
export { parseXMLTV, fetchAndParseXMLTV, parseXmltvTime } from './xmltv-parser';
export { detectCatchupType, channelHasCatchup, buildCatchupURL } from './catchup';
export { EPGIndex } from './epg-index';
export {
  detectSource,
  credsFromSource,
  middlewareCandidates,
  type IPTVProviderShape,
} from './source-detector';
export {
  IPTVSourceRepository,
  iptvRepository,
  type IPTVRepositorySnapshot,
  type IPTVRepositoryListener,
} from './source-repository';
