import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { Search, LayoutGrid, List } from 'lucide-react';
import { useNavigate } from '@/shell/Shell';
import { loadFolderItems } from '@/lib/collections/repository';
import { useTileHalo } from '@/lib/design/artwork-color';
import StrokeSpinner from '@/components/StrokeSpinner';
import LoadingView from '@/components/LoadingView';
import type { MetaPreview } from '@/lib/types';

interface AwardHubScreenProps {
  awardId: string;
}

interface AwardDef {
  id: string;
  hubTitle: string;
  shorthand: string;
  founded: number;
  tint: string;
  about: string;
  tagline: string;
}

const AWARDS: Record<string, AwardDef> = {
  oscars: {
    id: 'oscars', hubTitle: 'Academy Awards', shorthand: 'Oscar', founded: 1929,
    tint: '#D4AF37',
    about: 'The Academy Awards, popularly known as the Oscars, are awards for artistic and technical merit in the film industry. They are regarded as the most prestigious awards in the entertainment industry.',
    tagline: 'The highest honor in cinema',
  },
  golden_globes: {
    id: 'golden_globes', hubTitle: 'Golden Globe Awards', shorthand: 'Golden Globe', founded: 1944,
    tint: '#CFB53B',
    about: 'The Golden Globe Awards are accolades bestowed by the Hollywood Foreign Press Association recognizing excellence in film and television, both domestic and foreign.',
    tagline: 'Celebrating the best in film and television',
  },
  bafta: {
    id: 'bafta', hubTitle: 'BAFTA Awards', shorthand: 'BAFTA', founded: 1949,
    tint: '#E9B862',
    about: 'The British Academy Film Awards are presented by the British Academy of Film and Television Arts to honor the best British and international contributions to film.',
    tagline: 'The best of British and world cinema',
  },
  palme_dor: {
    id: 'palme_dor', hubTitle: 'Palme d\'Or', shorthand: 'Palme', founded: 1955,
    tint: '#2E8B57',
    about: 'The Palme d\'Or is the highest prize awarded at the Cannes Film Festival. It is one of the most prestigious awards in the film industry.',
    tagline: 'Cannes\' highest honor',
  },
  emmy: {
    id: 'emmy', hubTitle: 'Primetime Emmy Awards', shorthand: 'Emmy', founded: 1949,
    tint: '#E8B03B',
    about: 'The Primetime Emmy Awards are presented in recognition of excellence in American primetime television programming.',
    tagline: 'Television\'s finest',
  },
  sag: {
    id: 'sag', hubTitle: 'Screen Actors Guild Awards', shorthand: 'SAG', founded: 1995,
    tint: '#2E8B57',
    about: 'The Screen Actors Guild Awards are accolades given by the Screen Actors Guild to recognize outstanding performances in film and primetime television.',
    tagline: 'Actors honoring actors',
  },
  critics_choice: {
    id: 'critics_choice', hubTitle: 'Critics\' Choice Awards', shorthand: 'Critics\' Choice', founded: 1996,
    tint: '#4A90D9',
    about: 'The Critics\' Choice Movie Awards are presented by the Critics Choice Association to honor the finest in cinematic achievement.',
    tagline: 'Selected by the critics',
  },
  cannes: {
    id: 'cannes', hubTitle: 'Cannes Film Festival', shorthand: 'Cannes', founded: 1946,
    tint: '#C41E3A',
    about: 'The Cannes Film Festival is one of the most prestigious film festivals in the world, held annually in Cannes, France.',
    tagline: 'Where cinema meets the Croisette',
  },
  berlin: {
    id: 'berlin', hubTitle: 'Berlin International Film Festival', shorthand: 'Berlinale', founded: 1951,
    tint: '#E03C31',
    about: 'The Berlin International Film Festival, also called the Berlinale, is one of the world\'s leading film festivals and most reputable media events.',
    tagline: 'The world\'s largest public film festival',
  },
  venice: {
    id: 'venice', hubTitle: 'Venice Film Festival', shorthand: 'Venice', founded: 1932,
    tint: '#005A8B',
    about: 'The Venice Film Festival is the oldest film festival in the world and one of the "Big Three" alongside Cannes and Berlin.',
    tagline: 'The oldest film festival in the world',
  },
};

