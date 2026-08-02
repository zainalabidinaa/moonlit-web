import type { CatalogRow, DBCollection, DBFolder, DBFolderCatalog, DBFolderSource, MetaPreview, OrganizedCollections } from './types';

/**
 * Aggregates the many genre-related collections (a `Genres` browse collection,
 * `<Genre> Collections` franchise bundles inside `Film Collections`, and themed
 * collections like `Horror Franchises` / `International Horror`) into a single,
 * sectioned "genre hub" — driven entirely by collection naming so authoring a new
 * `Horror Decades` collection automatically appears under Horror.
 *
 * Ported 1:1 from Packages/MoonlitCore/Sources/MoonlitCore/Services/GenreCatalog.swift
 * so moonlit-web and the native apps resolve identical genre hubs from the same
 * OrganizedCollections snapshot. Keep the two in sync when either changes.
 */

export interface Genre {
  id: string;   // normalized key, e.g. "sci-fi"
  name: string; // display name, e.g. "Sci-Fi"
}

/** A row of folder tiles inside a genre hub (e.g. "Franchises" -> [Halloween, Scream]). */
export interface GenreSection {
  id: string;
  title: string;
  folders: DBFolder[];
}

/** A merged browse rail (e.g. "New" = New Movies + New Series for this genre). */
export interface BrowseRail {
  id: string;
  title: string;
  catalogs: DBFolderCatalog[];
  sources: DBFolderSource[];
}

/** A browse rail with its items resolved, ready to render. */
export interface LoadedBrowseRail {
  id: string;
  title: string;
  items: MetaPreview[];
  subtitle?: string;
}

/** Everything a genre hub renders: sectioned folder tiles + loaded browse rails. */
export interface GenreHubContent {
  sections: GenreSection[];
  browse: LoadedBrowseRail[];
  collectionRails: LoadedBrowseRail[];
}

/**
 * Genres we always want to offer, even when the profile has no browse folder for
 * them (Crime, for instance, has franchise collections but no `Genres` row).
 */
export const CANONICAL_GENRES = [
  'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary',
  'Drama', 'Family', 'Fantasy', 'Horror', 'Mystery', 'Romance',
  'Sci-Fi', 'Thriller', 'War', 'Western',
];

/** Lowercased, format-mark-stripped, whitespace-collapsed key for matching. */
export function normalize(s: string): string {
  const cleaned = s
    .replace(/[\u200E\u200F\uFEFF]/g, '')
    .toLowerCase();
  return cleaned
    .split(/[ \t\n]+/)
    .filter(Boolean)
    .join(' ')
    .trim();
}

function foldersOf(collection: DBCollection, org: OrganizedCollections): DBFolder[] {
  return org.folders
    .filter(f => f.collectionId === collection.id)
    .sort((a, b) => a.sortOrder - b.sortOrder);
}

// MARK: - Genre list

export function genres(org: OrganizedCollections): Genre[] {
  let names = org.collections
    .filter(c => normalize(c.name) === 'genres')
    .flatMap(c => foldersOf(c, org))
    .map(f => f.name);
  if (names.length === 0) names = CANONICAL_GENRES;
  if (!names.some(n => normalize(n) === 'crime')) names.push('Crime');

  const seen = new Set<string>();
  const result: Genre[] = [];
  for (const name of names) {
    const key = normalize(name);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push({ id: key, name });
  }
  return result;
}

// MARK: - Sections

/**
 * Checks whether `key` appears as a standalone word in `name`.
 * e.g. key="horror" matches "horror collections" but not "action horror collections"
 * or "reaction films".
 */
function genreIsStandaloneWord(name: string, key: string): boolean {
  return name.split(' ').includes(key);
}

function sectionOrder(title: string): number {
  const order = ['Sub-genres', 'Collections', 'Franchises', 'International', 'Mood & Vibe', 'Decades'];
  const index = order.indexOf(title);
  return index === -1 ? 50 : index;
}

function titleCased(s: string): string {
  return s.split(' ').map(w => w.slice(0, 1).toUpperCase() + w.slice(1)).join(' ');
}

function friendlyLabel(collectionName: string, genre: string): string {
  const rest = normalize(collectionName)
    .replace(normalize(genre), ' ')
    .replace(/&/g, ' and ')
    .split(' ')
    .filter(Boolean)
    .join(' ')
    .trim();
  switch (rest) {
    case 'genre': case 'genres': return 'Sub-genres';
    case 'franchise': case 'franchises': return 'Franchises';
    case 'decade': case 'decades': return 'Decades';
    case 'mood and vibe': case 'mood vibe': case 'vibe': return 'Mood & Vibe';
    case '': return 'Collections';
    default: return titleCased(rest);
  }
}

