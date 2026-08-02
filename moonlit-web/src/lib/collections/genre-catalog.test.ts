import { describe, expect, it } from 'vitest';

import { browseRails, genres, sections } from './genre-catalog';
import type { DBCollection, DBFolder, DBFolderCatalog, OrganizedCollections } from './types';

// Mirrors Packages/MoonlitCore/Tests/MoonlitCoreTests/GenreCatalogTests.swift so
// moonlit-web resolves identical genre hubs from the same OrganizedCollections
// snapshot as native. Keep the two test suites in sync when either changes.

function catalog(id: string, folderId: string, catalogId: string): DBFolderCatalog {
  return { id, folderId, catalogId, mediaType: 'all' };
}

/**
 * A small layout mirroring the *parsed* profile (CollectionOrganizerParser output):
 * franchises and browse rails both arrive as DBFolderCatalog with synthesized catalog
 * ids ("tmdb.collection.<id>", "tmdb.discover.movie.new-movies.<hash>"), never as titled
 * DBFolderSource. The hub aggregation must work off those ids.
 */
function fixtureOrg(): OrganizedCollections {
  const collections: DBCollection[] = [
    { id: 'c-film', name: 'Film Collections', sortOrder: 0 },
    { id: 'c-genres', name: 'Genres', sortOrder: 1 },
    { id: 'c-hgenre', name: 'Horror genre', sortOrder: 2 },
    { id: 'c-hfran', name: 'Horror Franchises', sortOrder: 3 },
  ];
  const folders: DBFolder[] = [
    { id: 'f-actcoll', collectionId: 'c-film', name: 'Action Collections', sortOrder: 0 },
    { id: 'f-badboys', collectionId: 'c-film', name: 'Bad Boys', sortOrder: 1 },
    { id: 'f-diehard', collectionId: 'c-film', name: 'Die Hard', sortOrder: 2 },
    { id: 'f-alien', collectionId: 'c-film', name: 'Alien', sortOrder: 3 },
    { id: 'f-g-action', collectionId: 'c-genres', name: 'Action', sortOrder: 0 },
    { id: 'f-g-drama', collectionId: 'c-genres', name: 'Drama', sortOrder: 1 },
    { id: 'f-h-slasher', collectionId: 'c-hgenre', name: 'Slasher', sortOrder: 0 },
    { id: 'f-h-halloween', collectionId: 'c-hfran', name: 'Halloween', sortOrder: 0 },
  ];
  const folderCatalogs: DBFolderCatalog[] = [
    // Bundle lists franchises as tmdb.collection.<id> catalog ids
    catalog('s1', 'f-actcoll', 'tmdb.collection.14890'),
    catalog('s2', 'f-actcoll', 'tmdb.collection.1570'),
    // Standalone franchise folders carry the same catalog ids
    catalog('s3', 'f-badboys', 'tmdb.collection.14890'),
    catalog('s4', 'f-diehard', 'tmdb.collection.1570'),
    catalog('s5', 'f-alien', 'tmdb.collection.8091'),
    // Genres -> Action: New/Popular as movie+series discover catalogs
    catalog('s6', 'f-g-action', 'tmdb.discover.movie.new-movies.069d5312'),
    catalog('s7', 'f-g-action', 'tmdb.discover.series.new-series.76fc7ade'),
    catalog('s8', 'f-g-action', 'tmdb.discover.movie.popular-movies.29727d26'),
    catalog('s9', 'f-g-action', 'tmdb.discover.series.popular-series.20af3ad9'),
  ];
  return { collections, folders, folderCatalogs, folderSources: [] };
}