export function AwardHubScreen({ awardId }: AwardHubScreenProps) {
  const { navigateTo } = useNavigate();
  const award = AWARDS[awardId];
  const [items, setItems] = useState<MetaPreview[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [mode, setMode] = useState<'gallery' | 'list'>('gallery');
  const [searchText, setSearchText] = useState('');
  const [showAllWinners, setShowAllWinners] = useState(false);

  const previewCount = 18;
  const currentYear = new Date().getFullYear();

  const handleMediaSelect = useCallback((item: MetaPreview) => {
    navigateTo(item.type, item.id);
  }, [navigateTo]);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const result = await loadFolderItems(awardId);
        if (!cancelled) {
          setItems(result.items || []);
          setIsLoading(false);
        }
      } catch {
        if (!cancelled) setIsLoading(false);
      }
    }
    load();
    return () => { cancelled = true; };
  }, [awardId]);

  if (!award) {
    return (
      <div className="min-h-screen bg-moonlit-bg flex items-center justify-center">
        <p className="text-white/50">Award not found: {awardId}</p>
      </div>
    );
  }

  const filteredItems = searchText
    ? items.filter(i => i.name.toLowerCase().includes(searchText.toLowerCase()))
    : items;

  const gridItems = mode === 'gallery' && !showAllWinners
    ? items.slice(0, previewCount)
    : filteredItems;

  const heroImages = (() => {
    const seen = new Set<string>();
    const urls: string[] = [];
    for (const item of items) {
      const url = item.poster || item.backdrop || item.banner;
      if (url && !seen.has(url)) {
        seen.add(url);
        urls.push(url);
      }
      if (urls.length >= 10) break;
    }
    return urls;
  })();

  return (
    <div className="min-h-screen bg-moonlit-bg relative">
      <div className="fixed inset-0 pointer-events-none" style={{
        background: `radial-gradient(ellipse 70% 50% at 30% 30%, ${award.tint}33, transparent 60%)`,
      }} />
      <div className="relative z-10">
        {isLoading ? (
          <LoadingView />
        ) : (
          <div className="flex flex-col gap-0">
            <div className="h-[380px] relative overflow-hidden">
              {heroImages.length >= 3 && (
                <div className="absolute inset-0 grid grid-cols-5 grid-rows-2 gap-1 opacity-80"
                  style={{
                    maskImage: 'linear-gradient(to right, transparent 6%, black 62%)',
                  }}
                >
                  {Array.from({ length: 10 }).map((_, i) => {
                    const url = heroImages[i % heroImages.length];
                    return (
                      <img key={i} src={url} alt="" className="w-full h-full object-cover rounded-[10px]" />
                    );
                  })}
                </div>
              )}

              <div className="absolute inset-0"
                style={{
                  background: [
                    `radial-gradient(circle at 16% 30%, ${award.tint}38, transparent 420px)`,
                    'linear-gradient(to right, #0a0a0b, #0a0a0bb3 50%, transparent)',
                    'linear-gradient(to top, #0a0a0b, transparent 50%, #0a0a0b26)',
                  ].join(', '),
                }}
              />

              <div className="absolute bottom-0 left-0 w-full p-7 pb-[26px] flex items-end justify-between">
                <div className="flex flex-col gap-3">
                  <span className="text-[11px] font-bold tracking-[3.5px] text-white/55 uppercase">{award.shorthand}</span>
                  <h1 className="text-[56px] font-semibold font-serif text-white" style={{ textShadow: '0 2px 18px rgba(0,0,0,0.45)' }}>
                    {award.hubTitle}
                  </h1>
                  {award.founded > 0 && (
                    <div className="flex gap-2.5 text-[13px] font-medium">
                      <span className="text-white/70">Founded {award.founded}</span>
                      <span className="text-white/30">·</span>
                      <span style={{ color: award.tint }}>{currentYear - award.founded} years</span>
                    </div>
                  )}
                </div>
                <div className="flex items-center gap-0 mr-6" style={{ color: award.tint, fontSize: '96px', textShadow: '0 4px 12px rgba(0,0,0,0.5)' }}>
                  <span role="img" aria-label="laurel">&#x1F3C6;</span>
                </div>
              </div>
            </div>

            <div className="px-7 pt-5 max-w-[720px]">
              <p className="text-[15px] text-white/72 leading-relaxed">{award.about}</p>
              <p className="text-[11px] font-semibold tracking-[1.5px] text-white/40 uppercase mt-2">{award.tagline}</p>
            </div>

            <div className="flex items-center gap-1 px-7 pt-5.5">
              <div className="flex items-center p-1 bg-white/[0.06] rounded-full border border-white/[0.08]">
                <button
                  type="button"
                  onClick={() => setMode('gallery')}
                  className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-[13px] font-semibold transition-colors ${
                    mode === 'gallery' ? 'text-black' : 'text-white/70'
                  }`}
                  style={mode === 'gallery' ? { backgroundColor: award.tint } : {}}
                >
                  <LayoutGrid size={12} />
                  Gallery
                </button>
                <button
                  type="button"
                  onClick={() => setMode('list')}
                  className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-[13px] font-semibold transition-colors ${
                    mode === 'list' ? 'text-black' : 'text-white/70'
                  }`}
                  style={mode === 'list' ? { backgroundColor: award.tint } : {}}
                >
                  <List size={12} />
                  Full list
                </button>
              </div>
            </div>

            {mode === 'list' && (
              <div className="px-7 pt-4">
                <div className="flex items-center gap-2 px-3.5 py-2.5 bg-white/[0.06] rounded-xl max-w-sm">
                  <Search size={14} className="text-white/40" />
                  <input
                    type="text"
                    placeholder="Search by title..."
                    value={searchText}
                    onChange={e => setSearchText(e.target.value)}
                    className="bg-transparent text-white text-[14px] outline-none w-full placeholder:text-white/30"
                  />
                </div>
              </div>
            )}

            <div className="px-7 pt-[26px]">
              <div className="flex items-center justify-between mb-3.5">
                <h2 className="text-[20px] font-bold font-serif text-white">
                  {mode === 'gallery' ? 'Winning films & shows' : 'All winners'}
                </h2>
                <span className="text-[12px] font-semibold text-white/40">{items.length} titles</span>
              </div>

              <div className="grid gap-4" style={{
                gridTemplateColumns: 'repeat(auto-fill, minmax(130px, 1fr))',
              }}>
                {gridItems.map(item => (
                  <AwardTile key={item.id} item={item} onClick={() => handleMediaSelect(item)} />
                ))}
              </div>

              {mode === 'gallery' && !showAllWinners && items.length > previewCount && (
                <button
                  type="button"
                  onClick={() => setShowAllWinners(true)}
                  className="flex items-center gap-1.5 mx-auto mt-6 px-[18px] py-2.5 text-[13px] font-semibold text-white bg-white/[0.08] rounded-full hover:bg-white/[0.12] transition-colors"
                >
                  View all {items.length} winners
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M6 9l6 6 6-6" /></svg>
                </button>
              )}
            </div>

            <div className="h-14" />
          </div>
        )}
      </div>
    </div>
  );
}

