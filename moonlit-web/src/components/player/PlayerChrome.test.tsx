import { act, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import type { PlayerAdapterCapabilities, PlayerTrack } from '@/lib/player/contracts';
import { PlayerChrome, type PlayerChromeController, type PlayerChromeState } from './PlayerChrome';

const capabilities: PlayerAdapterCapabilities = {
  seek: true,
  volume: true,
  playbackRate: true,
  fullscreen: true,
  pictureInPicture: true,
  remotePlayback: false,
  audioTracks: true,
  subtitleTracks: true,
  seekPreview: true,
  screenshot: false,
  anime4k: false,
};

const audioTracks: PlayerTrack[] = [
  { id: 'audio-en', kind: 'audio', label: 'English', language: 'en', codec: 'E-AC-3', channels: '5.1', selected: true },
  { id: 'audio-es', kind: 'audio', label: 'Spanish', language: 'es', codec: 'AAC', channels: 'Stereo', selected: false },
];

const subtitleTracks: PlayerTrack[] = [
  { id: 'sub-en', kind: 'subtitles', label: 'English · Embedded', language: 'en', embedded: true, selected: false },
];

const playingState: PlayerChromeState = {
  phase: 'playing',
  position: 1122,
  duration: 3128,
  buffered: 1600,
  paused: false,
  muted: false,
  volume: 0.72,
  playbackRate: 1,
  fullscreen: false,
  pictureInPicture: false,
  selectedAudioId: 'audio-en',
  selectedSubtitleId: 'off',
  audioTracks,
  subtitleTracks,
  capabilities,
  error: null,
  routeLabel: 'Direct',
  routeDetail: 'HLS · H.264 · E-AC-3 supported',
};

function controller(): PlayerChromeController {
  return {
    play: vi.fn(),
    pause: vi.fn(),
    seek: vi.fn(),
    setVolume: vi.fn(),
    setMuted: vi.fn(),
    setPlaybackRate: vi.fn(),
    setFullscreen: vi.fn(),
    setPictureInPicture: vi.fn(),
    selectAudioTrack: vi.fn(),
    selectSubtitleTrack: vi.fn(),
    openAudioPanel: vi.fn(),
    retry: vi.fn(),
  };
}

function renderChrome(overrides: Partial<React.ComponentProps<typeof PlayerChrome>> = {}) {
  const controls = controller();
  const view = render(
    <PlayerChrome
      state={playingState}
      controller={controls}
      metadata={{
        mediaId: 'tt111:2:4',
        mediaType: 'series',
        title: 'House of the Dragon',
        secondaryTitle: 'S2 · E4 — The Red Dragon and the Gold',
      }}
      mediaId="tt111:2:4"
      mediaType="series"
      currentStream={{ url: 'https://cdn.example/master.m3u8', title: '4K H.264 E-AC-3' }}
      streams={[
        { url: 'https://cdn.example/master.m3u8', title: '4K H.264 E-AC-3' },
        { url: 'https://cdn.example/backup.mp4', title: '1080p H.264 AAC' },
      ]}
      subtitles={[{ id: 'addon-sv', lang: 'sv', name: 'Svenska · Addon', url: '/sv.vtt' }]}
      resumePosition={42}
      onBack={vi.fn()}
      onSwitchStream={vi.fn()}
      upNextContent={<p>Next episode</p>}
      {...overrides}
    />,
  );
  return { ...view, controls };
}

afterEach(() => {
  vi.useRealTimers();
});

describe('PlayerChrome', () => {
  it('auto-hides after 2.4 seconds while playing and fades over 0.18 seconds', () => {
    vi.useFakeTimers();
    const { rerender } = renderChrome();
    const chrome = screen.getByTestId('player-chrome-controls');

    expect(chrome).toHaveAttribute('data-visible', 'true');
    expect(chrome).toHaveStyle({ transitionDuration: '180ms' });
    act(() => vi.advanceTimersByTime(2399));
    expect(chrome).toHaveAttribute('data-visible', 'true');
    act(() => vi.advanceTimersByTime(1));
    expect(chrome).toHaveAttribute('data-visible', 'false');
    expect(chrome).toHaveClass('invisible', 'pointer-events-none');
    expect(screen.getByTestId('player-chrome')).toHaveClass('pointer-events-auto');
    fireEvent.mouseMove(screen.getByTestId('player-chrome'));
    expect(chrome).toHaveAttribute('data-visible', 'true');

    rerender(
      <PlayerChrome
        state={{ ...playingState, phase: 'paused', paused: true }}
        controller={controller()}
        metadata={{ mediaId: 'tt111', mediaType: 'series', title: 'Paused title' }}
        mediaId="tt111"
        mediaType="series"
        currentStream={{ url: 'https://cdn.example/movie.mp4' }}
        streams={[]}
        subtitles={[]}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
      />,
    );
    act(() => vi.advanceTimersByTime(5000));
    expect(screen.getByTestId('player-chrome-controls')).toHaveAttribute('data-visible', 'true');
  });

  it('renders the Mac transport and exact seek-preview geometry', () => {
    renderChrome();

    expect(screen.getByText('House of the Dragon')).toBeInTheDocument();
    expect(screen.getByText('S2 · E4 — The Red Dragon and the Gold')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Seek back 10 seconds' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Seek forward 10 seconds' })).toBeInTheDocument();
    expect(screen.getByTestId('seek-preview')).toHaveClass('w-[256px]', 'h-[144px]');
    expect(screen.getByRole('slider', { name: 'Playback position' })).toHaveAttribute('max', '3128');
  });

  it('opens audio, subtitles, and Up Next in the approved panel widths', async () => {
    const { controls } = renderChrome({
      upNextContent: close => <button type="button" onClick={close}>Play next episode</button>,
    });

    fireEvent.click(screen.getByRole('button', { name: 'Audio tracks' }));
    expect(controls.openAudioPanel).toHaveBeenCalledTimes(1);
    expect(await screen.findByRole('dialog', { name: 'Audio' })).toHaveClass('w-[360px]');
    fireEvent.keyDown(window, { key: 'Escape' });

    fireEvent.click(screen.getByRole('button', { name: 'Subtitles' }));
    expect(await screen.findByRole('dialog', { name: 'Subtitles' })).toHaveClass('w-[500px]');
    fireEvent.keyDown(window, { key: 'Escape' });

    fireEvent.click(screen.getByRole('button', { name: 'Up Next' }));
    expect(await screen.findByRole('dialog', { name: 'Up Next' })).toHaveClass('w-[440px]');
    fireEvent.click(screen.getByRole('button', { name: 'Play next episode' }));
    expect(screen.queryByRole('dialog', { name: 'Up Next' })).not.toBeInTheDocument();
  });

  it('normalizes player hotkeys while ignoring modified shortcuts and form input', () => {
    const { controls } = renderChrome();

    fireEvent.keyDown(window, { key: ' ' });
    fireEvent.keyDown(window, { key: 'ArrowLeft' });
    fireEvent.keyDown(window, { key: 'ArrowRight' });
    fireEvent.keyDown(window, { key: 'ArrowUp' });
    fireEvent.keyDown(window, { key: 'ArrowDown' });
    fireEvent.keyDown(window, { key: 'm' });
    fireEvent.keyDown(window, { key: 'f' });
    fireEvent.keyDown(window, { key: 'c' });

    expect(controls.pause).toHaveBeenCalledTimes(1);
    expect(controls.seek).toHaveBeenNthCalledWith(1, 1117);
    expect(controls.seek).toHaveBeenNthCalledWith(2, 1127);
    expect(controls.setVolume).toHaveBeenNthCalledWith(1, 0.77);
    expect(controls.setVolume).toHaveBeenNthCalledWith(2, 0.6699999999999999);
    expect(controls.setMuted).toHaveBeenCalledWith(true);
    expect(controls.setFullscreen).toHaveBeenCalledWith(true);
    expect(controls.selectSubtitleTrack).toHaveBeenCalledWith('sub-en');

    fireEvent.keyDown(window, { key: 'f', metaKey: true });
    expect(controls.setFullscreen).toHaveBeenCalledTimes(1);
    const slider = screen.getByRole('slider', { name: 'Volume' });
    slider.focus();
    fireEvent.keyDown(slider, { key: ' ' });
    expect(controls.pause).toHaveBeenCalledTimes(1);
  });

  it('honestly disables controls unavailable from the active adapter', () => {
    renderChrome({
      state: {
        ...playingState,
        capabilities: {
          ...capabilities,
          playbackRate: false,
          pictureInPicture: false,
          audioTracks: false,
          subtitleTracks: false,
        },
        audioTracks: [],
        subtitleTracks: [],
      },
    });

    expect(screen.getByRole('button', { name: 'Audio tracks unavailable' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Subtitles unavailable' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Playback speed unavailable' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Picture in picture unavailable' })).toBeDisabled();
  });

  it('keeps loading, resume, and terminal error states inside the shared surface', () => {
    const { rerender, controls } = renderChrome({ state: { ...playingState, phase: 'loading' } });
    expect(screen.getByRole('status')).toHaveTextContent('Finding the best playable source');

    rerender(
      <PlayerChrome
        state={{ ...playingState, phase: 'ready', paused: true }}
        controller={controls}
        metadata={{ mediaId: 'tt111', mediaType: 'movie', title: 'Movie' }}
        mediaId="tt111"
        mediaType="movie"
        currentStream={{ url: 'https://cdn.example/movie.mp4' }}
        streams={[]}
        subtitles={[]}
        resumePosition={42}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Start over' }));
    expect(controls.seek).toHaveBeenCalledWith(0);

    rerender(
      <PlayerChrome
        state={{ ...playingState, phase: 'error', error: 'Every route failed.' }}
        controller={controls}
        metadata={{ mediaId: 'tt111', mediaType: 'movie', title: 'Movie' }}
        mediaId="tt111"
        mediaType="movie"
        currentStream={{ url: 'https://cdn.example/movie.mp4' }}
        streams={[]}
        subtitles={[]}
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
      />,
    );
    expect(screen.getByRole('alert')).toHaveTextContent('Every route failed.');
    fireEvent.click(screen.getByRole('button', { name: 'Retry playback' }));
    expect(controls.retry).toHaveBeenCalledTimes(1);

    rerender(
      <PlayerChrome
        state={{ ...playingState, phase: 'external', error: 'Use a desktop player.' }}
        controller={controls}
        metadata={{ mediaId: 'tt111', mediaType: 'movie', title: 'Movie' }}
        mediaId="tt111"
        mediaType="movie"
        currentStream={{ url: 'https://cdn.example/movie.mkv' }}
        streams={[]}
        subtitles={[]}
        externalUrl="https://cdn.example/movie.mkv"
        onBack={vi.fn()}
        onSwitchStream={vi.fn()}
      />,
    );
    expect(screen.getByRole('link', { name: 'Open externally' })).toHaveAttribute('href', 'https://cdn.example/movie.mkv');
  });

  it('switches sources from the shared source panel', () => {
    const onSwitchStream = vi.fn();
    renderChrome({ onSwitchStream });

    fireEvent.click(screen.getByRole('button', { name: 'Sources' }));
    fireEvent.click(screen.getByRole('option', { name: /1080p H\.264 AAC/ }));

    expect(onSwitchStream).toHaveBeenCalledWith(expect.objectContaining({ url: 'https://cdn.example/backup.mp4' }));
  });
});
