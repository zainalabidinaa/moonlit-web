import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { useAuth } from '@/app/AuthProvider';
import { usePlayer } from '@/app/PlayerProvider';
import { getStreamingServerUrl } from '@/lib/config';
import { getLastStream, saveLastStream } from '@/lib/last-stream';
import { fetchIntroTimestamps } from '@/lib/player/intro-timestamps';
import {
  normalizePlayerLaunch,
  type NormalizedPlayerLaunch,
  type PlaybackPlan,
  type PlayerLaunch,
} from '@/lib/player/contracts';
import { detectPlaybackEnvironment } from '@/lib/player/routing';
import {
  createProfilePreferencesRepository,
  DEFAULT_PLAYER_PREFERENCES,
  type PlayerPreferences,
} from '@/lib/preferences/profile-preferences';
import { getPlayableStreamUrl } from '@/lib/player-utils';
import { mpvAvailable } from '@/lib/platform/mpv';
import { updateWatchProgress } from '@/lib/services/api';
import { cacheStreams, getCachedStreams } from '@/lib/stream-cache';
import { fetchStreamsFromAll, fetchSubtitlesFromAll, type SubtitleItem } from '@/lib/stremio';
import type { StreamItem } from '@/lib/types';
import { applyPlayerPreferences } from './PlayerShell.preferences';
import { getIntroLookup, selectIntroConfig, type IntroRange } from './PlayerShell.intro';
import { selectStreamPlayback, type StreamPlaybackSelection } from './PlayerShell.selection';
import {
  UnifiedPlayer,
  type PlaybackHandoff,
  type PlayerAdapterFactory,
  type PlayerIntro,
} from './UnifiedPlayer';
import { UpNextPanel } from './UpNextPanel';

interface PlayerShellProps {
  launch: PlayerLaunch | NormalizedPlayerLaunch;
  onBack: () => void;
  onVideoReady: () => void;
  onError: () => void;
  onDesktop?: () => void;
  profileId?: string;
  createAdapter?: PlayerAdapterFactory;
}

interface MpvAvailability {
  checked: boolean;
  available: boolean;
}

export const PLAYER_RESOLUTION_TIMEOUT_MS = 15_000;
export const PLAYER_MPV_PROBE_TIMEOUT_MS = 3_000;

function streamsFromLaunch(launch: NormalizedPlayerLaunch): StreamItem[] {
  const streams = [...(launch.streams ?? [])];
  if (!launch.streamUrl) return streams;
  const match = streams.find(stream => stream.url === launch.streamUrl || stream.externalUrl === launch.streamUrl);
  if (match) {
    if (!launch.requestHeaders) return streams;
    return streams.map(stream => stream === match ? {
      ...stream,
      behaviorHints: {
        ...stream.behaviorHints,
        proxyHeaders: { request: launch.requestHeaders },
      },
    } : stream);
  }
  return [{
    url: launch.streamUrl,
    addonName: 'Direct',
    behaviorHints: launch.requestHeaders
      ? { proxyHeaders: { request: launch.requestHeaders } }
      : undefined,
  }, ...streams];
}

function unavailableSelection(detail: string): StreamPlaybackSelection {
  const stream: StreamItem = { title: 'No playable source' };
  const plan: PlaybackPlan = {
    outcome: 'unsupported',
    label: 'Not playable',
    detail,
    stream,
    attempts: [],
  };
  return { stream, plan };
}