function AwardTile({ item, onClick }: { item: MetaPreview; onClick: () => void }) {
  const [hovering, setHovering] = useState(false);
  const haloColor = useTileHalo(item.poster);

  return (
    <div
      className="flex flex-col gap-[7px] cursor-pointer"
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      onClick={onClick}
    >
      <div
        className="relative aspect-[2/3] w-full rounded-[12px] overflow-hidden border transition-all duration-200"
        style={{
          borderColor: hovering ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.06)',
          transform: hovering ? 'scale(1.03)' : 'scale(1)',
          boxShadow: hovering && haloColor ? `0 0 20px ${haloColor}33, 0 8px 24px rgba(0,0,0,0.5)` : undefined,
        }}
      >
        {item.poster ? (
          <img src={item.poster} alt={item.name} className="w-full h-full object-cover bg-moonlit-elevated" />
        ) : (
          <div className="w-full h-full bg-moonlit-elevated flex items-center justify-center">
            <span className="text-[11px] text-white/40">{item.name}</span>
          </div>
        )}
      </div>
      <p className="text-[12.5px] font-medium text-white truncate">{item.name}</p>
      {item.releaseInfo && (
        <p className="text-[10.5px] font-medium text-white/40">{item.releaseInfo}</p>
      )}
    </div>
  );
}
