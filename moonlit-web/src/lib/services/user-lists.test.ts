import { beforeEach, describe, expect, it, vi } from 'vitest';

const { from } = vi.hoisted(() => ({ from: vi.fn() }));

vi.mock('@/lib/supabase', () => ({
  supabase: { from },
  TMDB_API_KEY: 'test-key',
}));

import * as api from './api';

describe('user_lists watchlist API', () => {
  beforeEach(() => { from.mockReset(); });

  it('loads the profile watchlist from user_lists with its user_list_items', async () => {
    expect(typeof api.getUserWatchlist).toBe('function');

    const builder = {
      select: vi.fn(() => builder),
      eq: vi.fn(() => builder),
      maybeSingle: vi.fn(async () => ({
        data: {
          id: 'list-1',
          profile_id: 'profile-1',
          name: 'Watchlist',
          system_kind: 'watchlist',
          created_at: '2026-07-31T10:00:00Z',
          user_list_items: [
            {
              id: 'item-1',
              list_id: 'list-1',
              media_id: 'tt1',
              media_type: 'movie',
              name: 'Saved Movie',
              poster: 'poster.jpg',
              added_at: '2026-07-31T11:00:00Z',
            },
          ],
        },
        error: null,
      })),
    };
    from.mockReturnValue(builder);

    const watchlist = await api.getUserWatchlist('profile-1');

    expect(from).toHaveBeenCalledWith('user_lists');
    expect(builder.eq).toHaveBeenCalledWith('profile_id', 'profile-1');
    expect(builder.eq).toHaveBeenCalledWith('system_kind', 'watchlist');
    expect(watchlist.items).toEqual([
      expect.objectContaining({ media_id: 'tt1', name: 'Saved Movie' }),
    ]);
  });

  it('deletes a saved title through user_list_items and surfaces backend errors', async () => {
    expect(typeof api.removeUserWatchlistItem).toBe('function');

    const failure = new Error('delete failed');
    const builder = {
      delete: vi.fn(() => builder),
      eq: vi.fn(async () => ({ error: failure })),
    };
    from.mockReturnValue(builder);

    await expect(api.removeUserWatchlistItem('item-1')).rejects.toThrow('delete failed');
    expect(from).toHaveBeenCalledWith('user_list_items');
    expect(builder.eq).toHaveBeenCalledWith('id', 'item-1');
  });
});
