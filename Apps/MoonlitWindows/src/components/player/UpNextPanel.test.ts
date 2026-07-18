import { describe, it, expect } from 'vitest';
import { parseEpisodeId, findAdjacent } from './UpNextPanel';

describe('parseEpisodeId', () => {
  it('parses series ids', () => {
    expect(parseEpisodeId('tt123:2:5')).toEqual({ imdb: 'tt123', season: 2, episode: 5 });
  });
  it('rejects movie ids', () => {
    expect(parseEpisodeId('tt123')).toBeNull();
  });
});

describe('findAdjacent', () => {
  const eps = [
    { id: 'a', season: 1, episode: 9 },
    { id: 'b', season: 1, episode: 10 },
    { id: 'c', season: 2, episode: 1 },
  ];
  it('crosses season boundaries forward', () => {
    expect(findAdjacent(eps, 1, 10, 1)?.id).toBe('c');
  });
  it('goes backward', () => {
    expect(findAdjacent(eps, 1, 10, -1)?.id).toBe('a');
  });
  it('returns null at the end', () => {
    expect(findAdjacent(eps, 2, 1, 1)).toBeNull();
  });
});
