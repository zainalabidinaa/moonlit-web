import { useState, useEffect, useRef, type CSSProperties } from 'react';
import { useParams } from '@tanstack/react-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import { usePlayer } from '@/app/PlayerProvider';
import { FusionBackground } from '@/components/FusionBackground';
import { MediaRow } from '@/components/MediaRow';
import { MetaDetail, StreamItem, Season } from '@/lib/types';
import { fetchMeta, fetchStreamsFromAll } from '@/lib/stremio';
import { isInUserWatchlist, toggleUserWatchlistItem, getWatchProgress } from '@/lib/services/api';
import { cacheStreams } from '@/lib/stream-cache';
import { getPlayableStreamUrl } from '@/lib/player-utils';
import { TMDB_API_KEY } from '@/lib/supabase';
import { useAmbientColors } from '@/lib/design/artwork-color';
import { useArtworkPreferences } from './catalog-data';

const PlayIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 ml-0.5">
    <polygon points="6,4 20,12 6,20" />
  </svg>
);

const STREAILER_URL = 'https://9aa032f52161-streailer.baby-beamup.club/%7B%22language%22%3A%22en-US%22%2C%22externalLink%22%3Atrue%2C%22showRecap%22%3Atrue%7D';

export default function DetailPage() {
  const { type, id } = useParams({ strict: false }) as { type: string; id: string };
  const { currentProfile, addons } = useAuth();
  const { open: openPlayer } = usePlayer();
  const queryClient = useQueryClient();
  const artworkPreferences = useArtworkPreferences(currentProfile?.id);

  const [streams, setStreams] = useState<StreamItem[]>([]);
  const [showStreams, setShowStreams] = useState(false);
  const [loadingStreams, setLoadingStreams] = useState(false);
  const [selectedSeason, setSelectedSeason] = useState<Season | null>(null);
  const [selectedEpisodeId, setSelectedEpisodeId] = useState<string | null>(null);
  const prefetchedRef = useRef<string | null>(null);
  const [watchlistOverride, setWatchlistOverride] = useState<boolean | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['browse', type, id, currentProfile?.id],
    queryFn: async () => {
      const metaAddons = addons.filter(a => a.resources?.some(r => (typeof r === 'string' ? r : r.name) === 'meta'));
      let detail: MetaDetail | null = null;
      for (const addon of metaAddons) {
        if (!addon.transportUrl) continue;
        detail = await fetchMeta(addon.transportUrl, type, id);
        if (detail) break;
      }
      let enrichedMeta: MetaDetail = detail || { id, type, name: decodeURIComponent(id) } as MetaDetail;

      const initialSeason = enrichedMeta.seasons && enrichedMeta.seasons.length > 0 ? enrichedMeta.seasons[0] : null;

      let inLib = false;
      let savedPosition = 0;
      let trailers: { id: string; title: string; youtubeId: string }[] = [];
      let recentEp: { mediaId: string; positionSec: number } | null = null;
      const epProgress: Record<string, number> = {};

      if (currentProfile) {
        const [lib, progress] = await Promise.all([
          isInUserWatchlist(currentProfile.id, id),
          getWatchProgress(currentProfile.id),
        ]);
        inLib = lib;
        const decoded = progress.map(p => ({ ...p, media_id: decodeURIComponent(p.media_id) }));
        const entry = decoded.find(p => p.media_id === id || p.media_id.startsWith(id + ':'));
        if (entry && entry.position_seconds > 0) savedPosition = entry.position_seconds;
        const recentEpEntry = decoded
          .filter(p => p.media_id.startsWith(id + ':') && p.position_seconds > 0 && !p.completed)
          .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())[0] ?? null;
        if (recentEpEntry) recentEp = { mediaId: recentEpEntry.media_id, positionSec: recentEpEntry.position_seconds };
        for (const p of decoded) {
          if (p.media_id.startsWith(id + ':') && p.duration_seconds > 0) {
            epProgress[p.media_id] = Math.min(1, p.position_seconds / p.duration_seconds);
          }
        }
      }

      try {
        const res = await fetch(`${STREAILER_URL}/stream/${type}/${id}.json`);
        const streailerData = await res.json();
        trailers = (streailerData.streams || [])
          .filter((s: any) => s.externalUrl?.includes('youtube'))
          .map((s: any) => {
            const url = s.externalUrl;
            const match = url.match(/[?&]v=([^&]+)/) || url.match(/youtu\.be\/([^?]+)/);
            const youtubeId = match ? match[1] : '';
            return { id: youtubeId || s.name, title: s.title || s.name || 'Trailer', youtubeId };
          })
          .filter((t: any) => t.youtubeId);
      } catch {}

      trailers = [
        ...trailers,
        ...(enrichedMeta.trailers || [])
          .map((t: any) => ({ id: t.id || t.source, title: t.title || 'Trailer', youtubeId: t.youtubeId || t.source || '' }))
          .filter((t: any) => t.youtubeId),
      ];

      const seenIds = new Set<string>();
      trailers = trailers.filter(t => { if (seenIds.has(t.youtubeId)) return false; seenIds.add(t.youtubeId); return true; });

      try {
        let tmdbId = enrichedMeta.tmdbId;
        if (!tmdbId && id.startsWith('tt')) {
          const findRes = await fetch(
            `https://api.themoviedb.org/3/find/${id}?api_key=${TMDB_API_KEY}&external_source=imdb_id`
          );
          if (findRes.ok) {
            const findData = await findRes.json();
            const hit = type === 'series' ? findData.tv_results?.[0] : findData.movie_results?.[0];
            if (hit?.id) tmdbId = String(hit.id);
          }
        }

        if (tmdbId) {
          const tmdbType = type === 'series' ? 'tv' : 'movie';
          const tmdbRes = await fetch(
            `https://api.themoviedb.org/3/${tmdbType}/${tmdbId}?api_key=${TMDB_API_KEY}&append_to_response=credits,similar`
          );
          if (tmdbRes.ok) {
            const tmdb = await tmdbRes.json();
            const updates: Partial<MetaDetail> = {};
            if (tmdb.credits?.cast?.length) {
              updates.cast = (tmdb.credits.cast as any[]).slice(0, 25).map((c: any) => ({
                id: String(c.id),
                name: c.name,
                photo: c.profile_path ? `https://image.tmdb.org/t/p/w185${c.profile_path}` : undefined,
              }));
            }
            if (!enrichedMeta.moreLikeThis?.length && tmdb.similar?.results?.length) {
              updates.moreLikeThis = (tmdb.similar.results as any[]).slice(0, 15).map((r: any) => ({
                id: String(r.id),
                type,
                name: r.name || r.title || 'Unknown',
                poster: r.poster_path ? `https://image.tmdb.org/t/p/w342${r.poster_path}` : undefined,
                releaseInfo: (r.first_air_date || r.release_date || '').slice(0, 4),
              }));
            }
            if (Object.keys(updates).length) enrichedMeta = { ...enrichedMeta, ...updates };
          }
        }
      } catch {}

      return { meta: enrichedMeta, inLib, savedPosition, trailers, initialSeason, recentEp, epProgress };
    },
    staleTime: 60 * 60 * 1000,
    enabled: addons.length > 0,
  });

  const detail = data?.meta ?? null;
  const inLibrary = watchlistOverride ?? data?.inLib ?? false;
  const savedPositionSeconds = data?.savedPosition ?? 0;
  const trailers = data?.trailers ?? [];
  const recentEp = data?.recentEp ?? null;
  const epProgress = data?.epProgress ?? {};
  const backdropSrc = detail?.background || detail?.poster;
  const ambient = useAmbientColors(backdropSrc);
  const activeSeason = selectedSeason ?? data?.initialSeason ?? null;

  async function handleToggleLibrary() {
    if (!currentProfile || !detail) return;
    const next = !inLibrary;
    setWatchlistOverride(next);
    try {
      await toggleUserWatchlistItem(currentProfile.id, {
        media_id: id,
        media_type: type,
        name: detail.name,
        poster: detail.poster,
      });
      queryClient.invalidateQueries({ queryKey: ['user-watchlist', currentProfile.id] });
      queryClient.invalidateQueries({ queryKey: ['browse', type, id, currentProfile.id] });
    } catch {
      setWatchlistOverride(!next);
    }
  }

  useEffect(() => {
    if (!addons.length) return;
    const sid = selectedEpisodeId || id;
    const cacheKey = `${type}:${sid}`;
    const addonKey = addons.map(a => a.id).join(',');
    const fullKey = `${cacheKey}:${addonKey}`;
    if (prefetchedRef.current === fullKey) return;
    prefetchedRef.current = fullKey;
    fetchStreamsFromAll(type, sid, addons).then(fetched => {
      if (fetched.length > 0) cacheStreams(cacheKey, fetched);
    }).catch(() => {});
  }, [addons, id, type, selectedEpisodeId]);

  async function loadStreams(streamId?: string) {
    const sid = streamId || id;
    setShowStreams(true);
    setLoadingStreams(true);
    setStreams([]);
    const allStreams = await fetchStreamsFromAll(type, sid, addons);
    setStreams(allStreams);
    setLoadingStreams(false);
  }

  function handlePlay(stream: StreamItem) {
    const streamUrl = getPlayableStreamUrl(stream);
    if (!streamUrl) return;
    const mediaId = selectedEpisodeId || id;
    const cacheKey = `${type}:${mediaId}`;
    cacheStreams(cacheKey, streams);
    const ep = selectedEpisodeId && activeSeason ? activeSeason.episodes?.find(e => e.id === selectedEpisodeId) : null;
    const watchTitle = ep ? `${detail?.name || ''} — S${activeSeason!.number}:E${ep.episode}: ${ep.title}` : (detail?.name || '');
    openPlayer({
      type, id: mediaId,
      streamUrl,
      streams,
      metadata: { mediaId, mediaType: type, title: watchTitle, logo: detail?.logo ?? undefined, poster: detail?.poster ?? undefined, background: detail?.background ?? undefined },
      startPosition: savedPositionSeconds > 0 ? savedPositionSeconds : undefined,
    });
  }

  function handleAutoPlay(streamId?: string) {
    const sid = streamId || id;
    const ep = streamId && activeSeason ? activeSeason.episodes?.find(e => e.id === streamId) : null;
    const watchTitle = ep
      ? `${detail?.name || ''} — S${activeSeason!.number}:E${ep.episode}: ${ep.title}`
      : (detail?.name || '');
    openPlayer({
      type, id: sid,
      metadata: { mediaId: sid, mediaType: type, title: watchTitle, logo: detail?.logo ?? undefined, poster: detail?.poster ?? undefined, background: detail?.background ?? undefined },
      startPosition: savedPositionSeconds > 0 ? savedPositionSeconds : undefined,
    });
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="w-7 h-7 rounded-full border-2 border-white/[0.14] border-t-white animate-spin-arc" />
      </div>
    );
  }

  const title = detail?.name || decodeURIComponent(id);
  const isSeries = type === 'series';

  return (
    <div className="detail-page pb-16">
      <FusionBackground backdropUrl={backdropSrc} heroHeight={780} />

      <section
        data-detail-hero
        aria-label={`${title} details`}
        className="detail-hero relative flex items-end overflow-hidden"
        style={{ '--detail-hero-height': '780px' } as CSSProperties}
      >
        {backdropSrc && (
          <img src={backdropSrc} alt="" className="absolute inset-0 h-full w-full object-cover object-[center_20%]" />
        )}
        {ambient && (
          <div aria-hidden="true" className="absolute inset-0 overflow-hidden opacity-50">
            <div className="absolute inset-0" style={{ background: `linear-gradient(to bottom, ${ambient[0]}55, transparent 62%)` }} />
            <div className="absolute inset-0" style={{ background: `radial-gradient(circle at 72% 10%, ${ambient[1]}42, transparent 54%)` }} />
          </div>
        )}
        <div aria-hidden="true" className="absolute inset-0 bg-gradient-to-t from-[#0d0d0d] via-[#0d0d0d]/30 to-transparent" />
        <div aria-hidden="true" className="absolute inset-0 bg-gradient-to-r from-[#0d0d0d]/90 via-[#0d0d0d]/28 to-transparent" />

        <div className="relative z-10 w-full max-w-[1500px] px-4 pb-14 pt-28 sm:px-6 md:px-14">
          <div className="max-w-[760px]">
            {detail?.logo ? (
              <>
                <h1 className="sr-only">{title}</h1>
                <img src={detail.logo} alt={title} className="mb-5 max-h-28 max-w-[min(440px,82vw)] object-contain object-left drop-shadow-2xl" />
              </>
            ) : (
              <h1 className="mb-5 text-4xl font-black leading-none tracking-tight text-white sm:text-6xl">{title}</h1>
            )}

            <div className="mb-5 flex flex-wrap items-center gap-2.5 text-sm text-white/65">
              {detail?.releaseInfo && <span>{detail.releaseInfo}</span>}
              {detail?.runtime && <span>{detail.runtime}</span>}
              {detail?.imdbRating && <span className="rating-badge">★ {detail.imdbRating}</span>}
              {detail?.genres?.slice(0, 3).map(genre => <span key={genre}>{genre}</span>)}
              {detail?.awards?.[0] && <span className="font-semibold text-white/75">{detail.awards[0]}</span>}
            </div>

            <div className="mb-7 flex flex-wrap items-center gap-3">
              {!isSeries ? (
                <button type="button" onClick={() => handleAutoPlay()} className="btn-primary flex min-h-11 items-center gap-2 rounded-full">
                  <PlayIcon /> Play
                </button>
              ) : recentEp ? (
                <button type="button" onClick={() => handleAutoPlay(recentEp.mediaId)} className="btn-primary flex min-h-11 items-center gap-2 rounded-full">
                  <PlayIcon /> Continue {recentEp.mediaId.split(':').slice(1, 3).join('E')}
                </button>
              ) : detail?.seasons?.[0]?.episodes?.[0] ? (
                <button type="button" onClick={() => handleAutoPlay(detail.seasons![0].episodes![0].id)} className="btn-primary flex min-h-11 items-center gap-2 rounded-full">
                  <PlayIcon /> Play First Episode
                </button>
              ) : null}

              <button
                type="button"
                onClick={handleToggleLibrary}
                aria-label={inLibrary ? 'Remove from watchlist' : 'Add to watchlist'}
                aria-pressed={inLibrary}
                className={`detail-icon-action ${inLibrary ? 'detail-icon-action-active' : ''}`}
              >
                <svg aria-hidden="true" viewBox="0 0 24 24" fill={inLibrary ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.6">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M17.6 3.3c1.1.1 1.9 1.1 1.9 2.2V21L12 17.3 4.5 21V5.5c0-1.1.8-2.1 1.9-2.2a48.5 48.5 0 0 1 11.2 0Z" />
                </svg>
              </button>
              {!isSeries && (
                <button type="button" onClick={() => loadStreams()} aria-label="Choose source" className="detail-icon-action">
                  <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path strokeLinecap="round" d="M4 7h16M4 12h16M4 17h16" /></svg>
                </button>
              )}
            </div>

            {detail?.description && (
              <div className="max-w-[680px]">
                <h2 className="mb-2 text-[15px] font-bold text-white">Overview</h2>
                <p className="line-clamp-3 text-sm font-medium leading-relaxed text-white/70">{detail.description}</p>
              </div>
            )}
          </div>
        </div>
      </section>

      <div className="relative mx-auto max-w-[1500px] space-y-12 px-4 sm:px-6 md:px-14">
        {trailers.length > 0 && (
          <section aria-labelledby="trailers-heading">
            <h2 id="trailers-heading" className="detail-section-title">Trailers &amp; Clips</h2>
            <div className="flex gap-4 overflow-x-auto pb-3 scrollbar-hide">
              {trailers.map(trailer => (
                <a key={trailer.id} href={`https://www.youtube.com/watch?v=${trailer.youtubeId}`} target="_blank" rel="noopener noreferrer" className="detail-trailer-card group">
                  <span className="relative block aspect-video overflow-hidden rounded-ml-card bg-moonlit-elevated">
                    <img src={`https://img.youtube.com/vi/${trailer.youtubeId}/mqdefault.jpg`} alt="" className="h-full w-full object-cover" loading="lazy" />
                    <span className="absolute inset-0 flex items-center justify-center bg-black/20">
                      <span className="flex h-11 w-11 items-center justify-center rounded-full bg-white text-black"><PlayIcon /></span>
                    </span>
                  </span>
                  <span className="mt-2 block truncate text-sm font-semibold text-white">{trailer.title}</span>
                </a>
              ))}
            </div>
          </section>
        )}

        {isSeries && detail?.seasons && detail.seasons.length > 0 && (
          <section aria-labelledby="episodes-heading">
            <div className="mb-5 flex flex-wrap items-center gap-3">
              <h2 id="episodes-heading" className="detail-section-title !mb-0">Episodes</h2>
              <div role="group" aria-label="Choose season" className="flex gap-2 overflow-x-auto py-1 scrollbar-hide">
                {detail.seasons.map(season => (
                  <button
                    key={season.id}
                    type="button"
                    aria-pressed={activeSeason?.id === season.id}
                    onClick={() => { setSelectedSeason(season); setShowStreams(false); setSelectedEpisodeId(null); }}
                    className={`category-pill min-h-11 whitespace-nowrap ${activeSeason?.id === season.id ? 'category-pill-active' : 'category-pill-idle'}`}
                  >
                    Season {season.number}
                  </button>
                ))}
              </div>
            </div>
            <div className="grid grid-cols-[repeat(auto-fit,minmax(min(260px,100%),1fr))] gap-5">
              {activeSeason?.episodes?.map(ep => (
                <button
                  key={ep.id}
                  type="button"
                  onClick={() => { setSelectedEpisodeId(ep.id); handleAutoPlay(ep.id); }}
                  className="episode-card group min-w-0 text-left"
                >
                  <span className="relative block aspect-video overflow-hidden rounded-ml-card bg-moonlit-elevated">
                    {ep.thumbnail ? <img src={ep.thumbnail} alt="" className="h-full w-full object-cover" loading="lazy" /> : <span className="flex h-full items-center justify-center text-white/30">Episode {ep.episode}</span>}
                    {epProgress[ep.id] > 0 && (
                      <span role="progressbar" aria-label={`${ep.title} progress`} aria-valuenow={Math.round(epProgress[ep.id] * 100)} aria-valuemin={0} aria-valuemax={100} className="media-progress-track">
                        <span style={{ width: `${epProgress[ep.id] * 100}%` }} />
                      </span>
                    )}
                  </span>
                  <span className="mt-3 block text-xs font-semibold uppercase tracking-wider text-white/45">Episode {ep.episode}</span>
                  <span className="mt-1 block truncate text-sm font-semibold text-white">{ep.title}</span>
                  {ep.overview && <span className="mt-1.5 block line-clamp-2 text-xs leading-relaxed text-white/50">{ep.overview}</span>}
                </button>
              ))}
            </div>
          </section>
        )}

        {detail?.cast && detail.cast.length > 0 && (
          <section aria-labelledby="cast-heading">
            <h2 id="cast-heading" className="detail-section-title">Cast &amp; Creators</h2>
            <div className="flex gap-5 overflow-x-auto pb-3 scrollbar-hide">
              {detail.cast.slice(0, 25).map(person => (
                <article key={person.id || person.name} className="w-24 shrink-0 text-center">
                  <span className="mx-auto mb-2 flex h-24 w-24 items-center justify-center overflow-hidden rounded-full bg-white/5 ring-1 ring-white/10">
                    {person.photo ? <img src={person.photo} alt="" className="h-full w-full object-cover" loading="lazy" /> : <span className="text-lg font-semibold text-white/55">{person.name[0]}</span>}
                  </span>
                  <h3 className="truncate text-xs font-medium text-white/70">{person.name}</h3>
                </article>
              ))}
            </div>
          </section>
        )}

        {detail?.gallery && detail.gallery.length > 0 && (
          <section aria-labelledby="gallery-heading">
            <h2 id="gallery-heading" className="detail-section-title">Gallery</h2>
            <div className="flex gap-4 overflow-x-auto pb-3 scrollbar-hide">
              {detail.gallery.map(image => (
                <figure key={image.id} className="w-[min(420px,82vw)] shrink-0">
                  <img src={image.url} alt={image.caption || `${title} gallery image`} className="aspect-video w-full rounded-ml-card object-cover ring-1 ring-white/10" loading="lazy" />
                  {image.caption && <figcaption className="mt-2 text-xs text-white/50">{image.caption}</figcaption>}
                </figure>
              ))}
            </div>
          </section>
        )}

        {detail?.awards && detail.awards.length > 0 && (
          <section aria-labelledby="awards-heading">
            <h2 id="awards-heading" className="detail-section-title">Awards</h2>
            <div className="glass-panel max-w-2xl rounded-ml-lg p-6">
              {detail.awards.map(award => <p key={award} className="text-sm font-semibold text-moonlit-rating-gold">★ {award}</p>)}
            </div>
          </section>
        )}

        {detail?.links && detail.links.length > 0 && (
          <section aria-labelledby="links-heading">
            <h2 id="links-heading" className="detail-section-title">Links</h2>
            <div className="flex flex-wrap gap-3">
              {detail.links.map(link => (
                <a key={link.url} href={link.url} target="_blank" rel="noopener noreferrer" className="glass-panel inline-flex min-h-11 items-center rounded-full px-4 text-sm font-semibold text-white/80 hover:text-white">
                  {link.name} <span aria-hidden="true" className="ml-2">↗</span>
                </a>
              ))}
            </div>
          </section>
        )}

        {detail?.moreLikeThis && detail.moreLikeThis.length > 0 && (
          <MediaRow title="Recommendations" items={detail.moreLikeThis} artworkPreferences={artworkPreferences} />
        )}

        {showStreams && (
          <section aria-labelledby="sources-heading">
            <h2 id="sources-heading" className="detail-section-title">Sources</h2>
            {loadingStreams ? (
              <p role="status" className="text-sm text-white/50">Fetching sources…</p>
            ) : streams.length === 0 ? (
              <p className="text-sm text-white/50">No sources found.</p>
            ) : (
              <div className="grid gap-2">
                {streams.slice(0, 30).map((stream, index) => (
                  <button key={stream.url ? `${stream.url}-${index}` : `stream-${index}`} type="button" onClick={() => handlePlay(stream)} className="surface-card min-h-11 p-3 text-left text-sm text-white hover:bg-white/10">
                    {stream.title || stream.name || stream.description || 'Unknown source'}
                    {stream.addonName && <span className="ml-2 text-white/40">· {stream.addonName}</span>}
                  </button>
                ))}
              </div>
            )}
          </section>
        )}
      </div>
    </div>
  );
}