export function sections(genre: string, org: OrganizedCollections): GenreSection[] {
  const key = normalize(genre);
  const result: GenreSection[] = [];

  // Themed top-level collections whose name contains the genre as a standalone
  // word — not a substring — so "Action" doesn't bleed into collections named
  // "Reaction Films" or mixed-genre collections.
  const sortedCollections = [...org.collections].sort((a, b) => a.sortOrder - b.sortOrder);
  for (const collection of sortedCollections) {
    const cname = normalize(collection.name);
    if (cname === 'genres' || cname === 'film collections') continue;
    if (!genreIsStandaloneWord(cname, key)) continue;
    const folders = foldersOf(collection, org);
    if (folders.length === 0) continue;
    result.push({
      id: `section-${key}-${cname}`,
      title: friendlyLabel(collection.name, genre),
      folders,
    });
  }

  return result.sort((a, b) => sectionOrder(a.title) - sectionOrder(b.title));
}

// MARK: - Browse rails

function browseOrder(title: string): number {
  const order = ['New', 'Popular', 'Top of all time', 'Top of the year'];
  const index = order.indexOf(title);
  return index === -1 ? 50 : index;
}

/**
 * Browse-rail category from a synthesized discover catalog id, e.g.
 * "tmdb.discover.movie.new-movies.069d5312" -> "New". Returns null for genre/decade/
 * anime discover catalogs so only New / Popular / Top rails surface.
 */
function browseCategory(catalogId: string): string | null {
  const parts = catalogId.split('.');
  if (parts.length < 4 || parts[0] !== 'tmdb' || parts[1] !== 'discover') return null;
  if (parts[2] !== 'movie' && parts[2] !== 'series') return null;
  let slug = parts[3];
  for (const suffix of ['-movies', '-series', '-shows']) {
    if (slug.endsWith(suffix)) { slug = slug.slice(0, -suffix.length); break; }
  }
  switch (slug) {
    case 'new': return 'New';
    case 'popular': return 'Popular';
    case 'top-all-time': return 'Top of all time';
    case 'top-of-the-year': return 'Top of the year';
    default: return null;
  }
}

/**
 * Display names for imported AIOMetadata catalogs whose layout source omits a
 * title. New organizer sources keep their own title upstream; this fallback
 * prevents the existing library of list IDs from becoming anonymous rails.
 */
const CURATED_TITLES: Record<string, string> = {
  'mdblist.128037': 'New Action Releases',
  'mdblist.2407': 'Top Action Movies',
  'trakt.list.11255166': 'Action Movies (2000–2020)',
  'trakt.list.825738': 'Action Comedy',
  'trakt.list.4973644': '100 Best Action Movies',
  'trakt.list.22847039': 'IMDb’s Top Animation Movies',
  'trakt.list.24484523': 'IMDb’s Popular Family Animation',
  'mdblist.121922': 'Popular Animation Movies',
  'mdblist.121921': 'Popular Animation Series',
  'trakt.list.1522155': 'Pixar Animation Studios',
  'trakt.list.1580797': 'DreamWorks Animation',
  'trakt.list.23334961': 'Sony Pictures Animation',
  'trakt.list.3899489': 'Hidden Animation Gems',
  'trakt.list.837518': 'Warner Bros. Animation',
  'trakt.list.5707382': '100 Anime to Watch Before You Die',
  'trakt.list.23438792': '100 Best Anime Movies of All Time',
  'trakt.list.5040627': 'Time Out 100 Best Comedy Movies',
  'trakt.list.9659389': 'Best of British Comedy TV Shows',
  'mdblist.2195': 'Top Comedy Movies',
  'mdblist.3122': 'Comedy Series',
  'mdblist.128040': 'New Releases in Comedy',
  'trakt.list.22097600': 'Top 100 TV Comedy Shows',
  'trakt.list.10235726': 'Rotten Tomatoes’ 100 Best Documentaries',
  'trakt.list.801580': 'Documentary Blog’s Top 50 of the Decade',
  'trakt.list.33762909': 'Professor Brian Cox',
  'trakt.list.1799417': 'True Crime Documentaries',
  'trakt.list.6652940': 'History Documentaries',
  'trakt.list.25298201': 'BBC Wildlife & Nature Documentaries',
  'trakt.list.2565470': 'Hacking & Programming Documentaries',
  'trakt.list.23020633': 'Space Documentaries',
  'trakt.list.19556363': 'War Documentaries',
  'trakt.list.6652017': 'Attenborough Documentaries',
  'trakt.list.26957348': 'IMDb: Popular Nature Documentaries',
  'trakt.list.23440324': 'BBC Earth — Life on Our Planet',
  'mdblist.84487': 'Top Nature Shows',
  'trakt.list.3813071': 'Astronomy and Cosmology',
  'trakt.list.21840363': 'Martial Arts: Top 250',
  'trakt.list.6674425': 'Hollywood Martial Arts',
  'trakt.list.4467615': 'Bruce Lee',
  'trakt.list.11632332': 'Jackie Chan',
  'trakt.list.4974101': '100 Best Musicals',
  'trakt.list.2619099': 'Popular Musicals',
  'trakt.list.22803128': 'BFI 100 Best Thrillers',
  'trakt.list.22096238': 'Top 200 Psychological Thrillers',
  'trakt.list.19594387': 'Murder Mystery Movies',
  'trakt.list.5221223': 'Mystery: 1,000 Titles',
  'trakt.list.797798': '100 Greatest Sci‑Fi Movies',
  'trakt.list.4433767': 'Best War Movies Ever Made',
  'trakt.list.21899611': 'Spaghetti Westerns',
  'trakt.list.22847467': 'IMDb’s Top Western Movies',
  'trakt.list.20701912': 'Rotten Tomatoes’ Top 100 Romance Movies',
  'trakt.list.21033097': 'Mega Erotic',
  'trakt.list.4203408': 'Rotten Tomatoes: Best Horror Movies',
  'trakt.list.21193458': 'Popular Horror',
  'mdblist.2410': 'Top Horror Movies',
  'mdblist.128045': 'New Horror Releases',
  'mdblist.3124': 'Horror Series',
  'trakt.list.2067889': 'Best Slasher Flicks',
  'trakt.list.22535146': 'Hidden Horror Gems',
  'trakt.list.10563394': 'Classic Horror',
  'trakt.list.23423498': 'Comedy Horror',
  'trakt.list.1076151': 'British Crime & Drama',
  'trakt.list.21715794': 'Courtroom Dramas',
  'trakt.list.22957181': 'Period Drama Movies',
  'trakt.list.20580022': 'Rotten Tomatoes: Top Kids & Family Movies',
};

