import { useEffect, useEffectEvent, useMemo, useRef, useState, type ReactNode } from 'react';

import type { SubtitleItem } from '@/lib/stremio';
import type { StreamItem } from '@/lib/types';
import type {
  NormalizedPlayerLaunch,
  PlaybackAttempt,
  PlaybackPlan,
  PlayerAdapter,
  PlayerAdapterCapabilities,
  PlayerTrackSelection,
} from '@/lib/player/contracts';
import { playerTrackIdentity } from '@/lib/player/contracts';
import { PlayerSession, type PlayerSessionState } from '@/lib/player/session';
import { HtmlVideoAdapter } from '@/lib/player/adapters/html-video';
import { MediabunnyAdapter } from '@/lib/player/adapters/mediabunny';
import { WebCodecsAdapter } from '@/lib/player/adapters/webcodecs';
import { MpvAdapter } from '@/lib/player/adapters/mpv';
import {
  getSubtitlePreferenceStyle,
  loadSubtitlePreferences,
  subscribeSubtitlePreferences,
  type SubtitlePreferences,
} from '@/lib/subtitle-preferences';
import { PlayerChrome, type PlayerChromeController, type PlayerChromeState } from './PlayerChrome';

const unavailableCapabilities: PlayerAdapterCapabilities = {
  seek: false,
  volume: false,
  playbackRate: false,
  fullscreen: false,
  pictureInPicture: false,
  remotePlayback: false,
  audioTracks: false,
  subtitleTracks: false,
  seekPreview: false,
  screenshot: false,
  anime4k: false,
};

export interface PlayerHostElements {
  root: HTMLDivElement;
  video: HTMLVideoElement;
  canvas: HTMLCanvasElement;
}

export type PlayerAdapterFactory = (attempt: PlaybackAttempt, hosts: PlayerHostElements) => PlayerAdapter;

export interface PlaybackHandoff {
  position: number;
  tracks: PlayerTrackSelection;
}

export interface PlayerIntro {
  start: number;
  end: number;
  showButton: boolean;
  autoSkip: boolean;
}

export interface UnifiedPlayerProps {
  launch: NormalizedPlayerLaunch;
  plan: PlaybackPlan | null;
  currentStream: StreamItem | null;
  streams: StreamItem[];
  subtitles: SubtitleItem[];
  createAdapter?: PlayerAdapterFactory;
  onBack: () => void;
  onSwitchStream: (stream: StreamItem, handoff: PlaybackHandoff) => void;
  onReady?: () => void;
  onError?: (message: string, handoff: PlaybackHandoff) => void;
  onProgress?: (position: number, duration: number, completed: boolean) => void;
  onDesktop?: () => void;
  upNextContent?: ReactNode | ((close: () => void) => ReactNode);
  intro?: PlayerIntro | null;
}

function createDefaultAdapter(attempt: PlaybackAttempt, hosts: PlayerHostElements): PlayerAdapter {
  switch (attempt.adapter) {
    case 'html-video': return new HtmlVideoAdapter(hosts.video, hosts.root);
    case 'mediabunny': return new MediabunnyAdapter(hosts.video, hosts.root);
    case 'webcodecs': return new WebCodecsAdapter(hosts.canvas, hosts.root);
    case 'mpv': return new MpvAdapter();
  }
}

function chromeState(
  sessionState: PlayerSessionState | null,
  plan: PlaybackPlan | null,
  resumePosition: number,
): PlayerChromeState {
  const adapter = sessionState?.adapterState;
  const phase = !plan
    ? 'resolving'
    : sessionState?.phase ?? (plan.outcome === 'play-here' ? 'loading' : plan.outcome);
  return {
    phase,
    position: adapter?.position ?? resumePosition,
    duration: adapter?.duration ?? 0,
    buffered: adapter?.buffered ?? 0,
    paused: adapter?.paused ?? true,
    muted: adapter?.muted ?? false,
    volume: adapter?.volume ?? 1,
    playbackRate: adapter?.playbackRate ?? 1,
    fullscreen: adapter?.fullscreen ?? false,
    pictureInPicture: adapter?.pictureInPicture ?? false,
    selectedAudioId: adapter?.selectedAudioId ?? null,
    selectedSubtitleId: adapter?.selectedSubtitleId ?? 'off',
    audioTracks: adapter?.audioTracks ?? [],
    subtitleTracks: adapter?.subtitleTracks ?? [],
    capabilities: sessionState?.capabilities ?? unavailableCapabilities,
    error: sessionState?.error ?? (plan && plan.outcome !== 'play-here' ? plan.detail : null),
    routeLabel: sessionState?.attempt?.method ?? plan?.label ?? 'Checking',
    routeDetail: plan?.detail ?? 'Finding the best playable source.',
    previewSourceId: sessionState?.attempt?.id ?? plan?.attempts[0]?.id ?? plan?.externalUrl ?? plan?.label ?? 'none',
  };
}

