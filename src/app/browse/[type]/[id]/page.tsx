'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '../../../AuthProvider';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { Sidebar } from '@/components/Sidebar';
import { MetaDetail, StreamItem, Season } from '@/lib/types';
import { fetchMeta, fetchStreamsFromAll } from '@/lib/stremio';
import { isInLibrary, toggleLibrary, getWatchProgress } from '@/lib/services/api';
import { cacheStreams } from '@/lib/stream-cache';

const PlayIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 ml-0.5">
    <polygon points="6,4 20,12 6,20" />
  </svg>
);

const STREAILER_URL = 'https://9aa032f52161-streailer.baby-beamup.club/%7B%22language%22%3A%22en-US%22%2C%22externalLink%22%3Atrue%2C%22showRecap%22%3Atrue%7D';

export default function DetailPage({ params }: { params: { type: string; id: string } }) {
  const resolved = params;
  const { currentProfile, addons, user, isLoading } = useAuth();
  const router = useRouter();
  const [detail, setDetail] = useState<MetaDetail | null>(null);
  const [streams, setStreams] = useState<StreamItem[]>([]);
  const [inLibrary, setInLibrary] = useState(false);
  const [loading, setLoading] = useState(true);
  const [showStreams, setShowStreams] = useState(false);
  const [loadingStreams, setLoadingStreams] = useState(false);
  const [selectedSeason, setSelectedSeason] = useState<Season | null>(null);
  const [selectedEpisodeId, setSelectedEpisodeId] = useState<string | null>(null);
  const [autoPlaying, setAutoPlaying] = useState(false);
  const [trailers, setTrailers] = useState<{ id: string; title: string; youtubeId: string }[]>([]);
  const [savedPositionSeconds, setSavedPositionSeconds] = useState(0);

  useEffect(() => {
    if (isLoading) return;
    if (!user) { router.replace('/auth'); return; }
    if (!currentProfile) { router.replace('/profiles'); return; }
    loadAll();
  }, [currentProfile, resolved.type, resolved.id]);

  async function loadAll() {
    setLoading(true);
    try {
      const metaAddons = addons.filter(a => a.resources?.some(r => (typeof r === 'string' ? r : r.name) === 'meta'));
      let found: MetaDetail | null = null;
      for (const addon of metaAddons) {
        if (!addon.transportUrl) continue;
        found = await fetchMeta(addon.transportUrl, resolved.type, resolved.id);
        if (found) break;
      }
      const meta = found || { id: resolved.id, type: resolved.type, name: decodeURIComponent(resolved.id) };
      setDetail(meta);
      if (meta.seasons && meta.seasons.length > 0) {
        setSelectedSeason(meta.seasons[0]);
      }
      if (currentProfile) {
        const [lib, progress] = await Promise.all([
          isInLibrary(currentProfile.id, resolved.id),
          getWatchProgress(currentProfile.id),
        ]);
        setInLibrary(lib);
        // Find saved position: exact match for movies, prefix match for series episodes
        const entry = progress.find(p =>
          p.media_id === resolved.id ||
          p.media_id.startsWith(resolved.id + ':')
        );
        if (entry && entry.position_seconds > 0) {
          setSavedPositionSeconds(entry.position_seconds);
        }
      }

      // Fetch trailers from Streailer
      let streailerTrailers: { id: string; title: string; youtubeId: string }[] = [];
      try {
        const streailerRes = await fetch(`${STREAILER_URL}/stream/${resolved.type}/${resolved.id}.json`);
        const streailerData = await streailerRes.json();
        streailerTrailers = (streailerData.streams || [])
          .filter((s: any) => s.externalUrl && s.externalUrl.includes('youtube'))
          .map((s: any) => {
            const url = s.externalUrl;
            const match = url.match(/[?&]v=([^&]+)/) || url.match(/youtu\.be\/([^?]+)/);
            const youtubeId = match ? match[1] : '';
            return { id: youtubeId || s.name, title: s.title || s.name || 'Trailer', youtubeId };
          })
          .filter((t: any) => t.youtubeId);
      } catch {}

      setTrailers([
        ...streailerTrailers,
        ...(meta?.trailers || [])
          .map((t: any) => ({ id: t.id, title: t.title || 'Trailer', youtubeId: t.youtubeId || '' }))
          .filter((t: any) => t.youtubeId),
      ]);
    } catch {}
    setLoading(false);
  }

  async function handleToggleLibrary() {
    if (!currentProfile) return;
    await toggleLibrary(currentProfile.id, resolved.id, resolved.type, detail?.name, detail?.poster);
    setInLibrary(!inLibrary);
  }

  async function loadStreams(streamId?: string) {
    const id = streamId || resolved.id;
    setShowStreams(true);
    setLoadingStreams(true);
    setStreams([]);
    const allStreams = await fetchStreamsFromAll(resolved.type, id, addons);
    setStreams(allStreams);
    setLoadingStreams(false);
  }

  function handleEpisodeClick(episodeId: string) {
    setSelectedEpisodeId(episodeId);
    handleAutoPlay(episodeId);
  }

  function handlePlay(stream: StreamItem) {
    if (!stream.url) return;
    const mediaId = selectedEpisodeId || resolved.id;
    const cacheKey = `${resolved.type}:${mediaId}`;
    cacheStreams(cacheKey, streams);
    const encodedUrl = encodeURIComponent(stream.url);
    const ep = selectedEpisodeId && selectedSeason ? selectedSeason.episodes?.find(e => e.id === selectedEpisodeId) : null;
    const watchTitle = ep ? `${detail?.name || ''} — S${selectedSeason!.number}:E${ep.episode}: ${ep.title}` : (detail?.name || '');
    const posParam = savedPositionSeconds > 0 ? `&pos=${savedPositionSeconds}` : '';
    router.push(`/watch/${resolved.type}/${mediaId}?url=${encodedUrl}&cid=${encodeURIComponent(cacheKey)}&title=${encodeURIComponent(watchTitle)}${posParam}`);
  }

  async function handleAutoPlay(streamId?: string) {
    const id = streamId || resolved.id;
    setAutoPlaying(true);
    const allStreams = await fetchStreamsFromAll(resolved.type, id, addons);
    const playable = allStreams.filter(s => (s.url || s.externalUrl) && !s.infoHash && !s.behaviorHints?.notWebReady);
    const picked = playable[0];
    if (picked) {
      const cacheKey = `${resolved.type}:${id}`;
      cacheStreams(cacheKey, allStreams);
      const streamUrl = picked.url || picked.externalUrl!;
      const encodedUrl = encodeURIComponent(streamUrl);
      const ep = streamId && selectedSeason ? selectedSeason.episodes?.find(e => e.id === streamId) : null;
      const watchTitle = ep ? `${detail?.name || ''} — S${selectedSeason!.number}:E${ep.episode}: ${ep.title}` : (detail?.name || '');
      const posParam = savedPositionSeconds > 0 ? `&pos=${savedPositionSeconds}` : '';
      router.push(`/watch/${resolved.type}/${id}?url=${encodedUrl}&cid=${encodeURIComponent(cacheKey)}&title=${encodeURIComponent(watchTitle)}${posParam}`);
    } else {
      setAutoPlaying(false);
      setStreams(allStreams);
      setShowStreams(true);
    }
  }

  if (loading) {
    return (
      <Sidebar>
        <div className="flex items-center justify-center min-h-screen">
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-luna-accent border-t-transparent" />
        </div>
      </Sidebar>
    );
  }

  const backdropSrc = detail?.background || detail?.poster;
  const title = detail?.name || decodeURIComponent(resolved.id);
  const isSeries = resolved.type === 'series';

  // Reusable trailers section JSX
  const trailersSection = trailers.length > 0 ? (
    <section className="mb-8">
      <h3 className="text-sm font-bold text-white mb-4 px-6">Trailers &amp; Clips</h3>
      <div className="flex gap-4 overflow-x-auto pb-2 scrollbar-hide -mx-0 px-6">
        {trailers.map(trailer => (
          <a
            key={trailer.id}
            href={`https://www.youtube.com/watch?v=${trailer.youtubeId}`}
            target="_blank"
            rel="noopener noreferrer"
            className="flex-shrink-0 w-52 group cursor-pointer"
          >
            <div className="relative w-52 h-[117px] rounded-xl overflow-hidden bg-luna-elevated mb-2">
              <img
                src={`https://img.youtube.com/vi/${trailer.youtubeId}/mqdefault.jpg`}
                alt={trailer.title}
                className="absolute inset-0 w-full h-full object-cover"
                loading="lazy"
              />
              {/* Play overlay */}
              <div className="absolute inset-0 bg-black/30 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                <div className="w-12 h-12 rounded-full bg-white/20 backdrop-blur-sm flex items-center justify-center border border-white/25">
                  <svg viewBox="0 0 24 24" fill="white" className="w-5 h-5 ml-0.5">
                    <polygon points="6,4 20,12 6,20" />
                  </svg>
                </div>
              </div>
              {/* YouTube badge */}
              <div className="absolute bottom-2 right-2 bg-red-600/90 text-white text-[9px] font-bold px-1.5 py-0.5 rounded">
                YouTube
              </div>
            </div>
            <p className="text-sm font-semibold text-white line-clamp-1">{trailer.title}</p>
          </a>
        ))}
      </div>
    </section>
  ) : null;

  return (
    <Sidebar>
      {/* Cinematic full-bleed hero — pulled up behind navbar */}
      <div className="-mt-14 relative min-h-[85vh] flex items-end">
        {backdropSrc && (
          <div className="absolute inset-0 overflow-hidden">
            <img src={backdropSrc} alt="" className="w-full h-full object-cover object-[center_20%]" aria-hidden="true" />
          </div>
        )}
        {/* Top fade — blurs image into page bg */}
        <div className="absolute top-0 left-0 right-0 h-32 bg-gradient-to-b from-[#080808] to-transparent" />
        <div className="absolute inset-0 bg-gradient-to-t from-luna-bg via-luna-bg/30 to-transparent" />
        <div className="absolute inset-0 bg-gradient-to-r from-luna-bg/60 via-transparent to-transparent" />

        <div className="relative z-10 w-full px-6 pt-28 pb-10 max-w-5xl">
          <div className="max-w-xl">
            {detail?.logo ? (
              <img src={detail.logo} alt={title} className="h-14 sm:h-20 object-contain object-left mb-3" />
            ) : (
              <h1 className="text-3xl sm:text-5xl font-bold tracking-tight mb-3 text-white">{title}</h1>
            )}
            <div className="flex items-center gap-3 text-sm text-white/60 mb-4 flex-wrap">
              {(detail as any)?.year && <span>{(detail as any).year}</span>}
              {detail?.runtime && <span>{detail.runtime}</span>}
              {detail?.imdbRating && (
                <span className="flex items-center gap-1">
                  <svg viewBox="0 0 20 20" fill="#f59e0b" className="w-3.5 h-3.5">
                    <path fillRule="evenodd" d="M10.868 2.884c-.321-.772-1.415-.772-1.736 0l-1.83 4.401-4.753.381c-.833.067-1.171 1.107-.536 1.651l3.62 3.102-1.106 4.637c-.194.813.691 1.456 1.405 1.02L10 15.591l4.069 2.485c.713.436 1.598-.207 1.404-1.02l-1.106-4.637 3.62-3.102c.635-.544.297-1.584-.536-1.65l-4.752-.382-1.831-4.401z" clipRule="evenodd" />
                  </svg>
                  {detail.imdbRating}
                </span>
              )}
            </div>
            {detail?.genres && detail.genres.length > 0 && (
              <div className="flex flex-wrap gap-2 mb-4">
                {detail.genres.slice(0, 5).map(g => (
                  <span key={g} className="px-3 py-1 rounded-full bg-white/8 border border-white/10 text-xs text-white/70 font-medium">
                    {g}
                  </span>
                ))}
              </div>
            )}
            {detail?.description && (
              <p className="text-sm text-white/50 leading-relaxed mb-6 line-clamp-3">{detail.description}</p>
            )}
            <div className="flex gap-3 flex-wrap">
              {!isSeries && (
                <div className="flex gap-3">
                  <button onClick={() => handleAutoPlay()} disabled={autoPlaying}
                    className={`flex items-center gap-2 px-8 py-2.5 bg-white text-black font-semibold rounded-md transition-all ${autoPlaying ? 'opacity-70' : 'hover:bg-white/90'}`}>
                    {autoPlaying ? (
                      <div className="animate-spin rounded-full h-4 w-4 border-2 border-black border-t-transparent" />
                    ) : <PlayIcon />}
                    {autoPlaying ? 'Loading...' : 'Play'}
                  </button>
                  <button onClick={() => loadStreams()}
                    className="flex items-center gap-2 px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white font-semibold rounded-md transition-all text-sm">
                    Sources
                  </button>
                </div>
              )}
              <button onClick={handleToggleLibrary}
                className={`flex items-center gap-2 px-6 py-2.5 rounded-md font-semibold transition-all text-sm border ${
                  inLibrary ? 'bg-luna-accent/20 border-luna-accent/40 text-luna-accent' : 'bg-white/10 border-white/10 text-white hover:bg-white/15'
                }`}>
                <svg viewBox="0 0 24 24" fill={inLibrary ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.5" className="w-5 h-5">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0111.186 0z" />
                </svg>
                {inLibrary ? 'Saved' : 'Watchlist'}
              </button>
              {trailers.length > 0 && trailers[0].youtubeId && (
                <a
                  href={`https://www.youtube.com/watch?v=${trailers[0].youtubeId}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 px-5 py-2.5 rounded-md bg-white/8 border border-white/10 text-white font-semibold text-sm hover:bg-white/12 transition-all"
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" className="w-4 h-4 opacity-80">
                    <polygon points="5,3 19,12 5,21" fill="currentColor" stroke="none"/>
                  </svg>
                  Trailer
                </a>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Below fold — constrained content */}
      <div className="px-6 pb-12 max-w-5xl space-y-10">
        {/* Trailers & Clips — movies: before cast; series: rendered after episodes below */}
        {!isSeries && trailersSection}

        {/* Creator and Cast */}
        {detail?.cast && detail.cast.length > 0 && (
          <section>
            <h3 className="text-sm font-bold text-white mb-4">Cast &amp; Creators</h3>
            <div className="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
              {detail.cast.slice(0, 20).map(p => (
                <div key={p.name} className="flex-shrink-0 text-center w-16">
                  <div className="w-14 h-14 rounded-full bg-white/5 mx-auto mb-2 overflow-hidden ring-1 ring-white/10">
                    {p.photo ? (
                      <img src={p.photo} alt={p.name} className="w-full h-full object-cover" loading="lazy" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-sm font-semibold text-white/60">
                        {p.name[0]}
                      </div>
                    )}
                  </div>
                  <p className="text-xs text-white/60 truncate">{p.name}</p>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* More Like This */}
        {detail?.moreLikeThis && detail.moreLikeThis.length > 0 && (
          <section className="mb-8">
            <h3 className="text-sm font-bold text-white mb-4">More Like This</h3>
            <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-3">
              {detail.moreLikeThis.slice(0, 10).map(item => (
                <Link
                  key={item.id}
                  href={`/browse/${item.type}/${item.id}`}
                  className="group cursor-pointer"
                >
                  <div className="relative aspect-[2/3] rounded-lg overflow-hidden bg-luna-elevated mb-2">
                    {item.poster ? (
                      <img
                        src={item.poster}
                        alt={item.name}
                        className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                        loading="lazy"
                      />
                    ) : (
                      <div className="absolute inset-0 flex items-center justify-center text-white/20 text-xs font-semibold text-center px-2">{item.name}</div>
                    )}
                  </div>
                  <p className="text-xs font-medium text-white/80 truncate">{item.name}</p>
                  {item.releaseInfo && <p className="text-[10px] text-white/40 mt-0.5">{item.releaseInfo}</p>}
                </Link>
              ))}
            </div>
          </section>
        )}

        {/* Network / Production */}
        {detail?.links && detail.links.length > 0 && (() => {
          const networks = detail.links.filter(l => l.category === 'network');
          const studios = detail.links.filter(l => l.category === 'production');
          if (networks.length === 0 && studios.length === 0) return null;
          return (
            <section className="flex gap-8 flex-wrap">
              {networks.length > 0 && (
                <div>
                  <h4 className="text-xs font-bold text-white/40 uppercase tracking-wider mb-3">Network</h4>
                  <div className="flex gap-2 flex-wrap">
                    {networks.map(l => (
                      <span key={l.url} className="px-3 py-1.5 rounded-lg bg-white/6 border border-white/8 text-xs text-white/70 font-semibold">{l.name}</span>
                    ))}
                  </div>
                </div>
              )}
              {studios.length > 0 && (
                <div>
                  <h4 className="text-xs font-bold text-white/40 uppercase tracking-wider mb-3">Production</h4>
                  <div className="flex gap-2 flex-wrap">
                    {studios.map(l => (
                      <span key={l.url} className="px-3 py-1.5 rounded-lg bg-white/6 border border-white/8 text-xs text-white/70 font-semibold">{l.name}</span>
                    ))}
                  </div>
                </div>
              )}
            </section>
          );
        })()}

        {/* Streams */}
        {showStreams && (
          <section>
            <h3 className="text-sm font-semibold text-white mb-4">
              Sources {!loadingStreams && streams.length > 0 && <span className="text-white/30 font-normal">({streams.length})</span>}
            </h3>
            {loadingStreams ? (
              <div className="flex items-center gap-2 text-white/30 text-sm">
                <div className="animate-spin rounded-full h-4 w-4 border-2 border-luna-accent border-t-transparent" />
                Fetching streams...
              </div>
            ) : streams.length === 0 ? (
              <p className="text-white/30 text-sm">No sources found</p>
            ) : (
              <div className="space-y-1">
                {streams.slice(0, 30).map((s, i) => (
                  <button key={s.url || i} onClick={() => handlePlay(s)}
                    className="w-full text-left p-3 hover:bg-white/5 rounded-lg transition-all flex items-center justify-between group">
                    <div className="min-w-0">
                      <p className="text-sm text-white truncate">{s.title || s.name || s.description || 'Unknown'}</p>
                      <p className="text-xs text-white/30 mt-0.5">{s.addonName}</p>
                    </div>
                    <div className="flex-shrink-0 w-7 h-7 rounded-full bg-white/10 group-hover:bg-luna-accent/20 flex items-center justify-center ml-3 transition-colors opacity-0 group-hover:opacity-100">
                      <PlayIcon />
                    </div>
                  </button>
                ))}
              </div>
            )}
          </section>
        )}
      </div>

      {/* Episode section — full width, no max-w constraint */}
      {isSeries && detail?.seasons && detail.seasons.length > 0 && (
        <section className="mb-10 px-6">
          <h3 className="text-sm font-semibold text-white mb-4">Episodes</h3>
          <div className="flex gap-2 overflow-x-auto pb-2 mb-5 scrollbar-hide">
            {detail.seasons.map(s => (
              <button key={s.id}
                onClick={() => { setSelectedSeason(s); setShowStreams(false); setSelectedEpisodeId(null); }}
                className={`flex-shrink-0 px-4 py-2 rounded-md text-sm font-medium transition-all ${
                  selectedSeason?.id === s.id ? 'bg-white text-black' : 'bg-white/5 text-white/60 hover:bg-white/10 hover:text-white'
                }`}>
                Season {s.number}
              </button>
            ))}
          </div>
          {selectedSeason?.episodes && (
            <div className="flex gap-4 overflow-x-auto pb-3 scrollbar-hide -mx-6 px-6">
              {selectedSeason.episodes.map(ep => (
                <button
                  key={ep.id}
                  onClick={() => handleEpisodeClick(ep.id)}
                  className={`flex-shrink-0 w-52 text-left group rounded-xl overflow-hidden transition-all ${
                    selectedEpisodeId === ep.id ? 'ring-2 ring-luna-accent' : ''
                  }`}
                >
                  <div className="relative w-full aspect-video bg-luna-elevated rounded-xl overflow-hidden mb-2">
                    {ep.thumbnail ? (
                      <img src={ep.thumbnail} alt={ep.title} className="absolute inset-0 w-full h-full object-cover" loading="lazy" />
                    ) : (
                      <div className="absolute inset-0 flex items-center justify-center text-white/15 text-sm font-semibold">E{ep.episode}</div>
                    )}
                    <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                      <div className="w-10 h-10 rounded-full bg-white/20 backdrop-blur-sm flex items-center justify-center">
                        <svg viewBox="0 0 24 24" fill="white" className="w-4 h-4 ml-0.5"><polygon points="6,4 20,12 6,20" /></svg>
                      </div>
                    </div>
                  </div>
                  <p className="text-[10px] text-white/40 mb-0.5">Episode {ep.episode}</p>
                  {ep.released && (
                    <p className="text-[10px] text-white/30 mb-0.5">
                      {new Date(ep.released).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                    </p>
                  )}
                  <p className="text-sm font-semibold text-white truncate">{ep.title}</p>
                  {ep.overview && (
                    <p className="text-xs text-white/40 mt-1 line-clamp-2 leading-relaxed">{ep.overview}</p>
                  )}
                </button>
              ))}
            </div>
          )}
        </section>
      )}

      {/* Trailers & Clips — series only: rendered AFTER episodes */}
      {isSeries && (
        <div className="px-6 pb-8 max-w-5xl">
          {trailersSection}
        </div>
      )}

      {/* Auto-play loading overlay */}
      {autoPlaying && (
        <div className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-6 bg-black/90">
          {backdropSrc && (
            <div className="absolute inset-0 bg-cover bg-center opacity-30 blur-md" style={{ backgroundImage: `url(${backdropSrc})` }} />
          )}
          <div className="relative z-10 flex flex-col items-center gap-6">
            {detail?.logo ? (
              <img src={detail.logo} alt="" className="h-12 sm:h-16 object-contain" />
            ) : (
              <h2 className="text-lg font-semibold text-white">{title}</h2>
            )}
            <div className="animate-spin rounded-full h-8 w-8 border-2 border-luna-accent border-t-transparent" />
            <p className="text-sm text-white/40">Finding the best source...</p>
          </div>
        </div>
      )}
    </Sidebar>
  );
}
