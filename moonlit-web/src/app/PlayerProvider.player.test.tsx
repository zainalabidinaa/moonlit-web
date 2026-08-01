import { act, renderHook } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { PlayerProvider, usePlayer } from './PlayerProvider';

describe('PlayerProvider player contracts', () => {
  it('normalizes legacy launches and reconciles a direct URL to its full stream metadata', () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => <PlayerProvider>{children}</PlayerProvider>;
    const { result } = renderHook(() => usePlayer(), { wrapper });
    const matched = {
      url: 'https://cdn.example/movie.mkv',
      title: 'Movie H.264 AAC.mkv',
      addonName: 'Debrid Addon',
      behaviorHints: { proxyHeaders: { request: { Referer: 'https://addon.example' } } },
    };

    act(() => result.current.open({
      type: 'movie',
      id: 'tt123',
      streamUrl: matched.url,
      streams: [matched],
      metadata: { mediaId: 'tt123', mediaType: 'movie', title: 'Movie' },
      startPosition: -4,
    }));

    expect(result.current.launch).toMatchObject({ startPosition: 0, isLive: false });
    expect(result.current.activeStream).toEqual(matched);
  });

  it('unregisters stale stream-switch handlers when a player surface unmounts', () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => <PlayerProvider>{children}</PlayerProvider>;
    const { result } = renderHook(() => usePlayer(), { wrapper });
    const handler = vi.fn();

    let unregister = () => undefined;
    act(() => { unregister = result.current.registerStreamSwitchHandler(handler); });
    act(() => unregister());
    act(() => result.current.switchStream({ url: 'https://cdn.example/other.mp4' }));

    expect(handler).not.toHaveBeenCalled();
  });
});
