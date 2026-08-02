import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import {
  Airplay,
  ArrowLeft,
  Captions,
  Check,
  ChevronDown,
  Headphones,
  ListVideo,
  Maximize,
  Minimize,
  Pause,
  PictureInPicture2,
  Play,
  RotateCcw,
  RotateCw,
  SkipBack,
  SkipForward,
  Volume1,
  Volume2,
  VolumeX,
  X,
} from 'lucide-react';

import type { SubtitleItem } from '@/lib/stremio';
import type { StreamItem } from '@/lib/types';
import type {
  PlayerAdapterCapabilities,
  PlayerMetadata,
  PlayerSeekPreview,
  PlayerTrack,
} from '@/lib/player/contracts';

export const PLAYER_AUTO_HIDE_MS = 2_400;
export const PLAYER_CHROME_FADE_MS = 180;
export const PLAYER_SEEK_PREVIEW_DEBOUNCE_MS = 100;

export interface PlayerChromeState {
  phase: 'idle' | 'resolving' | 'loading' | 'ready' | 'playing' | 'paused' | 'buffering' | 'ended' | 'error' | 'external' | 'unsupported';
  position: number;
  duration: number;
  buffered: number;
  paused: boolean;
  muted: boolean;
  volume: number;
  playbackRate: number;
  fullscreen: boolean;
  pictureInPicture: boolean;
  selectedAudioId: string | number | null;
  selectedSubtitleId: string | number | 'off' | null;
  audioTracks: PlayerTrack[];
  subtitleTracks: PlayerTrack[];
  capabilities: PlayerAdapterCapabilities;
  error: string | null;
  routeLabel: string;
  routeDetail: string;
}

export interface PlayerChromeController {
  play(): void | Promise<void>;
  pause(): void | Promise<void>;
  seek(position: number): void | Promise<void>;
  setVolume(volume: number): void | Promise<void>;
  setMuted(muted: boolean): void | Promise<void>;
  setPlaybackRate(rate: number): void | Promise<void>;
  setFullscreen(fullscreen: boolean): void | Promise<void>;
  setPictureInPicture(enabled: boolean): void | Promise<void>;
  requestRemotePlayback?(): void | Promise<void>;
  selectAudioTrack(id: string | number): void | Promise<void>;
  selectSubtitleTrack(id: string | number | 'off'): void | Promise<void>;
  openAudioPanel(): void | Promise<void>;
  requestSeekPreview?(position: number, signal?: AbortSignal): PlayerSeekPreview | null | Promise<PlayerSeekPreview | null>;
  retry(): void | Promise<void>;
}

type Panel = 'sources' | 'audio' | 'subtitles' | 'speed' | 'up-next' | null;

export interface PlayerChromeProps {
  state: PlayerChromeState;
  controller: PlayerChromeController;
  metadata: PlayerMetadata;
  mediaId: string;
  mediaType: string;
  currentStream: StreamItem;
  streams: StreamItem[];
  subtitles: SubtitleItem[];
  resumePosition?: number;
  onBack: () => void;
  onSwitchStream: (stream: StreamItem) => void;
  onPreviousEpisode?: () => void;
  onNextEpisode?: () => void;
  upNextContent?: ReactNode | ((close: () => void) => ReactNode);
  skipIntro?: { to: number; label?: string } | null;
  externalUrl?: string;
}

function fmt(value: number): string {
  const seconds = Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const rest = seconds % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, '0')}:${String(rest).padStart(2, '0')}`
    : `${minutes}:${String(rest).padStart(2, '0')}`;
}

function streamLabel(stream: StreamItem, index: number): string {
  return stream.title || stream.name || stream.addonName || `Source ${index + 1}`;
}

function IconButton({
  label,
  disabled = false,
  active = false,
  onClick,
  children,
  className = '',
}: {
  label: string;
  disabled?: boolean;
  active?: boolean;
  onClick?: () => void;
  children: ReactNode;
  className?: string;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      aria-pressed={active || undefined}
      onClick={onClick}
      className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-ml-ctl text-player-ink transition-[color,background-color,transform] duration-150 active:scale-[0.96] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white disabled:cursor-not-allowed disabled:opacity-30 ${active ? 'bg-white/15' : 'hover:bg-white/10'} ${className}`}
    >
      {children}
    </button>
  );
}

