import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { Globe } from 'lucide-react';
import { useNavigate } from '@/shell/Shell';
import { languageColors } from '@/lib/design/oklch';
import PosterCard from '@/components/PosterCard';
import LoadingView from '@/components/LoadingView';
import type { MetaPreview } from '@/lib/types';

interface LanguageHubScreenProps {
  iso: string;
  name: string;
}

interface BrowseRail {
  id: string;
  title: string;
  items: MetaPreview[];
}

const TMDB_API_KEY_STORAGE_KEY = 'moonlit.tmdbApiKey';

function getTMDBKey(): string {
  try {
    return localStorage.getItem(TMDB_API_KEY_STORAGE_KEY) || '';
  } catch {
    return '';
  }
}

interface TmdbItem {
  id: number;
  title?: string;
  name?: string;
  poster_path?: string;
  backdrop_path?: string;
  release_date?: string;
  first_air_date?: string;
  popularity?: number;
  vote_average?: number;
  vote_count?: number;
}

const GENERAL_RAIL_DEFS: { title: string; kind: string; params: Record<string, string> }[] = [
  { title: 'Popular', kind: 'both', params: { sort_by: 'popularity.desc', 'vote_count.gte': '30' } },
  { title: 'Top Rated', kind: 'both', params: { sort_by: 'vote_average.desc', 'vote_count.gte': '50' } },
  { title: 'New Releases', kind: 'both', params: { sort_by: 'primary_release_date.desc', 'vote_count.gte': '5' } },
  { title: 'Hidden Gems', kind: 'both', params: { sort_by: 'vote_average.desc', 'vote_count.gte': '15', 'vote_count.lte': '300', 'vote_average.gte': '7.0' } },
  { title: 'Classics', kind: 'both', params: { sort_by: 'vote_average.desc', 'vote_count.gte': '20', 'vote_average.gte': '7.0', 'release_date.lte': '2000-12-31' } },
];

