import { useState, useEffect, useCallback } from 'react';
import { motion } from 'framer-motion';
import { RefreshCw, Plus, Calendar, Antenna, AlertTriangle, X } from 'lucide-react';
import EmptyState from '@/components/EmptyState';
import StrokeSpinner from '@/components/StrokeSpinner';

interface IPTVSource {
  id: string;
  name: string;
  url: string;
  kind: 'm3u' | 'xtream' | 'epg';
  username?: string;
  password?: string;
}

interface IPTVChannel {
  id: string;
  name: string;
  url: string;
  logo?: string;
  group?: string;
  headers?: Record<string, string>;
}

interface IPTVPlaylist {
  sourceId: string;
  channels: IPTVChannel[];
}

const STORAGE_KEY = 'moonlit.iptvSources';
const PLAYLISTS_KEY = 'moonlit.iptvPlaylists';

function loadSources(): IPTVSource[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function saveSources(sources: IPTVSource[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(sources));
}

function loadPlaylists(): Record<string, IPTVPlaylist> {
  try {
    const raw = localStorage.getItem(PLAYLISTS_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch { return {}; }
}

function savePlaylists(playlists: Record<string, IPTVPlaylist>) {
  localStorage.setItem(PLAYLISTS_KEY, JSON.stringify(playlists));
}

export function LiveTVScreen() {
  const [sources, setSources] = useState<IPTVSource[]>(loadSources);
  const [playlists, setPlaylists] = useState<Record<string, IPTVPlaylist>>(loadPlaylists);
  const [selectedSourceId, setSelectedSourceId] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [editingSource, setEditingSource] = useState<IPTVSource | null>(null);
  const [showGuide, setShowGuide] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const playlistSources = sources.filter(s => s.kind !== 'epg');
  const displayChannels = selectedSourceId
    ? playlists[selectedSourceId]?.channels ?? []
    : Object.values(playlists).flatMap(p => p.channels);

  const groupedChannels = (() => {
    const groups = new Map<string, IPTVChannel[]>();
    for (const c of displayChannels) {
      const group = c.group || 'Uncategorized';
      if (!groups.has(group)) groups.set(group, []);
      groups.get(group)!.push(c);
    }
    return Array.from(groups.entries()).sort(([a], [b]) => a.localeCompare(b));
  })();

  const addSource = useCallback(async (source: IPTVSource) => {
    const newSources = [...sources, source];
    setSources(newSources);
    saveSources(newSources);
    setShowForm(false);
    await refreshSource(source);
  }, [sources]);

  const updateSource = useCallback(async (source: IPTVSource) => {
    const newSources = sources.map(s => s.id === source.id ? source : s);
    setSources(newSources);
    saveSources(newSources);
    setEditingSource(null);
    setShowForm(false);
    await refreshSource(source);
  }, [sources]);

  const removeSource = useCallback((id: string) => {
    const newSources = sources.filter(s => s.id !== id);
    setSources(newSources);
    saveSources(newSources);
    const newPlaylists = { ...playlists };
    delete newPlaylists[id];
    setPlaylists(newPlaylists);
    savePlaylists(newPlaylists);
    if (selectedSourceId === id) setSelectedSourceId(null);
  }, [sources, playlists, selectedSourceId]);

  const refreshSource = async (source: IPTVSource) => {
    try {
      if (source.kind === 'm3u') {
        const res = await fetch(source.url);
        const text = await res.text();
        const channels = parseM3U(text);
        const newPlaylist: IPTVPlaylist = { sourceId: source.id, channels };
        const newPlaylists = { ...playlists, [source.id]: newPlaylist };
        setPlaylists(newPlaylists);
        savePlaylists(newPlaylists);
      }
    } catch (e: any) {
      setErrorMessage(`Failed to load ${source.name}: ${e.message}`);
    }
  };

  const refreshAll = useCallback(async () => {
    setIsRefreshing(true);
    for (const source of sources) {
      if (source.kind !== 'epg') await refreshSource(source);
    }
    setIsRefreshing(false);
  }, [sources]);

  useEffect(() => {
    if (sources.length > 0 && Object.keys(playlists).length === 0) {
      refreshAll();
    }
  }, []);

  return (
    <div className="min-h-screen bg-moonlit-bg">
      {playlistSources.length === 0 ? (
        <EmptyState
          icon={<Antenna size={24} />}
          title="No playlists yet"
          message="Add an M3U playlist or Xtream Codes account to watch live channels."
          action={{ label: 'Add Playlist', onClick: () => setShowForm(true) }}
        />
      ) : (
        <div className="flex flex-col gap-0">
          <div className="flex items-center gap-2.5 px-6 pt-[74px] pb-3">
            <SourceChip
              label="All Channels"
              isSelected={selectedSourceId === null}
              onClick={() => setSelectedSourceId(null)}
            />
            {playlistSources.map(source => (
              <SourceChip
                key={source.id}
                label={source.name}
                isSelected={selectedSourceId === source.id}
                onClick={() => setSelectedSourceId(source.id)}
                onEdit={() => { setEditingSource(source); setShowForm(true); }}
                onDelete={() => removeSource(source.id)}
              />
            ))}
            <div className="flex-1" />
            {isRefreshing && <StrokeSpinner size={16} />}
            <IconButton icon={<Calendar size={14} />} label="TV Guide" onClick={() => setShowGuide(true)} />
            <IconButton icon={<RefreshCw size={14} />} label="Refresh" onClick={refreshAll} />
            <IconButton icon={<Plus size={14} />} label="Add playlist" onClick={() => { setEditingSource(null); setShowForm(true); }} />
          </div>

          {errorMessage && (
            <div className="flex items-center gap-2 mx-6 px-3.5 py-2.5 bg-moonlit-surface rounded-lg mb-2">
              <AlertTriangle size={14} className="text-harbor-gold shrink-0" />
              <span className="text-[12px] text-white/60 line-clamp-2 flex-1">{errorMessage}</span>
              <button type="button" onClick={() => setErrorMessage(null)}>
                <X size={11} className="text-white/40" />
              </button>
            </div>
          )}

          <div className="px-6 py-4">
            {groupedChannels.map(([group, channels]) => (
              <div key={group} className="mb-6">
                <h3 className="text-[13px] font-bold text-white/40 uppercase tracking-[1px] mb-3">{group}</h3>
                <div className="grid gap-2" style={{
                  gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))',
                }}>
                  {channels.map(channel => (
                    <ChannelRow key={channel.id} channel={channel} />
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {showForm && (
        <IPTVSourceFormModal
          source={editingSource}
          onSave={editingSource ? updateSource : addSource}
          onCancel={() => { setShowForm(false); setEditingSource(null); }}
        />
      )}
    </div>
  );
}

function SourceChip({ label, isSelected, onClick, onEdit, onDelete }: {
  label: string; isSelected: boolean;
  onClick: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`text-[12.5px] font-medium px-3.5 py-1.5 rounded-full transition-colors ${
        isSelected ? 'bg-harbor-gold text-black font-semibold' : 'bg-moonlit-surface text-white/60 hover:text-white/80'
      }`}
    >
      {label}
    </button>
  );
}

function IconButton({ icon, label, onClick }: { icon: React.ReactNode; label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="w-[34px] h-[34px] rounded-full bg-moonlit-surface flex items-center justify-center text-white/60 hover:text-white/80 transition-colors"
      title={label}
    >
      {icon}
    </button>
  );
}

function ChannelRow({ channel }: { channel: IPTVChannel }) {
  return (
    <div className="flex items-center gap-3 px-3 py-2 bg-moonlit-surface rounded-lg hover:bg-white/[0.06] transition-colors cursor-pointer">
      {channel.logo ? (
        <img src={channel.logo} alt="" className="w-8 h-8 rounded object-contain bg-black/30" />
      ) : (
        <div className="w-8 h-8 rounded bg-black/30 flex items-center justify-center">
          <Antenna size={14} className="text-white/30" />
        </div>
      )}
      <div className="flex flex-col gap-0.5 min-w-0">
        <span className="text-[13px] font-medium text-white truncate">{channel.name}</span>
        {channel.group && (
          <span className="text-[11px] text-white/40 truncate">{channel.group}</span>
        )}
      </div>
    </div>
  );
}

function parseM3U(content: string): IPTVChannel[] {
  const channels: IPTVChannel[] = [];
  const lines = content.split('\n');
  let currentName = '';
  let currentLogo = '';
  let currentGroup = '';
  let currentUrl = '';
  let currentHeaders: Record<string, string> = {};

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith('#EXTINF:')) {
      const nameMatch = trimmed.match(/,([^,]+)$/);
      if (nameMatch) currentName = nameMatch[1].trim();
      const logoMatch = trimmed.match(/tvg-logo="([^"]*)"/);
      if (logoMatch) currentLogo = logoMatch[1];
      const groupMatch = trimmed.match(/group-title="([^"]*)"/);
      if (groupMatch) currentGroup = groupMatch[1];
      currentHeaders = {};
    } else if (trimmed.startsWith('#EXTVLCOPT:')) {
      const headerMatch = trimmed.match(/#EXTVLCOPT:(?:http-user-agent|http-referrer|http-header)=(.+)/);
    } else if (trimmed && !trimmed.startsWith('#')) {
      currentUrl = trimmed;
      if (currentUrl) {
        channels.push({
          id: `ch-${channels.length}`,
          name: currentName || 'Unknown Channel',
          url: currentUrl,
          logo: currentLogo || undefined,
          group: currentGroup || undefined,
          headers: Object.keys(currentHeaders).length > 0 ? currentHeaders : undefined,
        });
      }
      currentName = '';
      currentLogo = '';
      currentGroup = '';
      currentUrl = '';
      currentHeaders = {};
    }
  }
  return channels;
}

function IPTVSourceFormModal({ source, onSave, onCancel }: {
  source: IPTVSource | null;
  onSave: (source: IPTVSource) => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState(source?.name || '');
  const [url, setUrl] = useState(source?.url || '');
  const [kind, setKind] = useState<IPTVSource['kind']>(source?.kind || 'm3u');
  const [username, setUsername] = useState(source?.username || '');
  const [password, setPassword] = useState(source?.password || '');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSave({
      id: source?.id || `iptv-${Date.now()}`,
      name: name || 'Untitled',
      url,
      kind,
      username: kind === 'xtream' ? username : undefined,
      password: kind === 'xtream' ? password : undefined,
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="w-full max-w-md p-6 bg-moonlit-surface rounded-2xl border border-white/[0.08]"
      >
        <h2 className="text-[18px] font-bold text-white mb-5">{source ? 'Edit Source' : 'Add Playlist'}</h2>
        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div>
            <label className="text-[12px] font-semibold text-white/50 uppercase tracking-[1px] mb-1 block">Type</label>
            <div className="flex gap-2">
              {(['m3u', 'xtream'] as const).map(k => (
                <button
                  key={k}
                  type="button"
                  onClick={() => setKind(k)}
                  className={`px-4 py-1.5 rounded-full text-[13px] font-medium transition-colors ${
                    kind === k ? 'bg-harbor-gold text-black' : 'bg-white/[0.06] text-white/60'
                  }`}
                >
                  {k === 'm3u' ? 'M3U Playlist' : 'Xtream Codes'}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label className="text-[12px] font-semibold text-white/50 uppercase tracking-[1px] mb-1 block">Name</label>
            <input
              type="text"
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="My playlist"
              className="w-full px-3 py-2 bg-white/[0.06] rounded-lg text-white text-[14px] outline-none border border-white/[0.08] focus:border-white/20"
            />
          </div>
          <div>
            <label className="text-[12px] font-semibold text-white/50 uppercase tracking-[1px] mb-1 block">URL</label>
            <input
              type="text"
              value={url}
              onChange={e => setUrl(e.target.value)}
              placeholder={kind === 'm3u' ? 'https://.../playlist.m3u' : 'https://...'}
              className="w-full px-3 py-2 bg-white/[0.06] rounded-lg text-white text-[14px] outline-none border border-white/[0.08] focus:border-white/20"
            />
          </div>
          {kind === 'xtream' && (
            <>
              <div>
                <label className="text-[12px] font-semibold text-white/50 uppercase tracking-[1px] mb-1 block">Username</label>
                <input
                  type="text"
                  value={username}
                  onChange={e => setUsername(e.target.value)}
                  className="w-full px-3 py-2 bg-white/[0.06] rounded-lg text-white text-[14px] outline-none border border-white/[0.08] focus:border-white/20"
                />
              </div>
              <div>
                <label className="text-[12px] font-semibold text-white/50 uppercase tracking-[1px] mb-1 block">Password</label>
                <input
                  type="password"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  className="w-full px-3 py-2 bg-white/[0.06] rounded-lg text-white text-[14px] outline-none border border-white/[0.08] focus:border-white/20"
                />
              </div>
            </>
          )}
          <div className="flex gap-3 justify-end mt-2">
            <button
              type="button"
              onClick={onCancel}
              className="px-4 py-2 text-[13px] font-medium text-white/60 hover:text-white transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!url}
              className="px-5 py-2 text-[13px] font-semibold text-black bg-harbor-gold rounded-full disabled:opacity-40"
            >
              {source ? 'Save' : 'Add'}
            </button>
          </div>
        </form>
      </motion.div>
    </div>
  );
}
