import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { Star, ChevronDown, ChevronUp } from 'lucide-react';
import { useNavigate } from '@/shell/Shell';
import StrokeSpinner from '@/components/StrokeSpinner';
import LoadingView from '@/components/LoadingView';
import type { MetaPreview } from '@/lib/types';

interface ActorBioScreenProps {
  id: string;
  name: string;
}

interface PersonDetails {
  id: number;
  name: string;
  biography: string;
  birthday?: string;
  place_of_birth?: string;
  known_for_department?: string;
  also_known_as: string[];
  profile_path?: string;
  imdb_id?: string;
}

interface PersonCredit {
  id: number;
  title: string;
  character?: string;
  job?: string;
  media_type: string;
  poster_path?: string;
  backdrop_path?: string;
  release_date?: string;
  first_air_date?: string;
  vote_average?: number;
  episode_count?: number;
  popularity?: number;
}

const TMDB_API_KEY_STORAGE_KEY = 'moonlit.tmdbApiKey';

function getTMDBKey(): string {
  try {
    return localStorage.getItem(TMDB_API_KEY_STORAGE_KEY) || '';
  } catch {
    return '';
  }
}

function imageURL(path: string | undefined | null, size: string = 'w500'): string | undefined {
  if (!path) return undefined;
  return `https://image.tmdb.org/t/p/${size}${path}`;
}

function formatDate(dateStr: string): string {
  try {
    const d = new Date(dateStr + 'T00:00:00');
    return d.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
  } catch { return dateStr; }
}

function age(fromDate: string): number | undefined {
  try {
    const dob = new Date(fromDate + 'T00:00:00');
    const diff = Date.now() - dob.getTime();
    return new Date(diff).getUTCFullYear() - 1970;
  } catch { return undefined; }
}

type CreditFilter = 'all' | 'movie' | 'tv';