function PanelFrame({
  title,
  width,
  onClose,
  children,
  fullHeight = false,
}: {
  title: string;
  width: string;
  onClose: () => void;
  children: ReactNode;
  fullHeight?: boolean;
}) {
  const dialogRef = useRef<HTMLElement>(null);
  const openerRef = useRef<HTMLElement | null>(null);

  useLayoutEffect(() => {
    openerRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const initial = dialogRef.current?.querySelector<HTMLElement>('button:not(:disabled), [href], [tabindex="0"]');
    initial?.focus();
    return () => openerRef.current?.focus();
  }, []);

  const handleKeyDown = (event: React.KeyboardEvent<HTMLElement>) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      onClose();
      return;
    }
    if (event.key !== 'Tab') return;
    const focusable = [...(dialogRef.current?.querySelectorAll<HTMLElement>('button:not(:disabled), [href], input:not(:disabled), [tabindex="0"]') ?? [])];
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };

  return (
    <div className="pointer-events-auto absolute inset-0 z-40 flex items-end justify-center bg-black/60 sm:items-center sm:justify-end" onMouseDown={event => {
      if (event.target === event.currentTarget) onClose();
    }}>
      <section
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        data-player-panel="true"
        onKeyDown={handleKeyDown}
        className={`${width} max-w-[calc(100vw-24px)] overflow-y-auto overscroll-contain border border-player-edge bg-player-surface text-player-ink shadow-ml-panel ${fullHeight ? 'h-[calc(100%-24px)] rounded-ml-lg sm:h-full sm:rounded-none' : 'max-h-[min(72vh,620px)] rounded-ml-lg p-4 sm:me-[26px] sm:mb-[106px]'}`}
      >
        <header className="sticky top-0 z-10 flex min-h-11 items-center gap-3 bg-player-surface pb-3">
          <h2 className="text-[13px] font-bold">{title}</h2>
          <IconButton label={`Close ${title}`} onClick={onClose} className="ms-auto h-10 w-10">
            <X size={18} aria-hidden="true" />
          </IconButton>
        </header>
        {children}
      </section>
    </div>
  );
}

function TrackRow({ selected, tabStop = selected, label, detail, onClick }: {
  selected: boolean;
  tabStop?: boolean;
  label: string;
  detail?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      role="option"
      aria-selected={selected}
      tabIndex={tabStop ? 0 : -1}
      onClick={onClick}
      onKeyDown={event => {
        if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        event.stopPropagation();
        const listbox = event.currentTarget.closest('[role="listbox"]');
        const options = [...(listbox?.querySelectorAll<HTMLElement>('[role="option"]') ?? [])];
        const current = options.indexOf(event.currentTarget);
        const next = event.key === 'Home'
          ? 0
          : event.key === 'End'
            ? options.length - 1
            : (current + (event.key === 'ArrowDown' ? 1 : -1) + options.length) % options.length;
        options.forEach(option => { option.tabIndex = -1; });
        if (options[next]) {
          options[next].tabIndex = 0;
          options[next].focus();
        }
      }}
      className={`flex min-h-11 w-full items-center gap-3 rounded-ml-ctl px-3 py-2 text-start transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-white ${selected ? 'bg-player-elevated font-semibold text-player-ink' : 'text-player-ink-muted hover:bg-white/5 hover:text-player-ink'}`}
    >
      <span className={`grid h-4 w-4 shrink-0 place-items-center rounded-full ${selected ? 'bg-player-ink text-player-canvas' : 'bg-player-raised'}`}>
        {selected && <Check size={11} aria-hidden="true" />}
      </span>
      <span className="min-w-0">
        <span className="block truncate text-[13px]">{label}</span>
        {detail && <span className="block truncate text-[10px] uppercase tracking-wide text-white/35">{detail}</span>}
      </span>
    </button>
  );
}