const LANGUAGE_SPECIFIC_DEFS: Record<string, { title: string; kind: string; params: Record<string, string> }[]> = {
  ko: [
    { title: 'K-Drama', kind: 'tv', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '30' } },
    { title: 'Korean Horror', kind: 'movie', params: { with_genres: '27', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Korean Action', kind: 'movie', params: { with_genres: '28', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Korean Thriller', kind: 'movie', params: { with_genres: '53', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Korean Romance', kind: 'movie', params: { with_genres: '10749', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Korean Comedy', kind: 'movie', params: { with_genres: '35', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  ja: [
    { title: 'Anime', kind: 'tv', params: { with_genres: '16', sort_by: 'popularity.desc', 'vote_count.gte': '50' } },
    { title: 'Japanese Horror', kind: 'movie', params: { with_genres: '27', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Japanese Crime', kind: 'movie', params: { with_genres: '80', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Japanese Sci-Fi', kind: 'movie', params: { with_genres: '878', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Japanese Drama', kind: 'tv', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  hi: [
    { title: 'Indian Drama', kind: 'movie', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Indian Romance', kind: 'movie', params: { with_genres: '10749', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Indian Action', kind: 'movie', params: { with_genres: '28', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Indian Comedy', kind: 'movie', params: { with_genres: '35', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Indian Thriller', kind: 'movie', params: { with_genres: '53', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  fr: [
    { title: 'French Thriller', kind: 'movie', params: { with_genres: '53', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'French Comedy', kind: 'movie', params: { with_genres: '35', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'French Drama', kind: 'movie', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  es: [
    { title: 'Spanish Thriller', kind: 'movie', params: { with_genres: '53', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Spanish Horror', kind: 'movie', params: { with_genres: '27', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Spanish Comedy', kind: 'movie', params: { with_genres: '35', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  ar: [
    { title: 'Egyptian Cinema', kind: 'movie', params: { with_origin_country: 'EG', sort_by: 'popularity.desc', 'vote_count.gte': '10' } },
    { title: 'Levant Drama', kind: 'tv', params: { with_origin_country: 'LB,SY,JO,PS', sort_by: 'popularity.desc' } },
    { title: 'Gulf Cinema', kind: 'movie', params: { with_origin_country: 'SA,AE,KW,QA,OM,BH', sort_by: 'popularity.desc' } },
    { title: 'Maghreb Cinema', kind: 'movie', params: { with_origin_country: 'MA,DZ,TN', sort_by: 'popularity.desc' } },
    { title: 'Arab Classics', kind: 'movie', params: { sort_by: 'vote_average.desc', 'vote_count.gte': '10', 'vote_average.gte': '6.5', 'release_date.lte': '2000-12-31' } },
    { title: 'Arab Comedy', kind: 'movie', params: { with_genres: '35', sort_by: 'popularity.desc', 'vote_count.gte': '10' } },
  ],
  de: [
    { title: 'German Thriller', kind: 'movie', params: { with_genres: '53', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'German Crime', kind: 'movie', params: { with_genres: '80', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'German Drama', kind: 'movie', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  it: [
    { title: 'Italian Drama', kind: 'movie', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Italian Comedy', kind: 'movie', params: { with_genres: '35', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Italian Crime', kind: 'movie', params: { with_genres: '80', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  tr: [
    { title: 'Turkish Drama', kind: 'tv', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Turkish Romance', kind: 'tv', params: { with_genres: '10749', sort_by: 'popularity.desc', 'vote_count.gte': '10' } },
    { title: 'Turkish Action', kind: 'movie', params: { with_genres: '28', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  sv: [
    { title: 'Nordic Noir', kind: 'tv', params: { with_origin_country: 'SE,NO,DK,FI,IS', with_genres: '80,53', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Nordic Crime', kind: 'movie', params: { with_origin_country: 'SE,NO,DK,FI,IS', with_genres: '80', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Nordic Drama', kind: 'tv', params: { with_origin_country: 'SE,NO,DK,FI,IS', with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  ru: [
    { title: 'Russian Sci-Fi', kind: 'movie', params: { with_genres: '878', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Russian Drama', kind: 'movie', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Russian War', kind: 'movie', params: { with_genres: '10752', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  pl: [
    { title: 'Polish Drama', kind: 'movie', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Polish Thriller', kind: 'movie', params: { with_genres: '53', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Polish Crime', kind: 'movie', params: { with_genres: '80', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  th: [
    { title: 'Thai Horror', kind: 'movie', params: { with_genres: '27', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Thai Drama', kind: 'tv', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Thai Action', kind: 'movie', params: { with_genres: '28', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
  ],
  nl: [
    { title: 'Dutch Drama', kind: 'movie', params: { with_genres: '18', sort_by: 'popularity.desc', 'vote_count.gte': '20' } },
    { title: 'Dutch Documentary', kind: 'movie', params: { with_genres: '99', sort_by: 'popularity.desc', 'vote_count.gte': '10' } },
  ],
};

function languageHue(iso: string): number {
  const hues: Record<string, number> = {
    ko: 25, ja: 350, es: 60, fr: 260, zh: 10, hi: 300,
    de: 40, it: 145, pt: 130, tr: 200, sv: 230, da: 0,
    no: 250, ru: 340, pl: 170, th: 320, nl: 80, ar: 165,
  };
  return hues[iso] ?? 200;
}

async function fetchTMDBItems(kind: string, apiKey: string, params: Record<string, string>, iso: string): Promise<MetaPreview[]> {
  const type = kind === 'tv' || kind === 'tv' ? 'tv' : 'movie';
  let url = `https://api.themoviedb.org/3/discover/${type}?api_key=${apiKey}&with_original_language=${iso}`;
  for (const [k, v] of Object.entries(params)) {
    url += `&${k}=${v}`;
  }
  try {
    const res = await fetch(url);
    if (!res.ok) return [];
    const data = await res.json();
    const results: TmdbItem[] = data.results?.slice(0, 20) || [];
    const items: MetaPreview[] = [];
    for (const m of results) {
      const tmdbId = m.id;
      let imdbId = `tmdb:${tmdbId}`;
      try {
        const extRes = await fetch(`https://api.themoviedb.org/3/${type}/${tmdbId}/external_ids?api_key=${apiKey}`);
        const extData = await extRes.json();
        if (extData?.imdb_id) imdbId = extData.imdb_id;
      } catch {}
      items.push({
        id: kind === 'movie' ? imdbId : imdbId,
        type: kind === 'movie' ? 'movie' : 'series',
        name: m.title || m.name || 'Unknown',
        poster: m.poster_path ? `https://image.tmdb.org/t/p/w500${m.poster_path}` : undefined,
        releaseInfo: (m.release_date || m.first_air_date || '').slice(0, 4),
        popularity: m.popularity,
        imdbRating: m.vote_average ? String(m.vote_average.toFixed(1)) : undefined,
      } as MetaPreview);
    }
    return items;
  } catch {
    return [];
  }
}

function getGeneralDefs(iso: string): typeof GENERAL_RAIL_DEFS {
  if (iso === 'ar') {
    return [
      { title: 'Popular', kind: 'both', params: { sort_by: 'popularity.desc', 'vote_count.gte': '15' } },
      { title: 'Top Rated', kind: 'both', params: { sort_by: 'vote_average.desc', 'vote_count.gte': '30' } },
      { title: 'New Releases', kind: 'both', params: { sort_by: 'primary_release_date.desc', 'vote_count.gte': '3' } },
      { title: 'Hidden Gems', kind: 'both', params: { sort_by: 'vote_average.desc', 'vote_count.gte': '10', 'vote_count.lte': '300', 'vote_average.gte': '6.5' } },
      { title: 'Classics', kind: 'both', params: { sort_by: 'vote_average.desc', 'vote_count.gte': '10', 'vote_average.gte': '6.5', 'release_date.lte': '2000-12-31' } },
    ];
  }
  return GENERAL_RAIL_DEFS;
}

export function LanguageHubScreen({ iso, name }: LanguageHubScreenProps) {
  const { navigateTo } = useNavigate();
  const [featuredTVRails, setFeaturedTVRails] = useState<BrowseRail[]>([]);
  const [featuredMovieRails, setFeaturedMovieRails] = useState<BrowseRail[]>([]);
  const [tvRails, setTVRails] = useState<BrowseRail[]>([]);
  const [movieRails, setMovieRails] = useState<BrowseRail[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const handleMediaSelect = useCallback((item: MetaPreview) => {
    navigateTo(item.type, item.id);
  }, [navigateTo]);

  useEffect(() => {
    let cancelled = false;
    const apiKey = getTMDBKey();
    if (!apiKey) { setIsLoading(false); return; }

    async function load() {
      const generalDefs = getGeneralDefs(iso);
      const specificDefs = LANGUAGE_SPECIFIC_DEFS[iso] ?? [];

      const tvDefs = generalDefs.filter(d => d.kind === 'both' || d.kind === 'tv');
      const movieDefs = generalDefs.filter(d => d.kind === 'both' || d.kind === 'movie');
      const featuredTVDefs = specificDefs.filter(d => d.kind === 'tv');
      const featuredMovieDefs = specificDefs.filter(d => d.kind === 'movie');

      async function fetchRails(kind: string, defs: typeof generalDefs): Promise<BrowseRail[]> {
        const results = await Promise.all(defs.map(async def => {
          const items = await fetchTMDBItems(kind, apiKey, def.params, iso);
          if (items.length === 0) return null;
          const id = `lang-${kind}-${def.title.replace(/\s+/g, '-').toLowerCase()}`;
          return { id, title: def.title, items };
        }));
        return results.filter(Boolean) as BrowseRail[];
      }

      const [ftv, fmv, tv, mov] = await Promise.all([
        fetchRails('tv', featuredTVDefs),
        fetchRails('movie', featuredMovieDefs),
        fetchRails('tv', tvDefs),
        fetchRails('movie', movieDefs),
      ]);

      if (!cancelled) {
        setFeaturedTVRails(ftv);
        setFeaturedMovieRails(fmv);
        setTVRails(tv);
        setMovieRails(mov);
        setIsLoading(false);
      }
    }
    load();
    return () => { cancelled = true; };
  }, [iso, name]);

  const palette = languageColors(languageHue(iso));
  const ambientStyle = {
    background: `radial-gradient(ellipse 80% 60% at 30% 20%, ${palette.from}44, ${palette.to}11, transparent 70%)`,
  };

  const isEmpty = featuredTVRails.length === 0 && featuredMovieRails.length === 0 && tvRails.length === 0 && movieRails.length === 0;

  return (
    <div className="min-h-screen bg-moonlit-bg relative">
      <div className="fixed inset-0 pointer-events-none" style={ambientStyle} />
      <div className="relative z-10">
        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.3 }}>
          {isLoading && isEmpty ? (
            <LoadingView />
          ) : (
            <div className="flex flex-col gap-14 pt-24 pb-12">
              <div className="px-8">
                <span className="text-[13px] font-bold tracking-[6px] text-white/40 uppercase">Language</span>
                <h1 className="text-[60px] font-bold font-serif text-white mt-2">{name}</h1>
              </div>

              {isEmpty && !isLoading && (
                <div className="flex flex-col items-center gap-3 py-16">
                  <Globe size={40} className="text-white/30" />
                  <p className="text-[16px] text-white/50">No content found for {name}</p>
                </div>
              )}

              {(featuredTVRails.length > 0 || featuredMovieRails.length > 0) && (
                <>
                  <h2 className="text-[21px] font-bold text-white px-8">Featured</h2>
                  {[...featuredTVRails, ...featuredMovieRails].map(rail => (
                    <RailView key={rail.id} rail={rail} onClick={handleMediaSelect} />
                  ))}
                </>
              )}

              {tvRails.length > 0 && (
                <>
                  <h2 className="text-[21px] font-bold text-white px-8">Series</h2>
                  {tvRails.map(rail => (
                    <RailView key={rail.id} rail={rail} onClick={handleMediaSelect} />
                  ))}
                </>
              )}

              {movieRails.length > 0 && (
                <>
                  <h2 className="text-[21px] font-bold text-white px-8">Movies</h2>
                  {movieRails.map(rail => (
                    <RailView key={rail.id} rail={rail} onClick={handleMediaSelect} />
                  ))}
                </>
              )}

              <div className="h-12" />
            </div>
          )}
        </motion.div>
      </div>
    </div>
  );
}

function RailView({ rail, onClick }: { rail: BrowseRail; onClick: (item: MetaPreview) => void }) {
  return (
    <div>
      <h3 className="text-[15px] font-semibold text-white px-8 mb-3">{rail.title}</h3>
      <div className="overflow-x-auto scrollbar-hide">
        <div className="flex gap-3 px-8 py-2.5">
          {rail.items.map(item => (
            <PosterCard key={item.id} item={item} onClick={() => onClick(item)} />
          ))}
        </div>
      </div>
    </div>
  );
}
