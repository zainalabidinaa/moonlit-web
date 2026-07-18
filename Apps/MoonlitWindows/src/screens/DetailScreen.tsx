import { useState, useMemo, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import { useNavigate } from '@/shell/Shell';
import { fetchMeta } from '@/lib/stremio';
import { useAmbientColors } from '@/lib/design/artwork-color';
import type { MetaDetail, MetaPreview, MetaVideo, Season, Person } from '@/lib/types';

import PosterCard from '@/components/PosterCard';
import CastCard from '@/components/CastCard';
import EpisodeRow from '@/components/EpisodeRow';
import LoadingView from '@/components/LoadingView';
import ErrorState from '@/components/ErrorState';
import { Play, Plus, Check, Heart, Ellipsis, Eye, Star, ChevronDown } from 'lucide-react';

function releaseYear(releaseInfo?: string): string | undefined {
  if (!releaseInfo) return undefined;
  const d = releaseInfo.slice(0, 4);
  if (d.length === 4 && /^\d{4}$/.test(d)) return d;
  return releaseInfo;
}

function seasonSummary(detail: MetaDetail): string | undefined {
  const seasons = (detail.seasons || []).filter(s => s.number !== 0);
  if (seasons.length === 0) return undefined;
  return seasons.length === 1 ? '1 season' : `${seasons.length} seasons`;
}

function playButtonLabel(hasProgress: boolean, _isWatched: boolean, progress?: { positionSeconds: number; season?: number; episode?: number }) {
  if (_isWatched) return 'Rewatch';
  if (hasProgress && progress) {
    if (progress.season != null && progress.episode != null) return `Continue · S${progress.season}E${progress.episode}`;
    const mins = Math.floor(progress.positionSeconds / 60);
    const secs = Math.floor(progress.positionSeconds % 60);
    return `Continue · ${mins}:${String(secs).padStart(2, '0')}`;
  }
  return 'Play';
}

const HERO_HEIGHT = 780;

export function DetailScreen({ type, id }: { type: string; id: string }) {
  const navigate = useNavigate();
  const { addons } = useAuth();

  const [isLiked, setIsLiked] = useState(false);
  const [inWatchlist, setInWatchlist] = useState(false);
  const [isWatched, setIsWatched] = useState(false);
  const [showFullOverview, setShowFullOverview] = useState(false);
  const [selectedSeasonId, setSelectedSeasonId] = useState<string | null>(null);
  const [seasonPickerOpen, setSeasonPickerOpen] = useState(false);

  const { data: detail, isLoading, error } = useQuery({
    queryKey: ['meta-detail', type, id, addons.length],
    queryFn: async () => {
      const metaAddons = addons.filter(a =>
        a.transportUrl && a.resources?.some(r =>
          (typeof r === 'string' ? r : r.name) === 'meta' &&
          (typeof r === 'string' ? true : (r.types ? r.types.includes(type) : (a.types ? a.types.includes(type) : true)))
        )
      );
      const urls = metaAddons.map(a => a.transportUrl!).filter(Boolean);
      if (urls.length === 0) {
        urls.push(...addons.filter(a => a.transportUrl).map(a => a.transportUrl!));
      }

      for (const url of urls) {
        const result = await fetchMeta(url, type, id);
        if (result) return result;
      }
      throw new Error('No metadata found for this title.');
    },
    enabled: addons.length > 0,
    staleTime: 10 * 60 * 1000,
  });

  const sortedSeasons = useMemo(() => {
    const seasons = (detail?.seasons || []).filter(s => s.number !== 0);
    return seasons.sort((a, b) => a.number - b.number);
  }, [detail]);

  const activeSeason = useMemo(() => {
    if (!selectedSeasonId) return sortedSeasons[0];
    return sortedSeasons.find(s => s.id === selectedSeasonId) || sortedSeasons[0];
  }, [sortedSeasons, selectedSeasonId]);

  const episodes = activeSeason?.episodes || [];

  const backdropUrl = detail?.background;
  const ambient = useAmbientColors(backdropUrl);

  const handlePlay = useCallback(() => {
    if (!detail) return;
    navigate.startPlayback({
      type,
      id: detail.id,
      metadata: {
        mediaId: detail.id,
        mediaType: type,
        title: detail.name,
        poster: detail.poster,
        background: detail.background,
        logo: detail.logo,
      },
    });
  }, [detail, type, id, navigate]);

  if (isLoading) return <LoadingView />;
  if (error) return <ErrorState title="Failed to load" message={(error as Error).message} onRetry={() => window.location.reload()} />;
  if (!detail) return <ErrorState title="Not found" message="Could not load details for this title." />;

  const year = releaseYear(detail.releaseInfo);
  const sSummary = seasonSummary(detail);
  const genresSlice = (detail.genres || []).slice(0, 3);
  const hasLinks = !!(detail.links && detail.links.length > 0);
  const hasSeasons = !!(detail.seasons && detail.seasons.length > 0);
  const cast = detail.cast?.slice(0, 15) || [];
  const moreLike = detail.moreLikeThis?.slice(0, 20) || [];

  const links = detail.links || [];
  const networks = links.filter(l => l.category?.toLowerCase() === 'network');
  const studios = links.filter(l => l.category?.toLowerCase() === 'production');

  return (
    <div className="min-h-screen bg-moonlit-bg">
      {ambient && (
        <>
          <div
            className="fixed inset-0 pointer-events-none z-0"
            style={{
              background: `radial-gradient(ellipse at 50% 0%, ${ambient[0]} 0%, ${ambient[0]}22 40%, transparent 90%)`,
              opacity: 0.45,
            }}
          />
          <div
            className="fixed inset-0 pointer-events-none z-0"
            style={{
              background: `radial-gradient(ellipse at 75% 10%, ${ambient[1]} 0%, transparent 55%)`,
              opacity: 0.30,
            }}
          />
        </>
      )}

      <div className="relative z-10">
        <div className="relative overflow-hidden" style={{ height: HERO_HEIGHT }}>
          {backdropUrl ? (
            <>
              <img
                src={backdropUrl}
                alt=""
                className="absolute inset-0 w-full h-full object-cover object-top"
                style={{
                  maskImage: 'linear-gradient(to bottom, black 0%, black 48%, rgba(0,0,0,0.5) 72%, rgba(0,0,0,0.15) 88%, transparent 100%)',
                  WebkitMaskImage: 'linear-gradient(to bottom, black 0%, black 48%, rgba(0,0,0,0.5) 72%, rgba(0,0,0,0.15) 88%, transparent 100%)',
                }}
              />
              <div
                className="absolute inset-0"
                style={{
                  background: 'linear-gradient(to right, rgba(13,13,13,0.85) 0%, rgba(13,13,13,0.45) 28%, transparent 62%)',
                }}
              />
            </>
          ) : (
            <div className="w-full h-full bg-moonlit-elevated" />
          )}

          <div className="absolute bottom-[56px] left-0 right-0">
            <div className="max-w-[1500px] mx-auto px-[28px]">
              <div className="flex flex-col gap-[22px] max-w-[760px]">
                <div className="flex flex-col gap-[22px] max-w-[760px]">
                  {detail.tagline && (
                    <span className="text-[15px] font-medium text-white/48 tracking-[4.2px] uppercase line-clamp-1">
                      {detail.tagline}
                    </span>
                  )}

                  {detail.logo ? (
                    <img
                      src={detail.logo}
                      alt={detail.name}
                      className="object-contain"
                      style={{
                        maxWidth: 390,
                        maxHeight: 176,
                        filter: 'drop-shadow(0 5px 12px rgba(0,0,0,0.65))',
                      }}
                    />
                  ) : (
                    <h1
                      className="text-[66px] leading-tight font-medium line-clamp-2"
                      style={{
                        fontFamily: 'Georgia, serif',
                        background: 'linear-gradient(to bottom, #fff, rgba(212,175,55,0.85))',
                        WebkitBackgroundClip: 'text',
                        WebkitTextFillColor: 'transparent',
                        textShadow: '0 4px 10px rgba(0,0,0,0.52)',
                      }}
                    >
                      {detail.name}
                    </h1>
                  )}
                </div>

                <div className="flex flex-wrap items-center gap-[10px]">
                  {year && (
                    <span className="px-[13px] py-[8px] text-[14px] font-semibold text-white/75 bg-white/[0.045] rounded-full border border-white/10">
                      {year}
                    </span>
                  )}
                  {detail.imdbRating && (
                    <span className="flex items-center gap-[6px] px-[13px] py-[8px] bg-white/[0.045] rounded-full border border-white/10">
                      <span className="text-[11px] font-black text-[#D4AF37]">IMDb</span>
                      <Star size={10} className="fill-[#D4AF37] text-[#D4AF37]" />
                      <span className="text-[13px] font-semibold text-white/90">{detail.imdbRating}</span>
                    </span>
                  )}
                  {sSummary ? (
                    <span className="px-[13px] py-[8px] text-[14px] font-semibold text-white/75 bg-white/[0.045] rounded-full border border-white/10">
                      {sSummary}
                    </span>
                  ) : detail.runtime ? (
                    <span className="px-[13px] py-[8px] text-[14px] font-semibold text-white/75 bg-white/[0.045] rounded-full border border-white/10">
                      {detail.runtime}
                    </span>
                  ) : null}
                  {genresSlice.map(g => (
                    <span key={g} className="px-[13px] py-[8px] text-[14px] font-semibold text-white/75 bg-white/[0.045] rounded-full border border-white/10">
                      {g}
                    </span>
                  ))}
                </div>

                <div className="flex items-center gap-[12px] pt-[10px]">
                  <button
                    type="button"
                    className="btn-primary flex items-center gap-[8px] text-[15px] font-bold"
                    style={{ maxWidth: 240 }}
                    onClick={handlePlay}
                  >
                    <Play size={16} className="fill-black" />
                    {playButtonLabel(false, isWatched)}
                  </button>
                  <button
                    type="button"
                    className="flex items-center gap-[8px] text-[14px] font-semibold text-white px-[18px] py-[13px] bg-white/[0.12] rounded-full hover:bg-white/15 transition-colors"
                    onClick={() => setInWatchlist(v => !v)}
                  >
                    {inWatchlist ? <Check size={14} /> : <Plus size={14} />}
                    {inWatchlist ? 'In Watchlist' : 'Add to Watchlist'}
                  </button>
                  <button
                    type="button"
                    className="w-[50px] h-[50px] rounded-full bg-white/[0.12] flex items-center justify-center hover:bg-white/15 transition-colors"
                    onClick={() => setIsLiked(v => !v)}
                  >
                    <Heart size={17} className={isLiked ? 'fill-red-500 text-red-500' : 'text-white'} />
                  </button>
                  <button
                    type="button"
                    className="w-[50px] h-[50px] rounded-full bg-white/[0.12] flex items-center justify-center hover:bg-white/15 transition-colors"
                  >
                    <Ellipsis size={17} className="text-white" />
                  </button>
                </div>

                {detail.description && (
                  <div className="pt-[8px] max-w-[760px]">
                    <button
                      type="button"
                      className="text-left w-full"
                      onClick={() => setShowFullOverview(v => !v)}
                    >
                      <span className="text-[15px] font-bold text-white block mb-[6px]">Overview</span>
                      <p className={`text-[14px] font-medium text-white/70 ${showFullOverview ? '' : 'line-clamp-3'}`}>
                        {detail.description}
                      </p>
                      {!showFullOverview && detail.description.length > 220 && (
                        <span className="text-[12px] font-bold text-white/90 mt-1 block">Show more</span>
                      )}
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>

        {(networks.length > 0 || studios.length > 0) && (
          <div className="max-w-[1500px] mx-auto px-[28px] py-[10px] mt-[16px]">
            <div className="max-w-[760px]">
              {networks.length > 0 && (
                <div className="flex items-center gap-[12px] mb-[8px]">
                  <span className="text-[12px] font-semibold text-white/50 w-[80px]">NETWORK</span>
                  <div className="flex gap-2 flex-wrap">
                    {networks.map(l => (
                      <span key={l.name} className="text-[13px] font-medium text-[var(--accent)]">{l.name}</span>
                    ))}
                  </div>
                </div>
              )}
              {studios.length > 0 && (
                <div className="flex items-center gap-[12px]">
                  <span className="text-[12px] font-semibold text-white/50 w-[80px]">PRODUCTION</span>
                  <div className="flex gap-2 flex-wrap">
                    {studios.map(l => (
                      <span key={l.name} className="text-[13px] font-medium text-[var(--accent)]">{l.name}</span>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>
        )}

        {hasSeasons && detail.seasons && (
          <div className="max-w-[1500px] mx-auto px-[28px] py-[10px] mt-[28px]">
            <div className="flex items-center justify-between mb-[18px]">
              <div>
                <h2 className="text-[22px] font-bold text-white">Episodes</h2>
                <p className="text-[13px] font-medium text-white/50">
                  {activeSeason?.episodes?.length || 0} episode{(activeSeason?.episodes?.length || 0) === 1 ? '' : 's'}
                  {activeSeason?.episodes?.[0]?.released ? ` · ${activeSeason.episodes[0].released.slice(0, 4)}` : ''}
                </p>
              </div>

              <div className="flex items-center gap-3">
                <button
                  type="button"
                  className="w-[44px] h-[44px] rounded-full bg-white/10 flex items-center justify-center hover:bg-white/15 transition-colors"
                >
                  <Eye size={17} className="text-white/75" />
                </button>

                <div className="relative">
                  <button
                    type="button"
                    className="flex items-center gap-[8px] text-[16px] font-bold text-white px-[20px] py-[12px] bg-white/10 rounded-full hover:bg-white/15 transition-colors"
                    onClick={() => setSeasonPickerOpen(v => !v)}
                  >
                    {activeSeason?.name || `Season ${activeSeason?.number || 1}`}
                    <ChevronDown size={12} />
                  </button>
                  {seasonPickerOpen && (
                    <div className="absolute right-0 top-full mt-2 z-50">
                      <div
                        className="p-2 min-w-[240px] rounded-ml-lg"
                        style={{
                          background: 'rgba(13,13,13,0.97)',
                          backdropFilter: 'blur(40px)',
                          border: '0.8px solid rgba(255,255,255,0.12)',
                        }}
                      >
                        {sortedSeasons.map((season) => (
                          <button
                            key={season.id}
                            type="button"
                            className="flex items-center justify-between w-full px-[14px] py-[10px] rounded-[8px] text-left hover:bg-white/5 transition-colors"
                            style={{
                              background: season.id === (selectedSeasonId || sortedSeasons[0]?.id) ? 'rgba(255,255,255,0.06)' : 'transparent',
                            }}
                            onClick={() => {
                              setSelectedSeasonId(season.id);
                              setSeasonPickerOpen(false);
                            }}
                          >
                            <div>
                              <span className="text-[14px] font-semibold text-white block">{season.name || `Season ${season.number}`}</span>
                              <span className="text-[12px] font-medium text-white/50">
                                {season.episodes?.length || 0} episode{(season.episodes?.length || 0) === 1 ? '' : 's'}
                              </span>
                            </div>
                            {season.id === sortedSeasons[sortedSeasons.length - 1]?.id && (
                              <span className="text-[9px] font-bold text-black bg-[#D4AF37] px-[6px] py-[3px] rounded-full">NEW</span>
                            )}
                            {season.id === (selectedSeasonId || sortedSeasons[0]?.id) && (
                              <Check size={12} className="text-[#D4AF37]" />
                            )}
                          </button>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>
            </div>

            <div className="grid gap-x-5 gap-y-7" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 300px))' }}>
              {episodes.map((ep) => (
                <EpisodeRow
                  key={ep.id}
                  episode={ep}
                  seasonNumber={ep.season ?? activeSeason?.number ?? 1}
                  isWatched={false}
                  onToggleWatched={() => {}}
                  onPlay={() => {
                    navigate.startPlayback({
                      type,
                      id: ep.id,
                      metadata: {
                        mediaId: ep.id,
                        mediaType: type,
                        title: ep.title,
                        poster: detail.poster,
                        background: detail.background,
                      },
                    });
                  }}
                />
              ))}
            </div>
          </div>
        )}

        {cast.length > 0 && (
          <div className="mt-[28px]">
            <div className="max-w-[1500px] mx-auto px-[28px] mb-[10px]">
              <h2 className="text-[22px] font-bold text-white">Cast · {detail.cast?.length || cast.length}</h2>
            </div>
            <div className="overflow-x-auto scrollbar-hide">
              <div className="flex gap-[14px] px-[28px]">
                {cast.map((person) => (
                  <CastCard
                    key={person.id}
                    person={{
                      id: person.id,
                      name: person.name,
                      photo: person.photo,
                      character: undefined,
                    }}
                    onClick={() => navigate.navigateToActor(person.id, person.name)}
                  />
                ))}
              </div>
            </div>
          </div>
        )}

        {moreLike.length > 0 && (
          <div className="mt-[48px]">
            <div className="max-w-[1500px] mx-auto px-[28px] mb-[10px]">
              <h2 className="text-[22px] font-bold text-white">More Like This</h2>
            </div>
            <div className="overflow-x-auto scrollbar-hide">
              <div className="flex gap-[12px] px-[28px]">
                {moreLike.map((item) => (
                  <PosterCard
                    key={item.id}
                    item={item}
                    onClick={() => navigate.navigateTo(item.type, item.id)}
                  />
                ))}
              </div>
            </div>
          </div>
        )}

        <div className="h-8" />
      </div>
    </div>
  );
}