function playbackHandoff(
  session: PlayerSession | null,
  sessionState: PlayerSessionState | null,
  launch: NormalizedPlayerLaunch,
): PlaybackHandoff {
  const preserved = session?.getPlaybackHandoff();
  if (preserved) return preserved;
  const current = sessionState?.adapterState;
  const audioTrack = current?.audioTracks.find(track => track.id === current.selectedAudioId);
  const subtitleTrack = current?.subtitleTracks.find(track => track.id === current.selectedSubtitleId);
  return {
    position: current?.position ?? launch.startPosition,
    tracks: {
      audioId: null,
      subtitleId: current?.selectedSubtitleId === 'off' ? 'off' : null,
      audioLanguage: audioTrack?.language ?? launch.preferredTracks.audioLanguage,
      subtitleLanguage: subtitleTrack?.language ?? launch.preferredTracks.subtitleLanguage,
      audioIdentity: audioTrack ? playerTrackIdentity(audioTrack, current?.audioTracks ?? []) : launch.preferredTracks.audioIdentity ?? null,
      subtitleIdentity: subtitleTrack ? playerTrackIdentity(subtitleTrack, current?.subtitleTracks ?? []) : launch.preferredTracks.subtitleIdentity ?? null,
    },
  };
}

export function UnifiedPlayer({
  launch,
  plan,
  currentStream,
  streams,
  subtitles,
  createAdapter = createDefaultAdapter,
  onBack,
  onSwitchStream,
  onReady,
  onError,
  onProgress,
  onDesktop,
  upNextContent,
  intro,
}: UnifiedPlayerProps) {
  const rootRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sessionRef = useRef<PlayerSession | null>(null);
  const sessionGenerationRef = useRef(0);
  const teardownQueueRef = useRef<Promise<void>>(Promise.resolve());
  const stateRef = useRef<PlayerSessionState | null>(null);
  const [sessionState, setSessionState] = useState<PlayerSessionState | null>(null);
  const [subtitlePreferences, setSubtitlePreferences] = useState<SubtitlePreferences>(loadSubtitlePreferences);
  const readyAttemptRef = useRef<string | null>(null);
  const errorRef = useRef<string | null>(null);
  const endedRef = useRef(false);
  const introSkippedRef = useRef(false);

  useEffect(() => subscribeSubtitlePreferences(setSubtitlePreferences), []);

  const startSession = useEffectEvent((session: PlayerSession) => {
    void session.start({
      position: launch.startPosition,
      tracks: launch.preferredTracks,
      subtitles,
    });
  });

  useEffect(() => {
    const generation = sessionGenerationRef.current + 1;
    sessionGenerationRef.current = generation;
    let active = true;
    let session: PlayerSession | null = null;
    let unsubscribe: (() => void) | null = null;
    void (async () => {
      await teardownQueueRef.current;
      if (!active || generation !== sessionGenerationRef.current) return;
      if (!plan || !rootRef.current || !videoRef.current || !canvasRef.current) {
        stateRef.current = null;
        setSessionState(null);
        return;
      }
      const hosts: PlayerHostElements = {
        root: rootRef.current,
        video: videoRef.current,
        canvas: canvasRef.current,
      };
      session = new PlayerSession(plan, {
        createAdapter: attempt => createAdapter(attempt, hosts),
      });
      sessionRef.current = session;
      unsubscribe = session.subscribe(next => {
        if (!active) return;
        stateRef.current = next;
        setSessionState(next);
      });
      readyAttemptRef.current = null;
      errorRef.current = null;
      endedRef.current = false;
      startSession(session);
    })();
    return () => {
      active = false;
      unsubscribe?.();
      if (!session) return;
      if (sessionRef.current === session) sessionRef.current = null;
      const retiringSession = session;
      teardownQueueRef.current = teardownQueueRef.current
        .then(() => retiringSession.destroy())
        .catch(() => undefined);
    };
  }, [createAdapter, plan]);

  useEffect(() => {
    void sessionRef.current?.updateSubtitles(subtitles);
  }, [subtitles]);

  useEffect(() => {
    introSkippedRef.current = false;
  }, [intro?.end, intro?.start, plan]);

  useEffect(() => {
    const attemptId = sessionState?.attempt?.id;
    if (!attemptId) return;
    if ((sessionState.phase === 'ready' || sessionState.phase === 'playing' || sessionState.phase === 'paused') && readyAttemptRef.current !== attemptId) {
      readyAttemptRef.current = attemptId;
      onReady?.();
    }
  }, [onReady, sessionState?.attempt?.id, sessionState?.phase]);

  useEffect(() => {
    if (sessionState?.attempt?.adapter === 'mpv') onDesktop?.();
  }, [onDesktop, sessionState?.attempt?.adapter]);

  useEffect(() => {
    if (sessionState?.plan !== plan) return;
    if (sessionState?.phase !== 'error' || !sessionState.error || errorRef.current === sessionState.error) return;
    errorRef.current = sessionState.error;
    onError?.(sessionState.error, playbackHandoff(sessionRef.current, stateRef.current, launch));
  }, [launch, onError, plan, sessionState?.error, sessionState?.phase, sessionState?.plan]);

  useEffect(() => {
    if (!onProgress) return;
    const timer = setInterval(() => {
      const current = stateRef.current;
      if (endedRef.current || current?.phase === 'ended') return;
      const adapterState = current?.adapterState;
      if (adapterState && adapterState.duration > 0) onProgress(adapterState.position, adapterState.duration, false);
    }, 10_000);
    return () => clearInterval(timer);
  }, [onProgress]);

  useEffect(() => {
    const adapterState = sessionState?.adapterState;
    if (!onProgress || sessionState?.phase !== 'ended' || !adapterState || endedRef.current) return;
    endedRef.current = true;
    onProgress(adapterState.position, adapterState.duration, true);
  }, [onProgress, sessionState?.adapterState, sessionState?.phase]);

  const introPosition = sessionState?.adapterState?.position ?? launch.startPosition;
  const introActive = !!intro
    && intro.end > intro.start
    && introPosition >= intro.start
    && introPosition < intro.end;

  useEffect(() => {
    if (!intro?.autoSkip || !introActive || introSkippedRef.current || !sessionState?.capabilities?.seek) return;
    introSkippedRef.current = true;
    void sessionRef.current?.seek(intro.end);
  }, [intro?.autoSkip, intro?.end, introActive, sessionState?.capabilities?.seek]);

  const controller = useMemo<PlayerChromeController>(() => ({
    play: () => {
      if (stateRef.current?.phase === 'ended') endedRef.current = false;
      sessionRef.current?.play();
    },
    pause: () => sessionRef.current?.pause(),
    seek: position => sessionRef.current?.seek(position),
    setVolume: volume => sessionRef.current?.setVolume(volume),
    setMuted: muted => sessionRef.current?.setMuted(muted),
    setPlaybackRate: rate => sessionRef.current?.setPlaybackRate(rate),
    setFullscreen: fullscreen => sessionRef.current?.setFullscreen(fullscreen),
    setPictureInPicture: enabled => sessionRef.current?.setPictureInPicture(enabled),
    requestRemotePlayback: () => sessionRef.current?.requestRemotePlayback(),
    requestSeekPreview: (position, signal) => sessionRef.current?.requestSeekPreview(position, signal) ?? null,
    selectAudioTrack: id => sessionRef.current?.selectAudioTrack(id),
    selectSubtitleTrack: id => sessionRef.current?.selectSubtitleTrack(id),
    openAudioPanel: () => sessionRef.current?.openAudioPanel(),
    retry: () => sessionRef.current?.retry(),
  }), []);

  const uiState = chromeState(sessionState, plan, launch.startPosition);
  const activeAdapter = sessionState?.attempt?.adapter ?? null;
  return (
    <div
      ref={rootRef}
      data-testid="unified-player"
      data-active-adapter={activeAdapter ?? 'none'}
      className={`absolute inset-0 overflow-hidden ${activeAdapter === 'mpv' ? 'bg-transparent' : 'bg-black'}`}
      style={getSubtitlePreferenceStyle(subtitlePreferences)}
    >
      <video
        ref={videoRef}
        data-testid="player-video-host"
        className={`moonlit-native-subtitles absolute inset-0 h-full w-full object-contain ${(activeAdapter === 'html-video' || activeAdapter === 'mediabunny') ? 'block' : 'hidden'}`}
      />
      <canvas
        ref={canvasRef}
        data-testid="player-canvas-host"
        className={`absolute inset-0 h-full w-full object-contain ${activeAdapter === 'webcodecs' ? 'block' : 'hidden'}`}
      />
      <PlayerChrome
        state={uiState}
        controller={controller}
        metadata={launch.metadata}
        mediaId={launch.id}
        mediaType={launch.type}
        currentStream={currentStream ?? { title: 'Resolving source' }}
        streams={streams}
        subtitles={subtitles}
        resumePosition={launch.startPosition}
        onBack={onBack}
        onSwitchStream={stream => onSwitchStream(stream, playbackHandoff(sessionRef.current, stateRef.current, launch))}
        upNextContent={upNextContent}
        skipIntro={intro?.showButton && introActive ? { to: intro.end } : null}
        externalUrl={plan?.externalUrl}
      />
    </div>
  );
}
