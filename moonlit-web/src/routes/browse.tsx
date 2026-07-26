import { useState, useEffect, useRef } from 'react';
import { useParams, Link } from '@tanstack/react-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import { usePlayer } from '@/app/PlayerProvider';
import { FusionBackground } from '@/components/FusionBackground';
import { MetaDetail, StreamItem, Season } from '@/lib/types';
import { fetchMeta, fetchStreamsFromAll } from '@/lib/stremio';
import { isInLibrary, toggleLibrary, getWatchProgress } from '@/lib/services/api';
import { cacheStreams } from '@/lib/stream-cache';
import { getPlayableStreamUrl } from '@/lib/player-utils';
import { TMDB_API_KEY } from '@/lib/supabase';
import { useAmbientColors } from '@/lib/design/artwork-color';

const PlayIcon = () => <svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 ml-0.5"><polygon points="6,4 20,12 6,20"/></svg>;
const STREAILER_URL = 'https://9aa032f52161-streailer.baby-beamup.club/%7B%22language%22%3A%22en-US%22%2C%22externalLink%22%3Atrue%2C%22showRecap%22%3Atrue%7D';

export default function DetailPage() {
  const { type, id } = useParams({ strict: false }) as { type: string; id: string };
  const { currentProfile, addons } = useAuth(); const { open: openPlayer } = usePlayer();
  const queryClient = useQueryClient();
  const [streams, setStreams] = useState<StreamItem[]>([]); const [showStreams, setShowStreams] = useState(false);
  const [loadingStreams, setLoadingStreams] = useState(false);
  const [selectedSeason, setSelectedSeason] = useState<Season | null>(null);
  const [selectedEpisodeId, setSelectedEpisodeId] = useState<string | null>(null);
  const prefetchedRef = useRef<string | null>(null);
  const heroRef = useRef<HTMLDivElement>(null); const [heroHeight, setHeroHeight] = useState(0);
  useEffect(() => { if (heroRef.current) setHeroHeight(heroRef.current.getBoundingClientRect().height); }, []);

  const { data, isLoading } = useQuery({
    queryKey: ['browse', type, id, currentProfile?.id], staleTime: 60 * 60 * 1000, enabled: addons.length > 0,
    queryFn: async () => {
      const ma = addons.filter(a => a.resources?.some(r => (typeof r === 'string' ? r : r.name) === 'meta'));
      let detail: MetaDetail | null = null; for (const a of ma) { if (!a.transportUrl) continue; detail = await fetchMeta(a.transportUrl, type, id); if (detail) break; }
      let em: MetaDetail = detail || { id, type, name: decodeURIComponent(id) } as MetaDetail;
      const is = em.seasons?.length ? em.seasons[0] : null;
      let inLib = false, savedPos = 0, trailers: any[] = [], recentEp: any = null, epProg: Record<string,number> = {};
      if (currentProfile) {
        const [lib, prog] = await Promise.all([isInLibrary(currentProfile.id, id), getWatchProgress(currentProfile.id)]);
        inLib = lib; const dec = prog.map((p:any) => ({ ...p, media_id: decodeURIComponent(p.media_id) }));
        const ent = dec.find((p:any) => p.media_id === id || p.media_id.startsWith(id + ':')); if (ent?.position_seconds > 0) savedPos = ent.position_seconds;
        const rep = dec.filter((p:any) => p.media_id.startsWith(id+':') && p.position_seconds > 0 && !p.completed).sort((a:any,b:any) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())[0] ?? null;
        if (rep) recentEp = { mediaId: rep.media_id, positionSec: rep.position_seconds };
        for (const p of dec) { if (p.media_id.startsWith(id+':') && p.duration_seconds > 0) epProg[p.media_id] = Math.min(1, p.position_seconds / p.duration_seconds); }
      }
      try { const r = await fetch(`${STREAILER_URL}/stream/${type}/${id}.json`); const sd = await r.json(); trailers = (sd.streams||[]).filter((s:any)=>s.externalUrl?.includes('youtube')).map((s:any)=>{ const m = s.externalUrl.match(/[?&]v=([^&]+)/)||s.externalUrl.match(/youtu\.be\/([^?]+)/); return { id:(m?m[1]:'')||s.name, title:s.title||s.name||'Trailer', youtubeId:m?m[1]:'' }; }).filter((t:any)=>t.youtubeId); } catch {}
      trailers = [...trailers, ...((em as any).trailers||[]).map((t:any)=>({id:t.id||t.source,title:t.title||'Trailer',youtubeId:t.youtubeId||t.source||''})).filter((t:any)=>t.youtubeId)];
      const seen = new Set<string>(); trailers = trailers.filter((t:any)=>{if(seen.has(t.youtubeId))return false;seen.add(t.youtubeId);return true;});
      try { let tid = (em as any).tmdbId; if (!tid && id.startsWith('tt')) { const fr = await fetch(`https://api.themoviedb.org/3/find/${id}?api_key=${TMDB_API_KEY}&external_source=imdb_id`); if (fr.ok) { const fd = await fr.json(); const h = type==='series'?fd.tv_results?.[0]:fd.movie_results?.[0]; if (h?.id) tid = String(h.id); } }
      if (tid) { const tr = await fetch(`https://api.themoviedb.org/3/${type==='series'?'tv':'movie'}/${tid}?api_key=${TMDB_API_KEY}&append_to_response=credits,similar`);
      if (tr.ok) { const tmdb = await tr.json(); const u: Partial<MetaDetail> = {}; if (tmdb.credits?.cast?.length) u.cast = (tmdb.credits.cast as any[]).slice(0,25).map((c:any)=>({id:String(c.id),name:c.name,photo:c.profile_path?`https://image.tmdb.org/t/p/w185${c.profile_path}`:undefined})); if (!em.moreLikeThis?.length && tmdb.similar?.results?.length) u.moreLikeThis = (tmdb.similar.results as any[]).slice(0,15).map((r:any)=>({id:String(r.id),type,name:r.name||r.title||'Unknown',poster:r.poster_path?`https://image.tmdb.org/t/p/w342${r.poster_path}`:undefined,releaseInfo:(r.first_air_date||r.release_date||'').slice(0,4)})); if (Object.keys(u).length) em = { ...em, ...u }; } } } catch {}
      return { meta: em, inLib, savedPos, trailers, initialSeason: is, recentEp, epProg };
    },
  });

  const detail = data?.meta ?? null; const inLibrary = data?.inLib ?? false;
  const savedPositionSeconds = data?.savedPos ?? 0; const trailers = data?.trailers ?? [];
  const recentEp = data?.recentEp ?? null; const epProgress = data?.epProg ?? {};
  if (data?.initialSeason && !selectedSeason) setSelectedSeason(data.initialSeason);

  async function handleToggleLibrary() { if (!currentProfile || !detail) return; await toggleLibrary(currentProfile.id, id, type, detail.name, detail.poster); queryClient.invalidateQueries({ queryKey: ['browse', type, id, currentProfile.id] }); }

  useEffect(() => { if (!addons.length) return; const sid = selectedEpisodeId || id; const ck = `${type}:${sid}`; const ak = addons.map(a=>a.id).join(','); const fk = `${ck}:${ak}`; if (prefetchedRef.current === fk) return; prefetchedRef.current = fk; fetchStreamsFromAll(type, sid, addons).then(f=>{if(f.length>0)cacheStreams(ck,f);}).catch(()=>{}); }, [addons, id, type, selectedEpisodeId]);

  async function loadStreams(sid?: string) { const s = sid || id; setShowStreams(true); setLoadingStreams(true); setStreams([]); const all = await fetchStreamsFromAll(type, s, addons); setStreams(all); setLoadingStreams(false); }
  function handlePlay(stream: StreamItem) { const u = getPlayableStreamUrl(stream); if (!u) return; const mid = selectedEpisodeId || id; cacheStreams(`${type}:${mid}`, streams); const ep = selectedEpisodeId && selectedSeason ? selectedSeason.episodes?.find(e=>e.id===selectedEpisodeId) : null; const wt = ep ? `${detail?.name||''} — S${selectedSeason!.number}:E${ep.episode}: ${ep.title}` : (detail?.name||''); openPlayer({ type, id: mid, streamUrl: u, streams, metadata: { mediaId: mid, mediaType: type, title: wt, logo: detail?.logo??undefined, poster: detail?.poster??undefined, background: detail?.background??undefined }, startPosition: savedPositionSeconds > 0 ? savedPositionSeconds : undefined }); }
  function handleAutoPlay(sid?: string) { const s = sid || id; const ep = sid && selectedSeason ? selectedSeason.episodes?.find(e=>e.id===sid) : null; const wt = ep ? `${detail?.name||''} — S${selectedSeason!.number}:E${ep.episode}: ${ep.title}` : (detail?.name||''); openPlayer({ type, id: s, metadata: { mediaId: s, mediaType: type, title: wt, logo: detail?.logo??undefined, poster: detail?.poster??undefined, background: detail?.background??undefined }, startPosition: savedPositionSeconds > 0 ? savedPositionSeconds : undefined }); }

  if (isLoading) return <div className="flex items-center justify-center min-h-[60vh]"><div className="w-7 h-7 rounded-full border-2 border-white/[0.14] border-t-white animate-spin-arc"/></div>;

  const backdropSrc = detail?.background || detail?.poster;
  const ambient = useAmbientColors(backdropSrc);
  const title = detail?.name || decodeURIComponent(id);
  const isSeries = type === 'series';

  return (
    <>
      <FusionBackground backdropUrl={backdropSrc} heroHeight={heroHeight} />
      <div ref={heroRef} className="-mt-14 relative min-h-[65vh] flex items-end">
        {backdropSrc && <div className="absolute inset-0 overflow-hidden"><img src={backdropSrc} alt="" className="w-full h-full object-cover object-[center_20%]"/></div>}
        {ambient && <div className="absolute inset-0 pointer-events-none overflow-hidden" style={{ opacity: 0.45, transition: 'opacity 0.9s ease-in-out' }}><div className="absolute inset-0" style={{ background: `linear-gradient(to bottom, ${ambient[0]}66, transparent 60%)`, transition: 'background 0.9s ease-in-out' }}/><div className="absolute inset-0" style={{ background: `radial-gradient(circle at 70% 0%, ${ambient[1]}52, transparent 50%)`, transition: 'background 0.9s ease-in-out' }}/></div>}
        <div className="absolute inset-0 bg-gradient-to-t from-[#0D0D0D] via-[#0D0D0D]/30 to-transparent"/>
        <div className="absolute inset-0 bg-gradient-to-r from-[#0D0D0D]/80 via-transparent to-transparent"/>
        <div className="relative z-10 w-full px-8 md:px-14 pt-28 pb-14 max-w-4xl">
          <div className="max-w-xl">
            {detail?.logo ? <img src={detail.logo} alt={title} className="h-14 sm:h-20 object-contain object-left mb-3"/> : <h1 className="text-3xl sm:text-5xl font-bold tracking-tight mb-3 text-white">{title}</h1>}
            <div className="flex items-center gap-3 text-sm text-white/50 mb-4 flex-wrap">{(detail as any)?.year&&<span>{(detail as any).year}</span>}{detail?.runtime&&<span>{detail.runtime}</span>}{detail?.imdbRating&&<span className="rating-badge"><svg viewBox="0 0 20 20" fill="currentColor" className="w-3.5 h-3.5"><path fillRule="evenodd" d="M10.868 2.884c-.321-.772-1.415-.772-1.736 0l-1.83 4.401-4.753.381c-.833.067-1.171 1.107-.536 1.651l3.62 3.102-1.106 4.637c-.194.813.691 1.456 1.405 1.02L10 15.591l4.069 2.485c.713.436 1.598-.207 1.404-1.02l-1.106-4.637 3.62-3.102c.635-.544.297-1.584-.536-1.65l-4.752-.382-1.831-4.401z" clipRule="evenodd"/></svg>{detail.imdbRating}</span>}</div>
            {detail?.genres && <div className="flex flex-wrap gap-2 mb-4">{detail.genres.slice(0,5).map(g=><span key={g} className="px-3 py-1 rounded-full bg-white/8 border border-white/10 text-xs text-white/60 font-medium">{g}</span>)}</div>}
            {detail?.description && <p className="text-sm text-white/50 leading-relaxed mb-6 line-clamp-3">{detail.description}</p>}
            <div className="flex items-center gap-3">
              {!isSeries ? <button onClick={()=>handleAutoPlay()} className="btn-primary"><PlayIcon/> Play</button>
               : recentEp ? <button onClick={()=>handleAutoPlay(recentEp.mediaId)} className="btn-primary"><PlayIcon/> Continue</button>
               : detail?.seasons?.[0]?.episodes?.[0] ? <button onClick={()=>handleAutoPlay(detail.seasons![0].episodes![0].id)} className="btn-primary"><PlayIcon/> Play First</button> : <div/>}
              <button onClick={handleToggleLibrary} aria-label={inLibrary?'Remove':'Add'} className={`w-11 h-11 flex items-center justify-center rounded-full border transition-all active:scale-95 ${inLibrary?'bg-white/15 border-white/20 text-white':'bg-white/5 border-white/8 text-white/60 hover:bg-white/10 hover:text-white'}`}><svg viewBox="0 0 24 24" fill={inLibrary?'currentColor':'none'} stroke="currentColor" strokeWidth="1.5" className="w-5 h-5"><path strokeLinecap="round" strokeLinejoin="round" d="M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0111.186 0z"/></svg></button>
              {!isSeries && <button onClick={()=>loadStreams()} className="w-11 h-11 flex items-center justify-center rounded-full bg-white/5 border border-white/8 text-white/60 hover:bg-white/10 hover:text-white transition-all active:scale-95"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="w-5 h-5"><path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"/></svg></button>}
              {trailers.length>0&&<a href={`https://www.youtube.com/watch?v=${trailers[0].youtubeId}`} target="_blank" rel="noopener noreferrer" className="w-11 h-11 flex items-center justify-center rounded-full bg-white/5 border border-white/8 text-white/60 hover:bg-white/10 hover:text-white transition-all active:scale-95"><svg viewBox="0 0 24 24" fill="currentColor" className="w-4 h-4 ml-0.5"><polygon points="5,3 19,12 5,21"/></svg></a>}
            </div>
          </div>
        </div>
      </div>

      <div className="px-8 md:px-14 pb-16 max-w-4xl space-y-10">
        {!isSeries&&trailers.length>0&&<section><h3 className="text-sm font-bold text-white mb-4">Trailers & Clips</h3><div className="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">{trailers.map(t=><a key={t.id} href={`https://www.youtube.com/watch?v=${t.youtubeId}`} target="_blank" rel="noopener noreferrer" className="flex-shrink-0 w-52 group cursor-pointer"><div className="relative w-52 h-[117px] rounded-ml-card overflow-hidden bg-moonlit-elevated mb-2 border border-white/5"><img src={`https://img.youtube.com/vi/${t.youtubeId}/mqdefault.jpg`} alt={t.title} className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-[1.025]" loading="lazy"/><div className="absolute bottom-2 right-2 bg-red-600/90 text-white text-[9px] font-bold px-1.5 py-0.5 rounded">YouTube</div></div><p className="text-sm font-semibold text-white line-clamp-1">{t.title}</p></a>)}</div></section>}
        {detail?.cast&&<section><h3 className="text-sm font-bold text-white mb-4">Cast</h3><div className="flex gap-5 overflow-x-auto pb-3 scrollbar-hide">{detail.cast.slice(0,25).map(p=><div key={p.name} className="flex-shrink-0 text-center w-20"><div className="w-20 h-20 rounded-full bg-white/5 mx-auto mb-2 overflow-hidden ring-1 ring-white/10">{p.photo?<img src={p.photo} alt={p.name} className="w-full h-full object-cover" loading="lazy"/>:<div className="w-full h-full flex items-center justify-center text-base font-semibold text-white/60">{p.name[0]}</div>}</div><p className="text-xs text-white/60 truncate">{p.name}</p></div>)}</div></section>}
        {(()=>{const s=(detail?.moreLikeThis??[]).filter(i=>i.id.startsWith('tt'));if(s.length===0)return null;return(<section className="mb-8"><h3 className="text-sm font-bold text-white mb-4">More Like This</h3><div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-3">{s.slice(0,15).map(i=><Link key={i.id} to="/browse/$type/$id" params={{type:i.type,id:i.id}} className="group cursor-pointer"><div className="relative aspect-[2/3] rounded-ml-card overflow-hidden bg-moonlit-elevated mb-2 border border-white/5">{i.poster?<img src={i.poster} alt={i.name} className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105" loading="lazy"/>:<div className="absolute inset-0 flex items-center justify-center text-white/20 text-xs font-semibold text-center px-2">{i.name}</div>}</div><p className="text-xs font-medium text-white/80 truncate">{i.name}</p>{i.releaseInfo&&<p className="text-[10px] text-white/40 mt-0.5">{i.releaseInfo}</p>}</Link>)}</div></section>)})()}
        {showStreams&&<section><h3 className="text-sm font-semibold text-white mb-4">Sources {!loadingStreams&&streams.length>0&&<span className="text-white/30 font-normal">({streams.length})</span>}</h3>{loadingStreams?<div className="flex items-center gap-2 text-white/30 text-sm"><div className="w-5 h-5 rounded-full border-2 border-white/[0.14] border-t-white animate-spin-arc"/>Fetching...</div>:streams.length===0?<p className="text-white/30 text-sm">No sources found</p>:<div className="space-y-1">{streams.slice(0,30).map((s,i)=><button key={s.url?`${s.url}-${i}`:`stream-${i}`} onClick={()=>handlePlay(s)} className="w-full text-left p-3 hover:bg-white/5 rounded-ml-sm transition-all flex items-center justify-between group"><div className="min-w-0"><p className="text-sm text-white truncate">{s.title||s.name||s.description||'Unknown'}</p><p className="text-xs text-white/30 mt-0.5">{s.addonName}</p></div><div className="flex-shrink-0 w-7 h-7 rounded-full bg-white/10 group-hover:bg-white/20 flex items-center justify-center ml-3 transition-colors opacity-0 group-hover:opacity-100"><PlayIcon/></div></button>)}</div>}</section>}
      </div>

      {isSeries&&detail?.seasons&&<section className="mb-10 px-8 md:px-14"><h3 className="text-sm font-semibold text-white mb-4">Episodes</h3><div className="flex gap-2 overflow-x-auto pb-2 mb-5 scrollbar-hide">{detail.seasons.map(s=><button key={s.id} onClick={()=>{setSelectedSeason(s);setShowStreams(false);setSelectedEpisodeId(null);}} className={`flex-shrink-0 px-4 py-2 rounded-full text-sm transition-all ${selectedSeason?.id===s.id?'bg-white text-black font-bold':'bg-white/5 text-white/60 font-medium hover:bg-white/10 hover:text-white'}`}>Season {s.number}</button>)}</div>
      {selectedSeason?.episodes&&<div className="flex gap-4 overflow-x-auto pb-3 scrollbar-hide">{selectedSeason.episodes.map(ep=><button key={ep.id} onClick={()=>{setSelectedEpisodeId(ep.id);handleAutoPlay(ep.id);}} className={`flex-shrink-0 w-52 text-left group rounded-ml-card overflow-hidden transition-all ${selectedEpisodeId===ep.id?'ring-2 ring-white/60':''}`}><div className="relative w-full aspect-video bg-moonlit-elevated rounded-ml-card overflow-hidden mb-2 border border-white/5">{ep.thumbnail?<img src={ep.thumbnail} alt={ep.title} className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-[1.025]" loading="lazy"/>:<div className="absolute inset-0 flex items-center justify-center text-white/15 text-sm font-semibold">E{ep.episode}</div>}{epProgress[ep.id]!==undefined&&epProgress[ep.id]>0&&<div className="absolute bottom-0 left-0 right-0 h-0.5 bg-white/20"><div className="h-full bg-white" style={{width:`${Math.round(epProgress[ep.id]*100)}%`}}/></div>}</div><p className="text-[10px] text-white/40 mb-0.5">Episode {ep.episode}</p>{ep.released&&<p className="text-[10px] text-white/30 mb-0.5">{new Date(ep.released).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'})}</p>}<p className="text-sm font-semibold text-white truncate">{ep.title}</p>{ep.overview&&<p className="text-xs text-white/40 mt-1 line-clamp-2 leading-relaxed">{ep.overview}</p>}</button>)}</div>}
      </section>}
      {isSeries&&<div className="px-8 md:px-14 pb-8 max-w-4xl">{trailers.length>0&&<section><h3 className="text-sm font-bold text-white mb-4">Trailers & Clips</h3><div className="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">{trailers.map(t=><a key={t.id} href={`https://www.youtube.com/watch?v=${t.youtubeId}`} target="_blank" rel="noopener noreferrer" className="flex-shrink-0 w-52 group cursor-pointer"><div className="relative w-52 h-[117px] rounded-ml-card overflow-hidden bg-moonlit-elevated mb-2 border border-white/5"><img src={`https://img.youtube.com/vi/${t.youtubeId}/mqdefault.jpg`} alt={t.title} className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-[1.025]" loading="lazy"/><div className="absolute bottom-2 right-2 bg-red-600/90 text-white text-[9px] font-bold px-1.5 py-0.5 rounded">YouTube</div></div><p className="text-sm font-semibold text-white line-clamp-1">{t.title}</p></a>)}</div></section>}</div>}
    </>
  );
}