export function PlayerChrome({
  state,
  controller,
  metadata,
  mediaType,
  currentStream,
  streams,
  subtitles,
  resumePosition = 0,
  onBack,
  onSwitchStream,
  onPreviousEpisode,
  onNextEpisode,
  upNextContent,
  skipIntro,
  externalUrl,
}: PlayerChromeProps) {
  const [visible, setVisible] = useState(true);
  const [panel, setPanel] = useState<Panel>(null);
  const [chromeFocused, setChromeFocused] = useState(false);
  const [seekPreview, setSeekPreview] = useState<(PlayerSeekPreview & { percent: number }) | null>(null);
  const seekPreviewGeneration = useRef(0);
  const seekPreviewTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const seekPreviewAbort = useRef<AbortController | null>(null);
  const seekPreviewCache = useRef(new Map<number, PlayerSeekPreview>());
  const [showResume, setShowResume] = useState(resumePosition >= 10);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const stateRef = useRef(state);

  useEffect(() => {
    stateRef.current = state;
  }, [state]);

  const clearHideTimer = useCallback(() => {
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = null;
  }, []);

  const armHideTimer = useCallback(() => {
    clearHideTimer();
    if (stateRef.current.phase === 'playing' && !stateRef.current.paused && panel === null && !chromeFocused) {
      hideTimer.current = setTimeout(() => setVisible(false), PLAYER_AUTO_HIDE_MS);
    }
  }, [chromeFocused, clearHideTimer, panel]);

  const reveal = useCallback(() => {
    setVisible(true);
    armHideTimer();
  }, [armHideTimer]);

  useEffect(() => {
    if (state.phase === 'playing' && !state.paused && panel === null) {
      const revealTimer = setTimeout(() => {
        setVisible(true);
        armHideTimer();
      }, 0);
      return () => {
        clearTimeout(revealTimer);
        clearHideTimer();
      };
    }
    clearHideTimer();
    return clearHideTimer;
  }, [armHideTimer, clearHideTimer, panel, state.paused, state.phase]);

  const togglePlayback = useCallback(() => {
    const latest = stateRef.current;
    setVisible(true);
    if (latest.paused || latest.phase === 'ready' || latest.phase === 'paused') void controller.play();
    else void controller.pause();
  }, [controller]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target;
      const isFormControl = target instanceof Element
        && target.matches('input, textarea, select, button, a, [role="option"], [contenteditable="true"]');
      if (event.metaKey || event.ctrlKey || event.altKey || isFormControl) return;
      if (event.key === 'Escape' && panel) {
        event.preventDefault();
        setPanel(null);
        return;
      }
      const latest = stateRef.current;
      switch (event.key) {
        case ' ':
          event.preventDefault();
          togglePlayback();
          break;
        case 'ArrowLeft':
          event.preventDefault();
          if (latest.capabilities.seek) void controller.seek(Math.max(0, latest.position - 5));
          break;
        case 'ArrowRight':
          event.preventDefault();
          if (latest.capabilities.seek) void controller.seek(Math.min(latest.duration || Number.POSITIVE_INFINITY, latest.position + 5));
          break;
        case 'ArrowUp':
          event.preventDefault();
          if (latest.capabilities.volume) void controller.setVolume(Math.min(1, latest.volume + 0.05));
          break;
        case 'ArrowDown':
          event.preventDefault();
          if (latest.capabilities.volume) void controller.setVolume(Math.max(0, latest.volume - 0.05));
          break;
        case 'm': case 'M':
          if (latest.capabilities.volume) void controller.setMuted(!latest.muted);
          break;
        case 'f': case 'F':
          if (latest.capabilities.fullscreen) void controller.setFullscreen(!latest.fullscreen);
          break;
        case 'c': case 'C': {
          if (!latest.capabilities.subtitleTracks) break;
          const first = latest.subtitleTracks[0];
          void controller.selectSubtitleTrack(latest.selectedSubtitleId === 'off' && first ? first.id : 'off');
          break;
        }
        default:
          return;
      }
      reveal();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [controller, panel, reveal, togglePlayback]);

  const sourceIndex = streams.findIndex(stream => stream.url === currentStream.url);
  const volumeIcon = state.muted || state.volume <= 0
    ? <VolumeX size={21} aria-hidden="true" />
    : state.volume < 0.5
      ? <Volume1 size={21} aria-hidden="true" />
      : <Volume2 size={21} aria-hidden="true" />;
  const subtitleRows = useMemo<PlayerTrack[]>(() => [
    ...state.subtitleTracks,
    ...subtitles
      .filter(subtitle => !state.subtitleTracks.some(track => String(track.id) === subtitle.id))
      .map(subtitle => ({
        id: subtitle.id,
        kind: 'subtitles' as const,
        label: subtitle.name || subtitle.lang || 'Subtitle',
        language: subtitle.lang,
        embedded: false,
        selected: state.selectedSubtitleId === subtitle.id,
      })),
  ], [state.selectedSubtitleId, state.subtitleTracks, subtitles]);

  const openAudio = () => {
    setPanel('audio');
    void controller.openAudioPanel();
  };

  const updateSeekPreview = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!state.capabilities.seekPreview || !controller.requestSeekPreview || state.duration <= 0) return;
    const bounds = event.currentTarget.getBoundingClientRect();
    if (bounds.width <= 0) return;
    const percent = Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width));
    const position = Math.round(percent * state.duration);
    const generation = seekPreviewGeneration.current + 1;
    seekPreviewGeneration.current = generation;
    if (seekPreviewTimer.current) clearTimeout(seekPreviewTimer.current);
    const cached = seekPreviewCache.current.get(position);
    if (cached) {
      setSeekPreview({ ...cached, percent });
      return;
    }
    seekPreviewTimer.current = setTimeout(() => {
      seekPreviewTimer.current = null;
      seekPreviewAbort.current?.abort();
      const abortController = new AbortController();
      seekPreviewAbort.current = abortController;
      void Promise.resolve(controller.requestSeekPreview?.(position, abortController.signal)).then(result => {
        if (abortController.signal.aborted || generation !== seekPreviewGeneration.current || !result) return;
        seekPreviewCache.current.set(position, result);
        if (seekPreviewCache.current.size > 60) seekPreviewCache.current.delete(seekPreviewCache.current.keys().next().value as number);
        setSeekPreview({ ...result, percent });
      });
    }, PLAYER_SEEK_PREVIEW_DEBOUNCE_MS);
  };

  useEffect(() => () => {
    if (seekPreviewTimer.current) clearTimeout(seekPreviewTimer.current);
    seekPreviewAbort.current?.abort();
  }, []);

  const isLoading = state.phase === 'idle' || state.phase === 'resolving' || state.phase === 'loading';
  const isError = state.phase === 'error' || state.phase === 'external' || state.phase === 'unsupported';
  useEffect(() => {
    if (!isLoading && (!isError || panel === 'sources')) return;
    const timer = setTimeout(() => setPanel(null), 0);
    return () => clearTimeout(timer);
  }, [isError, isLoading, panel]);
  const controlsVisible = !isLoading && !isError && (
    visible || chromeFocused || state.phase !== 'playing' || state.paused || panel !== null
  );

  return (
    <div
      data-testid="player-chrome"
      className="pointer-events-auto absolute inset-0 z-20 select-none overflow-hidden text-player-ink"
      onMouseMove={reveal}
      onFocusCapture={() => {
        setChromeFocused(true);
        setVisible(true);
        clearHideTimer();
      }}
      onBlurCapture={event => {
        if (event.currentTarget.contains(event.relatedTarget as Node | null)) return;
        setChromeFocused(false);
        armHideTimer();
      }}
    >
      {isLoading && (
        <div
          role="status"
          aria-live="polite"
          className="pointer-events-auto absolute inset-0 z-30 grid place-items-center bg-player-canvas"
          style={metadata.background ? {
            backgroundImage: `linear-gradient(rgba(9,10,10,.6), rgba(9,10,10,.92)), url(${metadata.background})`,
            backgroundPosition: 'center',
            backgroundSize: 'cover',
          } : undefined}
        >
          <div className="px-6 text-center">
            {metadata.logo
              ? <img src={metadata.logo} alt={metadata.title} className="mx-auto mb-5 max-h-[180px] max-w-[300px] object-contain" />
              : <p className="mb-5 text-2xl font-semibold text-white">{metadata.title}</p>}
            <p className="text-[10px] font-bold uppercase tracking-[0.26em] text-player-ink-muted">Setting the scene</p>
            <span className="mx-auto my-4 block h-[3px] w-[34px] animate-pulse rounded-full bg-white" />
            <p className="text-xs text-white/45">Finding the best playable source…</p>
          </div>
        </div>
      )}

      {isError && (
        <div role="alert" className="pointer-events-auto absolute inset-0 z-30 flex flex-col items-center justify-center gap-4 bg-black/95 px-6 text-center">
          <h2 className="text-xl font-bold">Playback failed</h2>
          <p className="max-w-md text-sm text-player-ink-muted">{state.error || 'No safe playback route is available.'}</p>
          <div className="flex flex-wrap justify-center gap-3">
            {state.phase === 'external' && externalUrl && (
              <a
                href={externalUrl}
                target="_blank"
                rel="noreferrer"
                className="inline-flex min-h-11 items-center rounded-full bg-white px-6 text-sm font-bold text-black active:scale-[0.96]"
              >Open externally</a>
            )}
            {state.phase === 'error' && (
              <button type="button" aria-label="Retry playback" onClick={() => void controller.retry()} className="min-h-11 rounded-full bg-white px-6 text-sm font-bold text-black active:scale-[0.96]">Retry</button>
            )}
            {streams.length > 1 && (
              <button type="button" onClick={() => setPanel('sources')} className="min-h-11 rounded-full bg-white/10 px-6 text-sm font-semibold">Choose source</button>
            )}
            <button type="button" onClick={onBack} className="min-h-11 rounded-full bg-white/10 px-6 text-sm font-semibold">Back</button>
          </div>
        </div>
      )}

      {showResume && !isLoading && !isError && (
        <div className="pointer-events-auto absolute start-1/2 top-24 z-30 flex -translate-x-1/2 items-center gap-3 rounded-full border border-white/10 bg-player-canvas/90 p-1.5 ps-4 shadow-ml-panel backdrop-blur-sm">
          <span className="text-xs text-player-ink-muted">Resumed at {fmt(resumePosition)}</span>
          <button type="button" aria-label="Start over" onClick={() => { setShowResume(false); void controller.seek(0); }} className="min-h-10 rounded-full bg-white px-4 text-xs font-bold text-black active:scale-[0.96]">Start over</button>
          <IconButton label="Dismiss resume prompt" onClick={() => setShowResume(false)} className="h-10 w-10"><X size={16} aria-hidden="true" /></IconButton>
        </div>
      )}

      {skipIntro && !isLoading && !isError && (
        <button type="button" onClick={() => void controller.seek(skipIntro.to)} className="pointer-events-auto absolute end-[34px] bottom-[155px] z-20 min-h-11 rounded-full bg-white px-5 text-xs font-bold text-black shadow-ml-panel active:scale-[0.96]">
          {skipIntro.label || 'Skip Intro'} <span aria-hidden="true">→</span>
        </button>
      )}

      <div
        data-testid="player-chrome-controls"
        data-visible={String(controlsVisible)}
        aria-hidden={!controlsVisible}
        className={`absolute inset-0 z-20 flex flex-col justify-between transition-opacity ease-in-out ${controlsVisible ? 'visible opacity-100' : 'invisible pointer-events-none opacity-0'}`}
        style={{ transitionDuration: `${PLAYER_CHROME_FADE_MS}ms` }}
      >
        <header className="pointer-events-auto flex min-h-[82px] items-center gap-3 bg-gradient-to-b from-black/90 to-transparent px-4 pb-6 sm:px-[30px]">
          <IconButton label="Back" onClick={onBack} className="rounded-full"><ArrowLeft size={20} aria-hidden="true" /></IconButton>
          <div className="min-w-0">
            <p className="truncate text-[13px] font-bold text-white">{metadata.title}</p>
            {metadata.secondaryTitle && <p className="mt-0.5 truncate text-[10px] text-player-ink-muted">{metadata.secondaryTitle}</p>}
          </div>
          <div className="ms-auto flex items-center gap-1.5">
            <IconButton label="Sources" onClick={() => setPanel('sources')}><ListVideo size={18} aria-hidden="true" /></IconButton>
            <IconButton
              label={state.capabilities.remotePlayback ? 'Remote playback' : 'Remote playback unavailable'}
              disabled={!state.capabilities.remotePlayback}
              onClick={() => void controller.requestRemotePlayback?.()}
            ><Airplay size={18} aria-hidden="true" /></IconButton>
            <span className="grid h-[34px] min-w-[34px] place-items-center rounded-ml-ctl bg-white/10 px-2 text-[10px] font-black text-white" aria-label="Playback route">{state.routeLabel}</span>
          </div>
        </header>

        <footer className="pointer-events-auto bg-gradient-to-t from-black/95 via-black/75 to-transparent px-4 pb-[calc(16px+env(safe-area-inset-bottom))] pt-24 sm:px-7 sm:pb-[calc(23px+env(safe-area-inset-bottom))]">
          <div className="relative grid grid-cols-[42px_minmax(0,1fr)_42px] items-center gap-2.5 text-[10px] font-mono tabular-nums sm:text-xs">
            <span>{fmt(state.position)}</span>
            <div
              data-testid="seek-preview-timeline"
              className="group relative flex h-11 items-center"
              onMouseMove={updateSeekPreview}
              onMouseLeave={() => {
                seekPreviewGeneration.current += 1;
                if (seekPreviewTimer.current) clearTimeout(seekPreviewTimer.current);
                seekPreviewTimer.current = null;
                seekPreviewAbort.current?.abort();
                seekPreviewAbort.current = null;
                setSeekPreview(null);
              }}
            >
              <input
                type="range"
                aria-label="Playback position"
                min={0}
                max={state.duration || 0}
                step={0.1}
                value={Math.min(state.position, state.duration || 0)}
                disabled={!state.capabilities.seek || state.duration <= 0}
                onChange={event => void controller.seek(Number(event.currentTarget.value))}
                className="h-11 w-full cursor-pointer accent-white disabled:cursor-not-allowed"
              />
              <div
                data-testid="seek-preview"
                className="pointer-events-none absolute bottom-full hidden h-[144px] w-[256px] -translate-x-1/2 place-items-center overflow-hidden rounded-[7px] border border-white/10 bg-player-surface text-xs text-player-ink-muted shadow-ml-panel group-hover:grid"
                style={{ left: `${seekPreview ? seekPreview.percent * 100 : 50}%` }}
              >
                {seekPreview
                  ? <img src={seekPreview.imageUrl} alt={`Preview at ${fmt(seekPreview.position)}`} className="h-full w-full object-cover" />
                  : state.capabilities.seekPreview ? 'Move to preview' : 'Preview unavailable'}
              </div>
            </div>
            <span className="text-end">{fmt(state.duration)}</span>
          </div>

          <div className="mt-2 grid grid-cols-[1fr_auto_1fr] items-center gap-2">
            <div className="flex min-w-0 items-center gap-1">
              <IconButton label={state.muted ? 'Unmute' : 'Mute'} disabled={!state.capabilities.volume} onClick={() => void controller.setMuted(!state.muted)}>{volumeIcon}</IconButton>
              <input
                type="range"
                aria-label="Volume"
                min={0}
                max={1}
                step={0.01}
                value={state.volume}
                disabled={!state.capabilities.volume}
                onChange={event => void controller.setVolume(Number(event.currentTarget.value))}
                className="hidden h-11 w-[70px] accent-white sm:block"
              />
            </div>

            <div className="flex items-center gap-1 sm:gap-1.5">
              {mediaType === 'series' && (
                <IconButton label={onPreviousEpisode ? 'Previous episode' : 'Previous episode unavailable'} disabled={!onPreviousEpisode} onClick={onPreviousEpisode}><SkipBack size={19} aria-hidden="true" /></IconButton>
              )}
              <IconButton label="Seek back 10 seconds" disabled={!state.capabilities.seek} onClick={() => void controller.seek(Math.max(0, state.position - 10))}><RotateCcw size={21} aria-hidden="true" /></IconButton>
              <IconButton label={state.paused ? 'Play' : 'Pause'} onClick={togglePlayback} className="h-12 w-12 rounded-full bg-white text-black hover:bg-white/90">
                {state.paused ? <Play size={23} fill="currentColor" aria-hidden="true" /> : <Pause size={23} fill="currentColor" aria-hidden="true" />}
              </IconButton>
              <IconButton label="Seek forward 10 seconds" disabled={!state.capabilities.seek} onClick={() => void controller.seek(Math.min(state.duration || Number.POSITIVE_INFINITY, state.position + 10))}><RotateCw size={21} aria-hidden="true" /></IconButton>
              {mediaType === 'series' && (
                <IconButton label={onNextEpisode ? 'Next episode' : 'Next episode unavailable'} disabled={!onNextEpisode} onClick={onNextEpisode}><SkipForward size={19} aria-hidden="true" /></IconButton>
              )}
            </div>

            <div className="flex min-w-0 items-center justify-end gap-1">
              <IconButton
                label={state.capabilities.subtitleTracks ? 'Subtitles' : 'Subtitles unavailable'}
                disabled={!state.capabilities.subtitleTracks}
                active={state.selectedSubtitleId !== 'off'}
                onClick={() => setPanel('subtitles')}
              ><Captions size={20} aria-hidden="true" /></IconButton>
              <IconButton
                label={state.capabilities.audioTracks ? 'Audio tracks' : 'Audio tracks unavailable'}
                disabled={!state.capabilities.audioTracks}
                onClick={openAudio}
              ><Headphones size={20} aria-hidden="true" /></IconButton>
              <button
                type="button"
                aria-label={state.capabilities.playbackRate ? 'Playback speed' : 'Playback speed unavailable'}
                disabled={!state.capabilities.playbackRate}
                onClick={() => setPanel(panel === 'speed' ? null : 'speed')}
                className="hidden min-h-11 rounded-full bg-white/10 px-3 text-xs font-bold text-white active:scale-[0.96] focus-visible:outline focus-visible:outline-2 focus-visible:outline-white disabled:opacity-30 sm:block"
              >{state.playbackRate === 1 ? '1×' : `${state.playbackRate}×`} <ChevronDown className="inline" size={12} aria-hidden="true" /></button>
              <IconButton
                label={state.capabilities.pictureInPicture ? 'Picture in picture' : 'Picture in picture unavailable'}
                disabled={!state.capabilities.pictureInPicture}
                active={state.pictureInPicture}
                onClick={() => void controller.setPictureInPicture(!state.pictureInPicture)}
                className="hidden sm:flex"
              ><PictureInPicture2 size={19} aria-hidden="true" /></IconButton>
              {mediaType === 'series' && (
                <IconButton label="Up Next" disabled={!upNextContent} onClick={() => setPanel('up-next')} className="hidden sm:flex"><SkipForward size={19} aria-hidden="true" /></IconButton>
              )}
              <IconButton label={state.fullscreen ? 'Exit fullscreen' : 'Fullscreen'} disabled={!state.capabilities.fullscreen} onClick={() => void controller.setFullscreen(!state.fullscreen)}>
                {state.fullscreen ? <Minimize size={20} aria-hidden="true" /> : <Maximize size={20} aria-hidden="true" />}
              </IconButton>
            </div>
          </div>
        </footer>
      </div>

      {!isLoading && panel === 'sources' && (
        <PanelFrame title="Sources" width="w-[440px]" onClose={() => setPanel(null)} fullHeight>
          <div className="space-y-2 px-3 pb-5" role="listbox" aria-label="Playback sources">
            {streams.map((stream, index) => (
              <TrackRow
                key={`${stream.url || stream.externalUrl || index}`}
                selected={index === sourceIndex}
                tabStop={index === sourceIndex || (sourceIndex < 0 && index === 0)}
                label={streamLabel(stream, index)}
                detail={stream.addonName}
                onClick={() => { setPanel(null); onSwitchStream(stream); }}
              />
            ))}
            {streams.length === 0 && <p className="p-4 text-sm text-player-ink-muted">No alternate sources available.</p>}
          </div>
        </PanelFrame>
      )}

      {!isLoading && !isError && panel === 'audio' && (
        <PanelFrame title="Audio" width="w-[360px]" onClose={() => setPanel(null)}>
          <div role="listbox" aria-label="Audio tracks" className="max-h-[260px] space-y-1 overflow-y-auto">
            {state.audioTracks.map((track, index) => (
              <TrackRow
                key={track.id}
                selected={track.id === state.selectedAudioId || track.selected}
                tabStop={(track.id === state.selectedAudioId || track.selected)
                  || (!state.audioTracks.some(item => item.id === state.selectedAudioId || item.selected) && index === 0)}
                label={track.label}
                detail={[track.codec, track.channels].filter(Boolean).join(' · ')}
                onClick={() => { setPanel(null); void controller.selectAudioTrack(track.id); }}
              />
            ))}
            {state.audioTracks.length === 0 && <p className="p-4 text-sm text-player-ink-muted">No audio tracks available.</p>}
          </div>
          <p className="mt-3 rounded-ml-ctl bg-player-elevated p-3 text-[10px] leading-relaxed text-player-ink-muted"><strong className="text-player-ink">Playback route · {state.routeLabel}</strong><br />{state.routeDetail}</p>
        </PanelFrame>
      )}

      {!isLoading && !isError && panel === 'subtitles' && (
        <PanelFrame title="Subtitles" width="w-[500px]" onClose={() => setPanel(null)}>
          <div className="grid gap-3 sm:grid-cols-[128px_minmax(0,1fr)]">
            <div className="rounded-ml-ctl bg-player-elevated p-2 text-xs text-player-ink-muted">
              <p className="rounded-lg bg-player-raised px-3 py-2 font-semibold text-player-ink">All · {subtitleRows.length}</p>
              <p className="px-3 py-2">Embedded · {subtitleRows.filter(track => track.embedded).length}</p>
              <p className="px-3 py-2">External · {subtitleRows.filter(track => !track.embedded).length}</p>
            </div>
            <div role="listbox" aria-label="Subtitle tracks" className="max-h-[300px] space-y-1 overflow-y-auto">
              <TrackRow
                selected={state.selectedSubtitleId === 'off'}
                tabStop={state.selectedSubtitleId === 'off'
                  || !subtitleRows.some(track => track.id === state.selectedSubtitleId || track.selected)}
                label="Off"
                onClick={() => { setPanel(null); void controller.selectSubtitleTrack('off'); }}
              />
              {subtitleRows.map(track => (
                <TrackRow
                  key={track.id}
                  selected={track.id === state.selectedSubtitleId || track.selected}
                  label={track.label}
                  detail={track.embedded ? 'Embedded' : 'External'}
                  onClick={() => { setPanel(null); void controller.selectSubtitleTrack(track.id); }}
                />
              ))}
            </div>
          </div>
        </PanelFrame>
      )}

      {!isLoading && !isError && panel === 'speed' && (
        <PanelFrame title="Playback speed" width="w-[220px]" onClose={() => setPanel(null)}>
          <div role="listbox" aria-label="Playback speeds">
            {[0.5, 0.75, 1, 1.25, 1.5, 2].map(rate => (
              <TrackRow key={rate} selected={rate === state.playbackRate} label={rate === 1 ? 'Normal' : `${rate}×`} onClick={() => { setPanel(null); void controller.setPlaybackRate(rate); }} />
            ))}
          </div>
        </PanelFrame>
      )}

      {!isLoading && !isError && panel === 'up-next' && (
        <PanelFrame title="Up Next" width="w-[440px]" onClose={() => setPanel(null)} fullHeight>
          <div className="px-4 pb-6">
            {typeof upNextContent === 'function'
              ? upNextContent(() => setPanel(null))
              : upNextContent}
          </div>
        </PanelFrame>
      )}
    </div>
  );
}