export function PlayerShell({
  launch,
  onBack,
  onVideoReady,
  onError,
  onDesktop,
  profileId,
  createAdapter,
}: PlayerShellProps) {
  const { addons, currentProfile } = useAuth();
  const { setAllStreams, setActiveStream, registerStreamSwitchHandler } = usePlayer();
  const normalizedLaunch = useMemo(() => normalizePlayerLaunch(launch), [launch]);
  const cacheKey = `${normalizedLaunch.type}:${normalizedLaunch.id}`;
  const activeProfileId = profileId ?? currentProfile?.id ?? null;
  const launchStreams = useMemo(() => streamsFromLaunch(normalizedLaunch), [normalizedLaunch]);
  const initialStreams = useMemo(
    () => launchStreams.length > 0 ? launchStreams : getCachedStreams(cacheKey) ?? [],
    [cacheKey, launchStreams],
  );
  const [streams, setStreams] = useState<StreamItem[]>(initialStreams);
  const [streamsResolved, setStreamsResolved] = useState(initialStreams.length > 0);
  const [subtitles, setSubtitles] = useState<SubtitleItem[]>(normalizedLaunch.subtitles ?? []);
  const [mpv, setMpv] = useState<MpvAvailability>({ checked: false, available: false });
  const [selection, setSelection] = useState<StreamPlaybackSelection | null>(null);
  const progressWriteRef = useRef<Promise<unknown>>(Promise.resolve());
  const [handoff, setHandoff] = useState<PlaybackHandoff | null>(null);
  const [introResult, setIntroResult] = useState<{
    key: string;
    range: IntroRange | null;
  } | null>(null);
  const failedUrlsRef = useRef(new Set<string>());
  const latestHandoffRef = useRef<PlaybackHandoff>({
    position: normalizedLaunch.startPosition,
    tracks: normalizedLaunch.preferredTracks,
  });

  const preferencesRepository = useMemo(() => {
    if (typeof localStorage === 'undefined') return null;
    return createProfilePreferencesRepository(localStorage);
  }, []);
  const cachedPreferences = useMemo(
    () => preferencesRepository?.loadCached(activeProfileId, 'player').value ?? DEFAULT_PLAYER_PREFERENCES,
    [activeProfileId, preferencesRepository],
  );
  const [loadedPreferences, setLoadedPreferences] = useState<{
    profileId: string | null;
    value: PlayerPreferences;
  } | null>(null);
  const preferences = loadedPreferences?.profileId === activeProfileId
    ? loadedPreferences.value
    : cachedPreferences;

  useEffect(() => {
    if (!preferencesRepository) return;
    let active = true;
    void preferencesRepository.load(activeProfileId, 'player').then(result => {
      if (active) setLoadedPreferences({ profileId: activeProfileId, value: result.value });
    });
    return () => { active = false; };
  }, [activeProfileId, preferencesRepository]);

  const applied = useMemo(
    () => applyPlayerPreferences(normalizedLaunch, preferences),
    [normalizedLaunch, preferences],
  );

  const introLookup = useMemo(() => getIntroLookup(applied.launch), [applied.launch]);
  const introLookupKey = introLookup
    ? `${introLookup.imdbId}:${introLookup.season ?? ''}:${introLookup.episode ?? ''}`
    : null;

  useEffect(() => {
    if (!introLookup || !introLookupKey || !preferences.useIntroDb) return;
    let active = true;
    void fetchIntroTimestamps(introLookup.imdbId, introLookup.season, introLookup.episode).then(range => {
      if (active) setIntroResult({ key: introLookupKey, range });
    });
    return () => { active = false; };
  }, [introLookup, introLookupKey, preferences.useIntroDb]);

  const intro = useMemo<PlayerIntro | null>(() => {
    if (!introLookup || !introLookupKey) return null;
    if (!preferences.useIntroDb) return selectIntroConfig(null, preferences);
    if (introResult?.key !== introLookupKey) return null;
    return selectIntroConfig(introResult.range, preferences);
  }, [introLookup, introLookupKey, introResult, preferences]);

  useEffect(() => {
    let active = true;
    let settled = false;
    const timer = setTimeout(() => {
      if (!active || settled) return;
      settled = true;
      setMpv({ checked: true, available: false });
    }, PLAYER_MPV_PROBE_TIMEOUT_MS);
    void mpvAvailable().then(available => {
      if (!active || settled) return;
      settled = true;
      clearTimeout(timer);
      setMpv({ checked: true, available });
      if (available) onDesktop?.();
    }).catch(() => {
      if (!active || settled) return;
      settled = true;
      clearTimeout(timer);
      setMpv({ checked: true, available: false });
    });
    return () => { active = false; clearTimeout(timer); };
  }, [onDesktop]);

  useEffect(() => {
    if (streamsResolved) return;
    let active = true;
    let settled = false;
    const timer = setTimeout(() => {
      if (!active || settled) return;
      settled = true;
      setStreamsResolved(true);
    }, PLAYER_RESOLUTION_TIMEOUT_MS);
    void fetchStreamsFromAll(normalizedLaunch.type, normalizedLaunch.id, addons)
      .then(fetched => {
        if (!active || settled) return;
        settled = true;
        clearTimeout(timer);
        if (fetched.length > 0) cacheStreams(cacheKey, fetched);
        setStreams(fetched);
        setStreamsResolved(true);
      })
      .catch(() => {
        if (!active || settled) return;
        settled = true;
        clearTimeout(timer);
        setStreamsResolved(true);
      });
    return () => { active = false; clearTimeout(timer); };
  }, [addons, cacheKey, normalizedLaunch.id, normalizedLaunch.type, streamsResolved]);

  useEffect(() => {
    if ((normalizedLaunch.subtitles?.length ?? 0) > 0) return;
    let active = true;
    void fetchSubtitlesFromAll(normalizedLaunch.type, normalizedLaunch.id, addons)
      .then(fetched => {
        if (active && fetched.length > 0) setSubtitles(fetched);
      })
      .catch(() => undefined);
    return () => { active = false; };
  }, [addons, normalizedLaunch.id, normalizedLaunch.subtitles, normalizedLaunch.type]);

  const environment = useMemo(() => ({
    ...detectPlaybackEnvironment(),
    mpv: mpv.available,
  }), [mpv.available]);
  const selectionOptions = useMemo(() => ({
    serverUrl: getStreamingServerUrl(),
    isLive: applied.launch.isLive,
    enginePreference: applied.enginePreference,
    showOnlyCompatibleFormats: applied.showOnlyCompatibleFormats,
  }), [
    applied.enginePreference,
    applied.launch.isLive,
    applied.showOnlyCompatibleFormats,
  ]);

  const commitSelection = useCallback((next: StreamPlaybackSelection, nextHandoff?: PlaybackHandoff) => {
    setSelection(next);
    if (nextHandoff) {
      latestHandoffRef.current = nextHandoff;
      setHandoff(nextHandoff);
    }
    const url = getPlayableStreamUrl(next.stream);
    if (url && next.plan.outcome === 'play-here') {
      saveLastStream(cacheKey, {
        url,
        addonName: next.stream.addonName,
        streamTitle: next.stream.title ?? next.stream.name,
      });
    }
  }, [cacheKey]);

  useEffect(() => {
    if (!mpv.checked || !streamsResolved || selection) return;
    const candidates = streams.filter(stream => {
      const url = getPlayableStreamUrl(stream);
      return !url || !failedUrlsRef.current.has(url);
    });
    const next = selectStreamPlayback(candidates, environment, {
      ...selectionOptions,
      explicitUrl: normalizedLaunch.streamUrl,
      rememberedUrl: getLastStream(cacheKey)?.url,
    });
    commitSelection(next ?? unavailableSelection(
      streams.length === 0
        ? 'No sources were returned. Check the active profile’s addons.'
        : 'No compatible source is available with the active profile settings.',
    ));
  }, [
    cacheKey,
    commitSelection,
    environment,
    mpv.checked,
    normalizedLaunch.streamUrl,
    selection,
    selectionOptions,
    streams,
    streamsResolved,
  ]);

  useEffect(() => {
    setAllStreams(streams);
    if (selection) setActiveStream(selection.stream);
  }, [selection, setActiveStream, setAllStreams, streams]);

  const handleStreamSwitch = useCallback((stream: StreamItem, nextHandoff = latestHandoffRef.current) => {
    const url = getPlayableStreamUrl(stream);
    if (url) failedUrlsRef.current.delete(url);
    const next = selectStreamPlayback([stream], environment, {
      ...selectionOptions,
      explicitUrl: url,
      showOnlyCompatibleFormats: false,
    });
    if (next) commitSelection(next, nextHandoff);
  }, [commitSelection, environment, selectionOptions]);

  useEffect(() => registerStreamSwitchHandler(stream => handleStreamSwitch(stream)), [
    handleStreamSwitch,
    registerStreamSwitchHandler,
  ]);

  const handleTerminalError = useCallback((_message: string, nextHandoff: PlaybackHandoff) => {
    const failedUrl = selection ? getPlayableStreamUrl(selection.stream) : undefined;
    if (failedUrl) failedUrlsRef.current.add(failedUrl);
    const candidates = streams.filter(stream => {
      const url = getPlayableStreamUrl(stream);
      return !url || !failedUrlsRef.current.has(url);
    });
    const next = selectStreamPlayback(candidates, environment, {
      ...selectionOptions,
      rememberedUrl: undefined,
      explicitUrl: undefined,
    });
    if (next?.plan.outcome === 'play-here') {
      commitSelection(next, nextHandoff);
      return;
    }
    if (next) commitSelection(next, nextHandoff);
    onError();
  }, [commitSelection, environment, onError, selection, selectionOptions, streams]);

  const handleProgress = useCallback((position: number, duration: number, completed: boolean) => {
    latestHandoffRef.current = { ...latestHandoffRef.current, position };
    if (!activeProfileId || duration <= 0) return;
    progressWriteRef.current = progressWriteRef.current
      .catch(() => undefined)
      .then(() => updateWatchProgress(
        activeProfileId,
        normalizedLaunch.id,
        normalizedLaunch.type,
        position,
        duration,
        completed,
        normalizedLaunch.metadata.title,
        normalizedLaunch.metadata.poster,
      ));
  }, [activeProfileId, normalizedLaunch.id, normalizedLaunch.metadata.poster, normalizedLaunch.metadata.title, normalizedLaunch.type]);

  const playbackLaunch = useMemo<NormalizedPlayerLaunch>(() => ({
    ...applied.launch,
    startPosition: handoff?.position ?? applied.launch.startPosition,
    preferredTracks: handoff?.tracks ?? applied.launch.preferredTracks,
  }), [applied.launch, handoff]);

  return (
    <UnifiedPlayer
      launch={playbackLaunch}
      plan={selection?.plan ?? null}
      currentStream={selection?.stream ?? null}
      streams={streams}
      subtitles={subtitles}
      createAdapter={createAdapter}
      onBack={onBack}
      onSwitchStream={handleStreamSwitch}
      onReady={onVideoReady}
      onError={handleTerminalError}
      onProgress={handleProgress}
      onDesktop={onDesktop}
      intro={intro}
      upNextContent={normalizedLaunch.type === 'series'
        ? close => (
          <UpNextPanel
            mediaId={normalizedLaunch.id}
            mediaType={normalizedLaunch.type}
            onClose={close}
            embedded
          />
        )
        : undefined}
    />
  );
}
