import { useState, useEffect } from 'react';
import { useAuth } from '@/app/AuthProvider';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getLibrary, toggleLibrary as toggleLib, getWatchProgress } from '@/lib/services/api';
import { getLikedItems, removeLiked, refreshUpcoming, LikedItem, UpcomingInfo } from '@/lib/liked';
import { Link } from '@tanstack/react-router';

type MediaFilter = 'all' | 'movie' | 'series';
const POSTER_GRID = { gridTemplateColumns: 'repeat(auto-fill, minmax(155px, 1fr))' } as const;

function PosterCard({ to, params, poster, name, mediaType, progress, onRemove }: { to: string; params: Record<string,string>; poster?: string|null; name: string; mediaType: string; progress?: number; onRemove?: (e: React.MouseEvent) => void }) {
  return <Link to={to as any} params={params as any} className="media-card block w-full"><div className="relative rounded-ml-card overflow-hidden bg-moonlit-elevated mb-2 border border-white/5" style={{ aspectRatio: '2/3' }}>{poster ? <img src={poster} alt={name} loading="lazy" className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"/> : <div className="absolute inset-0 flex items-center justify-center"><span className="text-white/15 text-xs text-center px-2">{name}</span></div>}{onRemove && <button onClick={onRemove} className="absolute top-1.5 right-1.5 w-6 h-6 rounded-full bg-black/70 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity z-10" aria-label="Remove"><svg className="w-3 h-3 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M18 6L6 18M6 6l12 12"/></svg></button>}<div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center"><div className="w-10 h-10 rounded-full bg-white/20 flex items-center justify-center"><svg viewBox="0 0 24 24" fill="white" className="w-5 h-5 ml-0.5"><polygon points="6,4 20,12 6,20"/></svg></div></div>{progress!==undefined && <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-white/10"><div className="h-full bg-white" style={{ width: `${Math.round(progress*100)}%` }}/></div>}</div><p className="text-xs font-medium text-white/80 truncate">{name}</p><p className="text-[10px] text-white/35 mt-0.5">{mediaType === 'series' ? 'Series' : 'Movie'}</p></Link>;
}

function SectionHeader({ title, count, icon }: { title: string; count: number; icon?: React.ReactNode }) {
  return <div className="flex items-center gap-2 mb-3 mt-10 first:mt-0">{icon}<h2 className="text-lg font-bold text-white">{title}</h2><span className="text-sm text-white/35">({count})</span></div>;
}

export default function LibraryPage() {
  const { currentProfile } = useAuth(); const qc = useQueryClient();
  const [wf, setWf] = useState<MediaFilter>('all'); const [lf, setLf] = useState<MediaFilter>('all');
  const [liked, setLiked] = useState<LikedItem[]>(()=>getLikedItems());
  const [upcoming, setUpcoming] = useState<Record<string, UpcomingInfo>>({});
  useEffect(() => { function cb() { setLiked(getLikedItems()); } window.addEventListener('moonlit-liked-changed', cb); return () => window.removeEventListener('moonlit-liked-changed', cb); }, []);
  useEffect(() => { if (liked.length > 0) refreshUpcoming(liked).then(setUpcoming); }, [liked]);

  const { data, isLoading } = useQuery({
    queryKey: ['library', currentProfile?.id], enabled: !!currentProfile,
    queryFn: async () => { const [items, prog] = await Promise.all([getLibrary(currentProfile!.id), getWatchProgress(currentProfile!.id)]); const pm: Record<string,number> = {}; for (const p of prog) { if (p.duration_seconds > 0 && !p.completed) { const b = decodeURIComponent(p.media_id).split(':')[0]; const f = p.position_seconds / p.duration_seconds; if (f > 0.02) pm[b] = f; } } return { items, progressMap: pm }; },
  });

  const watchlist = data?.items ?? []; const progressMap = data?.progressMap ?? {};
  const fwl = wf === 'all' ? watchlist : watchlist.filter(i => i.media_type === wf);
  const upcomingItems = liked.filter(i => upcoming[i.mediaId]);
  const availLiked = liked.filter(i => !upcoming[i.mediaId]);
  const fl = lf === 'all' ? availLiked : availLiked.filter(i => i.mediaType === lf);

  async function handleRemove(mid: string, mt: string) { if (!currentProfile) return; await toggleLib(currentProfile.id, mid, mt); qc.invalidateQueries({ queryKey: ['library', currentProfile.id] }); }

  return (
    <div className="px-6 md:px-10 lg:px-14 pt-24 pb-8 w-full">
      {upcomingItems.length > 0 && <>
        <SectionHeader title="Upcoming" count={upcomingItems.length} icon={<svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 text-white/70"><path fillRule="evenodd" d="M6.75 2.25A.75.75 0 017.5 3v1.5h9V3A.75.75 0 0118 3v1.5h.75a3 3 0 013 3v11.25a3 3 0 01-3 3H5.25a3 3 0 01-3-3V7.5a3 3 0 013-3H6V3a.75.75 0 01.75-.75zm13.5 9a1.5 1.5 0 00-1.5-1.5H5.25a1.5 1.5 0 00-1.5 1.5v7.5a1.5 1.5 0 001.5 1.5h13.5a1.5 1.5 0 001.5-1.5v-7.5z" clipRule="evenodd"/></svg>}/>
        <div className="flex gap-3 overflow-x-auto pb-2 scrollbar-hide mb-2">{upcomingItems.map(item => { const info = upcoming[item.mediaId]; const img = info?.backdrop || item.poster; return <Link key={item.id} to="/browse/$type/$id" params={{ type: item.mediaType, id: item.mediaId }} className="media-card group flex-shrink-0" style={{ width: 248 }}><div className="relative rounded-ml-card overflow-hidden bg-moonlit-elevated border border-white/5" style={{ aspectRatio: '16/9' }}>{img ? <img src={img} alt={item.name} loading="lazy" className="absolute inset-0 w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"/> : <div className="absolute inset-0 bg-white/5"/>}<div className="absolute inset-x-0 bottom-0 h-2/3 bg-gradient-to-t from-black/85 via-black/25 to-transparent"/><div className="absolute top-2 right-2 flex items-center gap-1 px-2 py-1 rounded-full bg-white text-black text-[10px] font-bold shadow-lg max-w-[85%]"><svg viewBox="0 0 24 24" fill="currentColor" className="w-3 h-3 shrink-0"><path d="M6.75 2.25A.75.75 0 017.5 3v1.5h9V3a.75.75 0 011.5 0v1.5h.75a3 3 0 013 3v9.75a3 3 0 01-3 3H5.25a3 3 0 01-3-3V7.5a3 3 0 013-3H6V3a.75.75 0 01.75-.75zM18.75 9H5.25a1.5 1.5 0 00-1.5 1.5v.75h16.5V10.5a1.5 1.5 0 00-1.5-1.5z"/></svg><span className="truncate">{info?.badge}</span></div><div className="absolute inset-x-0 bottom-0 p-3"><p className="text-sm font-semibold text-white truncate drop-shadow">{item.name}</p><p className="text-[11px] text-white/60 mt-0.5">{item.mediaType === 'series' ? 'Series' : 'Movie'}</p></div></div></Link>; })}</div>
      </>}

      <SectionHeader title="Watchlist" count={watchlist.length} icon={<svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 text-white/70"><path d="M6.32 2.577a49.255 49.255 0 0111.36 0c1.497.174 2.57 1.46 2.57 2.93V21a.75.75 0 01-1.085.67L12 18.089l-7.165 3.583A.75.75 0 013.75 21V5.507c0-1.47 1.073-2.756 2.57-2.93z"/></svg>}/>
      {isLoading ? <div className="flex items-center justify-center py-16"><div className="w-7 h-7 rounded-full border-2 border-white/[0.14] border-t-white animate-spin-arc"/></div>
       : watchlist.length === 0 ? <div className="flex flex-col items-center justify-center py-16 text-white/35"><svg viewBox="0 0 24 24" fill="currentColor" className="w-10 h-10 mb-3 opacity-40"><path d="M6.32 2.577a49.255 49.255 0 0111.36 0c1.497.174 2.57 1.46 2.57 2.93V21a.75.75 0 01-1.085.67L12 18.089l-7.165 3.583A.75.75 0 013.75 21V5.507c0-1.47 1.073-2.756 2.57-2.93z"/></svg><p className="text-sm text-white/50">Nothing saved yet</p><p className="text-xs mt-1 text-white/25">Save titles from the browse screen</p></div>
       : <><div className="flex gap-2 mb-5">{(['all','movie','series'] as MediaFilter[]).map(f=><button key={f} onClick={()=>setWf(f)} className={`px-3.5 py-1.5 rounded-full text-xs font-semibold transition-all ${wf===f?'bg-white/20 text-white':'bg-white/8 text-white/50 hover:text-white/80'}`}>{f==='all'?'All':f==='movie'?'Movies':'Series'}</button>)}</div>{fwl.length===0?<p className="text-sm text-white/35 py-8 text-center">No {wf==='movie'?'movies':'series'} saved</p>:<div className="grid gap-3" style={POSTER_GRID}>{fwl.map(item=><PosterCard key={item.id} to="/browse/$type/$id" params={{type:item.media_type,id:item.media_id}} poster={item.poster} name={item.name||item.media_id} mediaType={item.media_type} progress={progressMap[item.media_id]} onRemove={e=>{e.preventDefault();handleRemove(item.media_id,item.media_type);}}/>)}</div>}</>}

      <SectionHeader title="Liked" count={availLiked.length} icon={<svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5 text-red-400"><path d="M11.645 20.91l-.007-.003-.022-.012a15.247 15.247 0 01-.383-.218 25.18 25.18 0 01-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0112 5.052 5.5 5.5 0 0116.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 01-4.244 3.17 15.247 15.247 0 01-.383.219l-.022.012-.007.004-.003.001a.752.752 0 01-.704 0l-.003-.001z"/></svg>}/>
      {availLiked.length===0?<div className="flex flex-col items-center justify-center py-16 text-white/35"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="w-10 h-10 mb-3 opacity-40"><path strokeLinecap="round" strokeLinejoin="round" d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12z"/></svg><p className="text-sm text-white/50">Nothing liked yet</p></div>
       :<><div className="flex gap-2 mb-5">{(['all','movie','series'] as MediaFilter[]).map(f=><button key={f} onClick={()=>setLf(f)} className={`px-3.5 py-1.5 rounded-full text-xs font-semibold transition-all ${lf===f?'bg-white/20 text-white':'bg-white/8 text-white/50 hover:text-white/80'}`}>{f==='all'?'All':f==='movie'?'Movies':'Series'}</button>)}</div>{fl.length===0?<p className="text-sm text-white/35 py-8 text-center">No {lf==='movie'?'movies':'series'} liked</p>:<div className="grid gap-3" style={POSTER_GRID}>{fl.map(item=><PosterCard key={item.id} to="/browse/$type/$id" params={{type:item.mediaType,id:item.mediaId}} poster={item.poster} name={item.name} mediaType={item.mediaType} onRemove={e=>{e.preventDefault();removeLiked(item.mediaId);setLiked(getLikedItems());}}/>)}</div>}</>}
    </div>
  );
}
