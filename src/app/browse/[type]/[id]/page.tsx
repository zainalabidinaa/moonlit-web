'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '../../../AuthProvider';
import { useRouter } from 'next/navigation';
import { Sidebar } from '@/components/Sidebar';
import { MetaDetail, StreamItem, Season } from '@/lib/types';
import { fetchMeta, fetchStreamsFromAll } from '@/lib/stremio';
import { isInLibrary, toggleLibrary } from '@/lib/services/api';
import { cacheStreams } from '@/lib/stream-cache';

const PlayIcon = () => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 ml-0.5">
    <path fillRule="evenodd" d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.348c1.295.712 1.295 2.573 0 3.285L7.28 19.991c-1.25.687-2.779-.217-2.779-1.643V5.653z" clipRule="evenodd" />
  </svg>
);

const BookmarkIcon = ({ filled }: { filled: boolean }) => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill={filled ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth={1.5} className="w-5 h-5">
    <path strokeLinecap="round" strokeLinejoin="round" d="M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0111.186 0z" />
  </svg>
);

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
      // Auto-select first season for series
      if (meta.seasons && meta.seasons.length > 0) {
        setSelectedSeason(meta.seasons[0]);
      }
      if (currentProfile) {
        const lib = await isInLibrary(currentProfile.id, resolved.id);
        setInLibrary(lib);
      }
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
    const cacheKey = `${resolved.type}:${selectedEpisodeId || resolved.id}`;
    cacheStreams(cacheKey, streams);
    const encodedUrl = encodeURIComponent(stream.url);
    router.push(`/watch/${resolved.type}/${selectedEpisodeId || resolved.id}?url=${encodedUrl}&cid=${encodeURIComponent(cacheKey)}`);
  }

  async function handleAutoPlay(streamId?: string) {
    const id = streamId || resolved.id;
    setAutoPlaying(true);
    const streamAddons = addons.filter(a => a.transportUrl && a.resources?.some(r => (typeof r === 'string' ? r : r.name) === 'stream'));
    console.log('[handleAutoPlay] type:', resolved.type, 'id:', id, 'stream addons:', streamAddons.length);
    const allStreams = await fetchStreamsFromAll(resolved.type, id, addons);
    console.log('[handleAutoPlay] total streams:', allStreams.length, allStreams.slice(0, 3).map(s => ({ url: s.url?.slice(0, 60), infoHash: s.infoHash, notWebReady: s.behaviorHints?.notWebReady, addonName: s.addonName })));
    const playable = allStreams.filter(s => (s.url || s.externalUrl) && !s.infoHash && !s.behaviorHints?.notWebReady);
    const picked = playable[0];
    if (picked) {
      const cacheKey = `${resolved.type}:${id}`;
      cacheStreams(cacheKey, allStreams);
      const streamUrl = picked.url || picked.externalUrl!;
      const encodedUrl = encodeURIComponent(streamUrl);
      router.push(`/watch/${resolved.type}/${id}?url=${encodedUrl}&cid=${encodeURIComponent(cacheKey)}`);
    } else {
      console.log('[handleAutoPlay] no playable streams found');
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

  const backdropSrc = (detail as any)?.background || detail?.poster;
  const title = detail?.name || decodeURIComponent(resolved.id);
  const isSeries = resolved.type === 'series';

  return (
    <Sidebar>
      {/* Hero */}
      <div className="relative min-h-[60vh] flex items-end">
        {backdropSrc && (
          <div className="absolute inset-0 overflow-hidden">
            <img src={backdropSrc} alt="" className="w-full h-full object-cover scale-105 blur-sm" aria-hidden="true" />
          </div>
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-luna-bg via-luna-bg/60 to-transparent" />
        <div className="absolute inset-0 bg-gradient-to-r from-luna-bg/80 via-transparent to-transparent" />

        <div className="relative z-10 px-6 pt-28 pb-8 flex gap-6 items-end w-full max-w-5xl">
          {detail?.poster && (
            <div className="hidden sm:block flex-shrink-0 w-36 h-52 rounded-xl overflow-hidden shadow-2xl ring-1 ring-white/10">
              <img src={detail.poster} alt={title} className="w-full h-full object-cover" />
            </div>
          )}
          <div className="flex-1 min-w-0">
            <h1 className="text-3xl sm:text-4xl font-bold tracking-tight mb-2 text-white">{title}</h1>
            <div className="flex items-center gap-3 text-sm text-luna-muted mb-3 flex-wrap">
              {(detail as any)?.year && <span>{(detail as any).year}</span>}
              {detail?.runtime && <span>{detail.runtime}</span>}
              {detail?.imdbRating && (
                <span className="flex items-center gap-1">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="#f59e0b" className="w-3.5 h-3.5">
                    <path fillRule="evenodd" d="M10.868 2.884c-.321-.772-1.415-.772-1.736 0l-1.83 4.401-4.753.381c-.833.067-1.171 1.107-.536 1.651l3.62 3.102-1.106 4.637c-.194.813.691 1.456 1.405 1.02L10 15.591l4.069 2.485c.713.436 1.598-.207 1.404-1.02l-1.106-4.637 3.62-3.102c.635-.544.297-1.584-.536-1.65l-4.752-.382-1.831-4.401z" clipRule="evenodd" />
                  </svg>
                  {detail.imdbRating}
                </span>
              )}
            </div>
            {detail?.genres && detail.genres.length > 0 && (
              <div className="flex gap-2 flex-wrap mb-4">
                {detail.genres.map(g => (
                  <span key={g} className="px-3 py-1 bg-white/10 border border-white/10 rounded-full text-xs text-white/80">{g}</span>
                ))}
              </div>
            )}
            {detail?.description && (
              <p className="text-sm text-luna-muted leading-relaxed mb-5 max-w-xl line-clamp-3">{detail.description}</p>
            )}
            <div className="flex gap-3 flex-wrap">
              {!isSeries && (
                <div className="flex gap-2">
                  <button
                    onClick={() => handleAutoPlay()}
                    disabled={autoPlaying}
                    className={`flex items-center gap-2 px-6 py-2.5 bg-white text-black font-semibold rounded-full transition-all duration-200 cursor-pointer text-sm ${
                      autoPlaying ? 'opacity-70' : 'hover:bg-white/90'
                    }`}
                  >
                    {autoPlaying ? (
                      <div className="animate-spin rounded-full h-4 w-4 border-2 border-black border-t-transparent" />
                    ) : (
                      <PlayIcon />
                    )}
                    {autoPlaying ? 'Loading...' : 'Play'}
                  </button>
                  <button
                    onClick={() => loadStreams()}
                    className="flex items-center gap-2 px-6 py-2.5 bg-white/10 hover:bg-white/15 border border-white/10 text-white font-semibold rounded-full transition-all duration-200 cursor-pointer text-sm"
                  >
                    Sources
                  </button>
                </div>
              )}
              <button
                onClick={handleToggleLibrary}
                className={`flex items-center gap-2 px-6 py-2.5 rounded-full font-semibold transition-all duration-200 cursor-pointer text-sm border ${
                  inLibrary
                    ? 'bg-luna-accent/20 border-luna-accent/40 text-luna-accent'
                    : 'bg-white/10 border-white/10 text-white hover:bg-white/15'
                }`}
              >
                <BookmarkIcon filled={inLibrary} />
                {inLibrary ? 'Saved' : 'Watchlist'}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Below fold */}
      <div className="px-6 pb-12 max-w-5xl space-y-8">

        {/* Cast */}
        {detail?.cast && detail.cast.length > 0 && (
          <section>
            <h3 className="text-sm font-semibold text-white mb-3">Cast</h3>
            <div className="flex gap-4 overflow-x-auto pb-2">
              {detail.cast.slice(0, 20).map(p => (
                <div key={p.name} className="flex-shrink-0 text-center w-14">
                  <div className="w-12 h-12 rounded-full bg-luna-elevated mx-auto mb-1.5 flex items-center justify-center text-sm font-semibold text-white ring-1 ring-white/10">
                    {p.name[0]}
                  </div>
                  <p className="text-xs text-luna-muted truncate">{p.name}</p>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* Seasons + Episodes */}
        {isSeries && detail?.seasons && detail.seasons.length > 0 && (
          <section>
            {/* Season tabs */}
            <div className="flex gap-2 overflow-x-auto pb-2 mb-4">
              {detail.seasons.map(s => (
                <button
                  key={s.id}
                  onClick={() => { setSelectedSeason(s); setShowStreams(false); setSelectedEpisodeId(null); }}
                  className={`flex-shrink-0 px-4 py-1.5 rounded-full text-sm font-medium transition-all cursor-pointer ${
                    selectedSeason?.id === s.id
                      ? 'bg-luna-accent text-white'
                      : 'bg-white/10 text-luna-muted hover:bg-white/15'
                  }`}
                >
                  Season {s.number}
                </button>
              ))}
            </div>

            {/* Episodes grid */}
            {selectedSeason?.episodes && (
              <div className="space-y-2">
                {selectedSeason.episodes.map(ep => (
                  <button
                    key={ep.id}
                    onClick={() => handleEpisodeClick(ep.id)}
                    className={`w-full text-left flex gap-3 p-3 rounded-xl border transition-all cursor-pointer group ${
                      selectedEpisodeId === ep.id
                        ? 'bg-luna-accent/10 border-luna-accent/30'
                        : 'bg-white/5 border-white/5 hover:bg-white/10 hover:border-white/10'
                    }`}
                  >
                    {ep.thumbnail ? (
                      <img src={ep.thumbnail} alt={ep.title} className="w-24 h-14 object-cover rounded-lg flex-shrink-0" loading="lazy" />
                    ) : (
                      <div className="w-24 h-14 bg-luna-elevated rounded-lg flex-shrink-0 flex items-center justify-center text-luna-muted text-xs">
                        E{ep.episode}
                      </div>
                    )}
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-white truncate">
                        {ep.episode}. {ep.title}
                      </p>
                      {ep.overview && (
                        <p className="text-xs text-luna-muted mt-1 line-clamp-2">{ep.overview}</p>
                      )}
                    </div>
                    <div className="flex-shrink-0 self-center w-7 h-7 rounded-full bg-white/10 group-hover:bg-luna-accent/20 flex items-center justify-center transition-colors">
                      <PlayIcon />
                    </div>
                  </button>
                ))}
              </div>
            )}
          </section>
        )}

        {/* Streams */}
        {showStreams && (
          <section>
            <h3 className="text-sm font-semibold text-white mb-3">
              Sources {!loadingStreams && streams.length > 0 && <span className="text-luna-muted font-normal">({streams.length})</span>}
            </h3>
            {loadingStreams ? (
              <div className="flex items-center gap-2 text-luna-muted text-sm">
                <div className="animate-spin rounded-full h-4 w-4 border-2 border-luna-accent border-t-transparent" />
                Fetching streams...
              </div>
            ) : streams.length === 0 ? (
              <p className="text-luna-muted text-sm">No sources found</p>
            ) : (
              <div className="space-y-2">
                {streams.slice(0, 30).map((s, i) => (
                  <button
                    key={s.url || i}
                    onClick={() => handlePlay(s)}
                    className="w-full text-left p-3 bg-white/5 hover:bg-white/10 border border-white/5 hover:border-white/10 rounded-xl transition-all duration-200 flex items-center justify-between cursor-pointer group"
                  >
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-white truncate">{s.title || s.name || s.description || 'Unknown'}</p>
                      <p className="text-xs text-luna-muted">{s.addonName}</p>
                    </div>
                    <div className="flex-shrink-0 w-7 h-7 rounded-full bg-white/10 group-hover:bg-luna-accent/20 flex items-center justify-center ml-3 transition-colors">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-3 h-3 ml-0.5 text-white/70 group-hover:text-luna-accent">
                        <path fillRule="evenodd" d="M2 10a8 8 0 1116 0 8 8 0 01-16 0zm6.39-2.908a.75.75 0 01.766.027l3.5 2.25a.75.75 0 010 1.262l-3.5 2.25A.75.75 0 018 12.25v-4.5a.75.75 0 01.39-.658z" clipRule="evenodd" />
                      </svg>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </section>
        )}
      </div>

      {/* Auto-play loading overlay (Stremio-style) */}
      {autoPlaying && (
        <div className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-6 bg-black/90">
          {backdropSrc && (
            <img
              src={backdropSrc}
              alt=""
              className="absolute inset-0 w-full h-full object-cover opacity-30 blur-md"
            />
          )}
          <div className="relative z-10 flex flex-col items-center gap-6">
            {detail?.poster && (
              <img
                src={detail.poster}
                alt={title}
                className="w-24 sm:w-32 rounded-xl shadow-2xl ring-1 ring-white/10"
              />
            )}
            <h2 className="text-lg font-semibold text-white text-center">{title}</h2>
            <div className="animate-spin rounded-full h-8 w-8 border-2 border-luna-accent border-t-transparent" />
            <p className="text-sm text-luna-muted">Finding the best source...</p>
          </div>
        </div>
      )}

    </Sidebar>
  );
}