function curatedTitle(catalogId: string): string {
  return CURATED_TITLES[catalogId] ?? 'Curated Collection';
}

export function browseRails(genre: string, org: OrganizedCollections): BrowseRail[] {
  const key = normalize(genre);
  // Browse catalogs live in the "Genres" collection(s); the parser turns each
  // "New Movies"/"Popular Series"/… source into a discover catalog whose id encodes
  // the category (e.g. "tmdb.discover.movie.new-movies.<hash>").
  const genreCollectionIds = new Set(
    org.collections.filter(c => normalize(c.name) === 'genres').map(c => c.id),
  );
  const categoryCollectionIds = new Set(
    org.collections.filter(c => normalize(c.name) === 'categories').map(c => c.id),
  );
  const folderIds = new Set(
    org.folders
      .filter(f => (genreCollectionIds.has(f.collectionId) || categoryCollectionIds.has(f.collectionId))
        && normalize(f.name) === key)
      .map(f => f.id),
  );
  if (folderIds.size === 0) return [];

  const catalogs = org.folderCatalogs.filter(c => folderIds.has(c.folderId));

  // Merge the movie + series catalog of each category into one rail, in canonical order.
  const order: string[] = [];
  const buckets = new Map<string, DBFolderCatalog[]>();
  const leftover: DBFolderCatalog[] = [];
  for (const catalog of catalogs) {
    const category = browseCategory(catalog.catalogId);
    if (!category) { leftover.push(catalog); continue; }
    if (!buckets.has(category)) order.push(category);
    buckets.set(category, [...(buckets.get(category) ?? []), catalog]);
  }

  const rails: BrowseRail[] = [...order]
    .sort((a, b) => browseOrder(a) - browseOrder(b))
    .map(category => ({
      id: `browse-${key}-${normalize(category)}`,
      title: category,
      catalogs: buckets.get(category) ?? [],
      sources: [],
    }));

  // A curated source is editorial content in its own right. Combining every
  // remaining source into one anonymous "Browse" row loses that editorial
  // intent (for example Attenborough, BFI 100 Best Thrillers, or Jackie Chan).
  // Keep each source as an individually titled rail, in organizer order.
  for (const catalog of leftover) {
    rails.push({
      id: `browse-${key}-${catalog.id ?? catalog.catalogId}`,
      title: curatedTitle(catalog.catalogId),
      catalogs: [catalog],
      sources: [],
    });
  }
  return rails;
}

/** Folder tiles for a genre section, as a row `MediaCard` can render. */
export function sectionAsRow(section: GenreSection): CatalogRow {
  const present = (s: string | undefined | null) => (s ? s : undefined);
  const tiles: MetaPreview[] = section.folders.map(folder => ({
    id: `folder_${folder.id}`,
    type: 'folder',
    name: folder.name,
    poster: present(folder.coverImage) ?? present(folder.heroBackdrop) ?? present(folder.titleLogo),
    banner: present(folder.coverImage) ?? present(folder.heroBackdrop),
    logo: folder.titleLogo,
    tileShape: folder.tileShape || 'landscape',
  }));
  return {
    id: `section_${section.id}`,
    title: section.title,
    items: tiles,
    page: 0,
    hasMore: false,
    tileShape: section.folders[0]?.tileShape || 'landscape',
  };
}

/**
 * If a home folder-tile row id maps to a folder in the named "Genres" browse
 * collection, returns the genre name so the tile can open the genre hub.
 */
export function genreNameForFolderRowId(rowId: string, org: OrganizedCollections): string | null {
  const fid = rowId.startsWith('folder_') ? rowId.slice('folder_'.length) : rowId;
  const folder = org.folders.find(f => f.id === fid);
  if (!folder) return null;
  const collection = org.collections.find(c => c.id === folder.collectionId);
  if (!collection || normalize(collection.name) !== 'genres') return null;
  return folder.name;
}