describe('GenreCatalog', () => {
  it('includes Crime even without a browse folder', () => {
    const names = genres(fixtureOrg()).map(g => g.name);
    expect(names).toContain('Action');
    expect(names).toContain('Crime');
  });

  it('does not put franchise bundles in sections (handled as content rows elsewhere)', () => {
    const result = sections('Action', fixtureOrg());
    expect(result.find(s => s.title === 'Collections')).toBeUndefined();
  });

  it('turns themed collections into labeled sections', () => {
    const result = sections('Horror', fixtureOrg());
    const titles = result.map(s => s.title);
    expect(titles).toContain('Sub-genres');
    expect(titles).toContain('Franchises');
    expect(result.find(s => s.title === 'Franchises')?.folders.map(f => f.name)).toEqual(['Halloween']);
  });

  it('merges movies and series into one browse rail per category', () => {
    const rails = browseRails('Action', fixtureOrg());
    expect(rails.map(r => r.title)).toEqual(['New', 'Popular']);
    expect(rails.find(r => r.title === 'New')?.catalogs).toHaveLength(2);
  });

  it('keeps non-New/Popular catalogs as individually titled curated rails', () => {
    const org: OrganizedCollections = {
      collections: [{ id: 'c-genres', name: 'Genres', sortOrder: 0 }],
      folders: [{ id: 'f-war', collectionId: 'c-genres', name: 'War', sortOrder: 0 }],
      folderCatalogs: [
        catalog('a', 'f-war', 'tmdb.discover.movie.movies.mo7bd2ar'),
        catalog('b', 'f-war', 'trakt.list.4973644'),
      ],
      folderSources: [],
    };
    const rails = browseRails('War', org);
    expect(rails.map(r => r.title)).toEqual(['Curated Collection', '100 Best Action Movies']);
    expect(rails.every(r => r.catalogs.length === 1)).toBe(true);
  });

  it('keeps curated catalogs as their own named rails alongside New', () => {
    const org: OrganizedCollections = {
      collections: [{ id: 'c-genres', name: 'Genres', sortOrder: 0 }],
      folders: [{ id: 'f-action', collectionId: 'c-genres', name: 'Action', sortOrder: 0 }],
      folderCatalogs: [
        catalog('new', 'f-action', 'tmdb.discover.movie.new-movies.069d5312'),
        catalog('top-action', 'f-action', 'mdblist.2407'),
        catalog('action-comedy', 'f-action', 'trakt.list.825738'),
      ],
      folderSources: [],
    };
    expect(browseRails('Action', org).map(r => r.title)).toEqual(['New', 'Top Action Movies', 'Action Comedy']);
  });

  it('does not leak Martial Arts catalogs into Action rails', () => {
    const org: OrganizedCollections = {
      collections: [{ id: 'c-genres', name: 'Genres', sortOrder: 0 }],
      folders: [
        { id: 'f-action', collectionId: 'c-genres', name: 'Action', sortOrder: 0 },
        { id: 'f-martial', collectionId: 'c-genres', name: 'Martial Arts', sortOrder: 1 },
      ],
      folderCatalogs: [
        catalog('action', 'f-action', 'mdblist.2407'),
        catalog('bruce', 'f-martial', 'trakt.list.4467615'),
      ],
      folderSources: [],
    };
    expect(browseRails('Action', org).map(r => r.title)).toEqual(['Top Action Movies']);
  });

  it('includes matching Categories-folder rails alongside the Genres-folder rails', () => {
    const org: OrganizedCollections = {
      collections: [
        { id: 'c-genres', name: 'Genres', sortOrder: 0 },
        { id: 'c-categories', name: 'Categories', sortOrder: 1 },
      ],
      folders: [
        { id: 'f-action', collectionId: 'c-genres', name: 'Action', sortOrder: 0 },
        { id: 'f-category-action', collectionId: 'c-categories', name: 'Action', sortOrder: 0 },
      ],
      folderCatalogs: [
        catalog('standard', 'f-action', 'tmdb.discover.movie.new-movies.069d5312'),
        catalog('editorial', 'f-category-action', 'mdblist.128037'),
      ],
      folderSources: [],
    };
    expect(browseRails('Action', org).map(r => r.title)).toEqual(['New', 'New Action Releases']);
  });
});