export function ActorBioScreen({ id, name }: ActorBioScreenProps) {
  const { navigateTo } = useNavigate();
  const [person, setPerson] = useState<PersonDetails | null>(null);
  const [credits, setCredits] = useState<PersonCredit[]>([]);
  const [knownFor, setKnownFor] = useState<PersonCredit[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [bioExpanded, setBioExpanded] = useState(false);
  const [mediaFilter, setMediaFilter] = useState<CreditFilter>('all');
  const [departmentFilter, setDepartmentFilter] = useState<string | null>(null);
  const [hoveredKFId, setHoveredKFId] = useState<number | null>(null);

  const handleMediaSelect = useCallback((credit: PersonCredit) => {
    const type = credit.media_type === 'tv' ? 'series' : 'movie';
    navigateTo(type, String(credit.id));
  }, [navigateTo]);

  useEffect(() => {
    let cancelled = false;
    const apiKey = getTMDBKey();
    if (!apiKey) {
      setError('TMDB API key not configured. Add it in Settings > Metadata.');
      setIsLoading(false);
      return;
    }

    async function load() {
      try {
        const personUrl = `https://api.themoviedb.org/3/person/${id}?api_key=${apiKey}&append_to_response=combined_credits`;
        const res = await fetch(personUrl);
        if (!res.ok) throw new Error(`Person not found (${res.status})`);
        const data = await res.json();

        if (!cancelled) {
          setPerson(data);
          const allCredits: PersonCredit[] = [
            ...(data.combined_credits?.cast || []),
            ...(data.combined_credits?.crew || []),
          ];

          const uniqueCredits = new Map<number, PersonCredit>();
          for (const c of allCredits) {
            if (!uniqueCredits.has(c.id)) uniqueCredits.set(c.id, c);
          }
          const sorted = Array.from(uniqueCredits.values()).sort((a, b) => (b.popularity || 0) - (a.popularity || 0));
          setCredits(sorted);
          setKnownFor(sorted.slice(0, 12));
        }
      } catch (e: any) {
        if (!cancelled) setError(e.message || 'Failed to load');
      }
      if (!cancelled) setIsLoading(false);
    }
    load();
    return () => { cancelled = true; };
  }, [id]);

  const filteredCredits = credits.filter(c => {
    if (mediaFilter === 'movie' && c.media_type !== 'movie') return false;
    if (mediaFilter === 'tv' && c.media_type !== 'tv') return false;
    if (departmentFilter && c.job !== departmentFilter && c.character !== departmentFilter) {
      const dept = c.character ? 'Acting' : c.job;
      if (dept !== departmentFilter) return false;
    }
    return true;
  });

  const departments = Array.from(new Set(
    credits.map(c => c.character ? 'Acting' : c.job).filter(Boolean) as string[]
  ));

  const groupedCredits = (() => {
    const groups = new Map<string, PersonCredit[]>();
    for (const c of filteredCredits) {
      const year = (c.release_date || c.first_air_date || 'Unknown').slice(0, 4);
      if (!groups.has(year)) groups.set(year, []);
      groups.get(year)!.push(c);
    }
    return Array.from(groups.entries()).sort(([a], [b]) => b.localeCompare(a));
  })();

  const knownForBackdrop = imageURL(knownFor[0]?.backdrop_path, 'w1280');

  return (
    <div className="min-h-screen bg-moonlit-bg relative">
      {knownForBackdrop && (
        <div className="fixed inset-0 pointer-events-none overflow-hidden">
          <img
            src={knownForBackdrop}
            alt=""
            className="absolute top-0 w-full h-[70vh] object-cover scale-110 blur-[80px] saturate-[1.3] opacity-45"
            style={{ maskImage: 'linear-gradient(to bottom, black 30%, transparent 100%)' }}
          />
          <div className="absolute top-0 w-full h-[70vh] bg-gradient-to-b from-moonlit-bg/40 via-moonlit-bg/70 to-moonlit-bg" />
        </div>
      )}

      <div className="relative z-10">
        {isLoading ? (
          <LoadingView />
        ) : error ? (
          <div className="flex flex-col items-center gap-2 pt-32">
            <span className="text-orange-400 text-lg">!</span>
            <p className="text-white/60">{error}</p>
          </div>
        ) : person ? (
          <div className="flex flex-col gap-0">
            <div className="flex items-center gap-[52px] px-12 pt-24 pb-5">
              <div className="w-[288px] h-[432px] rounded-[20px] overflow-hidden shadow-[0_18px_30px_rgba(0,0,0,0.58)] shrink-0">
                {person.profile_path ? (
                  <img src={imageURL(person.profile_path, 'w500')} alt={person.name} className="w-full h-full object-cover" />
                ) : (
                  <div className="w-full h-full bg-white/[0.05] flex items-center justify-center">
                    <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-white/20"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-4 4-7 8-7s8 3 8 7"/></svg>
                  </div>
                )}
              </div>

              <div className="flex flex-col gap-3 min-w-0">
                <span className="text-[12px] font-semibold tracking-[5px] text-white/45 uppercase">
                  {person.known_for_department || 'Acting'}
                </span>
                <h1 className="text-[78px] font-medium font-serif text-white tracking-[-2px] leading-none">{person.name}</h1>

                <div className="flex gap-4 flex-wrap">
                  {person.birthday && (
                    <span className="text-[15px] font-medium text-white/60">
                      Born {formatDate(person.birthday)}{age(person.birthday) ? ` · ${age(person.birthday)}` : ''}
                    </span>
                  )}
                  {person.place_of_birth && (
                    <span className="text-[15px] font-medium text-white/60">{person.place_of_birth}</span>
                  )}
                </div>

                {person.biography && (
                  <div className="pt-1.5">
                    <p className={`text-[15px] font-medium text-white/60 leading-relaxed ${bioExpanded ? '' : 'line-clamp-8'}`}>
                      {person.biography}
                    </p>
                    {person.biography.length > 400 && (
                      <button
                        type="button"
                        onClick={() => setBioExpanded(!bioExpanded)}
                        className="text-[12px] font-bold text-white mt-1 hover:underline"
                      >
                        {bioExpanded ? 'Show Less' : 'Show More'}
                      </button>
                    )}
                  </div>
                )}
              </div>
            </div>

            {(person.birthday || person.place_of_birth || person.also_known_as.length > 0 || person.known_for_department) && (
              <>
                <h2 className="text-[24px] font-semibold font-serif text-white px-12 pt-10 pb-4">Personal Info</h2>
                <div className="mx-12 bg-black/28 rounded-[18px] border border-white/[0.08] overflow-hidden">
                  {person.known_for_department && <InfoRow label="Area of Work" value={person.known_for_department} />}
                  {person.birthday && (
                    <InfoRow
                      label="Born"
                      value={`${formatDate(person.birthday)}${age(person.birthday) ? ` (age ${age(person.birthday)})` : ''}`}
                    />
                  )}
                  {person.place_of_birth && <InfoRow label="Place of Birth" value={person.place_of_birth} />}
                  {person.also_known_as[0] && <InfoRow label="Also Known As" value={person.also_known_as[0]} />}
                </div>
              </>
            )}

            {knownFor.length > 0 && (
              <>
                <h2 className="text-[24px] font-semibold font-serif text-white px-12 pt-10 pb-4">Known For</h2>
                <div className="overflow-x-auto scrollbar-hide">
                  <div className="flex gap-4 px-12 py-2.5">
                    {knownFor.map(credit => (
                      <div
                        key={credit.id}
                        className="flex flex-col gap-1.5 shrink-0 cursor-pointer"
                        onMouseEnter={() => setHoveredKFId(credit.id)}
                        onMouseLeave={() => setHoveredKFId(null)}
                        onClick={() => handleMediaSelect(credit)}
                      >
                        <div
                          className="w-[190px] h-[285px] rounded-[14px] overflow-hidden shadow-[0_10px_18px_rgba(0,0,0,0.38)] transition-transform duration-200"
                          style={{
                            transform: hoveredKFId === credit.id ? 'translateY(-8px)' : 'translateY(0)',
                            boxShadow: hoveredKFId === credit.id
                              ? `0 10px 28px rgba(0,0,0,0.5), 0 0 20px rgba(212,175,55,0.15)`
                              : undefined,
                          }}
                        >
                          {imageURL(credit.poster_path, 'w300') ? (
                            <img src={imageURL(credit.poster_path, 'w300')} alt={credit.title} className="w-full h-full object-cover" />
                          ) : (
                            <div className="w-full h-full bg-white/[0.05]" />
                          )}
                        </div>
                        <p className="text-[15px] font-semibold text-white line-clamp-2 w-[190px]">{credit.title}</p>
                        <p className="text-[13px] text-white/50">{(credit.release_date || credit.first_air_date || '').slice(0, 4)}</p>
                      </div>
                    ))}
                  </div>
                </div>
              </>
            )}

            {credits.length > 0 && (
              <>
                <h2 className="text-[24px] font-semibold font-serif text-white px-12 pt-10 pb-4">Credits</h2>
                <div className="flex gap-2 px-12 pb-3">
                  <select
                    value={mediaFilter}
                    onChange={e => setMediaFilter(e.target.value as CreditFilter)}
                    className="px-3.5 py-2 text-[13px] font-semibold text-white bg-white/[0.06] border border-white/[0.1] rounded-full appearance-none cursor-pointer"
                  >
                    <option value="all">All</option>
                    <option value="movie">Movies</option>
                    <option value="tv">Series</option>
                  </select>
                  <select
                    value={departmentFilter || ''}
                    onChange={e => setDepartmentFilter(e.target.value || null)}
                    className="px-3.5 py-2 text-[13px] font-semibold text-white bg-white/[0.06] border border-white/[0.1] rounded-full appearance-none cursor-pointer"
                  >
                    <option value="">All Departments</option>
                    {departments.map(d => (
                      <option key={d} value={d}>{d}</option>
                    ))}
                  </select>
                </div>

                <div className="px-12">
                  {groupedCredits.map(([year, yearCredits]) => (
                    <div key={year} className="flex gap-4">
                      <div className="w-[62px] text-right pt-3 shrink-0">
                        <span className="text-[20px] font-serif text-white/45 font-mono">{year}</span>
                      </div>
                      <div className="flex flex-col items-center shrink-0">
                        <div className="w-[7px] h-[7px] rounded-full bg-white/40 mt-[17px]" />
                        <div className="w-px flex-1 bg-white/[0.07]" />
                      </div>
                      <div className="flex flex-col gap-2 pb-5 flex-1 min-w-0">
                        {yearCredits.map(credit => {
                          const yearStr = (credit.release_date || credit.first_air_date || '').slice(0, 4);
                          const role = credit.character || credit.job || '';
                          const mediaLabel = credit.media_type === 'tv' ? 'Series' : 'Movie';
                          const eps = credit.episode_count ? ` · ${credit.episode_count} ep${credit.episode_count > 1 ? 's' : ''}` : '';
                          const subtitle = [role, mediaLabel].filter(Boolean).join(' · ') + eps;

                          return (
                            <div
                              key={credit.id}
                              className="flex items-center gap-3 px-[18px] py-3.5 bg-black/26 rounded-[14px] border border-white/[0.05] cursor-pointer hover:bg-black/40 transition-colors"
                              onClick={() => handleMediaSelect(credit)}
                            >
                              <div className="w-[54px] h-[81px] rounded-[7px] overflow-hidden shrink-0">
                                {imageURL(credit.poster_path, 'w185') ? (
                                  <img src={imageURL(credit.poster_path, 'w185')} alt={credit.title} className="w-full h-full object-cover" />
                                ) : (
                                  <div className="w-full h-full bg-white/[0.05]" />
                                )}
                              </div>
                              <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                                <p className="text-[16px] font-semibold text-white truncate">{credit.title}</p>
                                <p className="text-[13.5px] text-white/45 truncate">{subtitle || yearStr}</p>
                              </div>
                              {credit.vote_average && credit.vote_average > 0 && (
                                <div className="flex items-center gap-1 shrink-0">
                                  <Star size={9} fill="currentColor" className="text-harbor-gold" />
                                  <span className="text-[13px] font-bold text-harbor-gold">{credit.vote_average.toFixed(1)}</span>
                                </div>
                              )}
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  ))}
                </div>
              </>
            )}

            <div className="h-10" />
          </div>
        ) : null}
      </div>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start gap-[22px] px-5 py-3.5 border-b border-white/[0.06] last:border-b-0">
      <span className="text-[13px] font-semibold text-white/40 w-[120px] shrink-0">{label}</span>
      <span className="text-[15px] font-medium text-white">{value}</span>
    </div>
  );
}
