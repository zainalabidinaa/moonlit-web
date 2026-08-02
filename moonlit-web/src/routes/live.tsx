import { useCallback, useEffect, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/app/AuthProvider';
import type { IPTVChannel, IPTVPlaylistSource } from '@/lib/iptv';
import { iptvRepository, PLAYLIST_UNGROUPED, channelsByGroup, EPGIndex } from '@/lib/iptv';
import { ChannelTile } from '@/components/ChannelTile';
import { EPGGuide } from '@/components/EPGGuide';
import { IPTVSourceForm } from '@/components/IPTVSourceForm';
import { fetchAndParseXMLTV } from '@/lib/iptv/xmltv-parser';
import type { EPGNowNext, EPGProgram, EPGParseResult } from '@/lib/iptv';

export default function LivePage() {
  const { currentProfile } = useAuth();
  const profileId = currentProfile?.id;
  const [selectedSourceId, setSelectedSourceId] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [showGuide, setShowGuide] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [editingSource, setEditingSource] = useState<IPTVPlaylistSource | undefined>();

  const { data: snap, refetch: refetchSources } = useQuery({
    queryKey: ['iptv-sources', profileId],
    queryFn: async () => {
      if (!profileId) return null;
      await iptvRepository.load(profileId);
      return {
        sources: iptvRepository.sources,
        playlists: iptvRepository.playlists,
        refreshing: iptvRepository.refreshing,
        errorMessage: iptvRepository.errorMessage,
      };
    },
    enabled: !!profileId,
    staleTime: 60_000,
  });

  const { data: epgResult } = useQuery({
    queryKey: ['iptv-epg', profileId, snap?.sources.map(s => s.id + (s.epgUrl || '')).join(',')],
    queryFn: async (): Promise<EPGParseResult> => {
      const sources = iptvRepository.sources;
      const urls = new Set(sources.map(s => s.epgUrl || (s.kind === 'epg' ? s.url : '')).filter(Boolean));
      let mergedPrograms: EPGProgram[] = [];
      const mergedMeta: Record<string, { displayName?: string; icon?: string }> = {};
      for (const url of urls) {
        try {
          const result = await fetchAndParseXMLTV(url);
          mergedPrograms.push(...result.programs);
          for (const [id, meta] of Object.entries(result.channelMeta)) {
            if (!mergedMeta[id]) mergedMeta[id] = meta;
          }
        } catch { /* skip failed feeds */ }
      }
      return { programs: mergedPrograms, channelMeta: mergedMeta };
    },
    enabled: !!profileId && !!snap,
    refetchInterval: 30 * 60_000,
  });

  const epgIndex = useMemo(() => {
    if (!epgResult) return null;
    return new EPGIndex(epgResult.programs, epgResult.channelMeta);
  }, [epgResult]);

  const sources = snap?.sources ?? [];
  const playlists = snap?.playlists ?? {};
  const selectedSource = selectedSourceId ? sources.find(s => s.id === selectedSourceId) : sources[0];
  const playlist = selectedSource ? playlists[selectedSource.id] : undefined;

  const allChannels = useMemo(() => {
    if (!playlist) return [];
    let channels = playlist.channels;
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      channels = channels.filter(ch => ch.name.toLowerCase().includes(q));
    }
    return channels;
  }, [playlist, searchQuery]);

  const groupedChannels = useMemo(() => {
    if (!playlist) return [];
    const grouped = channelsByGroup({ ...playlist, channels: allChannels });
    return grouped;
  }, [playlist, allChannels]);

  const programsByChannel = useMemo(() => {
    const result: Record<string, EPGProgram[]> = {};
    if (!epgIndex || !playlist) return result;
    for (const ch of playlist.channels) {
      const prog = epgIndex.programsFor(ch);
      if (prog) {
        result[ch.tvgId ?? ''] = prog;
        result[ch.id] = prog;
      }
    }
    return result;
  }, [epgIndex, playlist]);

  function toNowNext(channel: IPTVChannel): EPGNowNext | undefined {
    if (!epgIndex) return undefined;
    return epgIndex.nowNextFor(channel);
  }

  function handlePlayChannel(channel: IPTVChannel) {
    const params = new URLSearchParams({ url: channel.url });
    if (channel.headers) {
      for (const [k, v] of Object.entries(channel.headers)) {
        params.append(`header.${encodeURIComponent(k)}`, v);
      }
    }
    window.location.href = `/watch/channel/${channel.id}?${params.toString()}`;
  }

  function handlePlayCatchup(_channel: IPTVChannel, _startMs: number, _endMs: number) {
    // TODO: open in player with catch-up URL
  }

  const handleSaveSource = useCallback(async (source: IPTVPlaylistSource) => {
    if (editingSource) {
      await iptvRepository.updateSource(source);
    } else {
      await iptvRepository.addSource(source);
    }
    setShowForm(false);
    setEditingSource(undefined);
    refetchSources();
  }, [editingSource, refetchSources]);

  const handleEditSource = useCallback((source: IPTVPlaylistSource) => {
    setEditingSource(source);
    setShowForm(true);
  }, []);

  const handleRemoveSource = useCallback(async (id: string) => {
    await iptvRepository.removeSource(id);
    if (selectedSourceId === id) setSelectedSourceId(null);
    refetchSources();
  }, [selectedSourceId, refetchSources]);

  const handleRefresh = useCallback(async () => {
    if (!selectedSource) return;
    await iptvRepository.refresh(selectedSource);
    refetchSources();
  }, [selectedSource, refetchSources]);

  const handleAddSource = useCallback(() => {
    setEditingSource(undefined);
    setShowForm(true);
  }, []);

  const isRefreshing = selectedSourceId ? snap?.refreshing.has(selectedSourceId) : false;

  return (
    <div className="mx-auto min-h-[calc(100vh-56px)] max-w-[1600px] px-4 pb-16 pt-10 sm:px-6 md:px-14">
      <div className="flex items-center justify-between mb-6">
        <div>
          <p className="type-label mb-1 text-moonlit-text-tertiary">Watch now</p>
          <h1 className="type-title-lg text-white">Live TV</h1>
        </div>
        <div className="flex items-center gap-2">
          {playlist && (
            <button
              onClick={() => setShowGuide(true)}
              className="flex items-center gap-1.5 px-3 py-2 rounded-ml-ctl bg-white/10 text-white text-sm font-medium hover:bg-white/20 transition-colors"
            >
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5">
                <rect x="1" y="2" width="12" height="10" rx="1" />
                <line x1="5" y1="2" x2="5" y2="12" />
                <line x1="1" y1="5" x2="12" y2="5" />
              </svg>
              Guide
            </button>
          )}
          <button
            onClick={handleAddSource}
            className="flex items-center gap-1.5 px-3 py-2 rounded-ml-ctl bg-white text-black text-sm font-semibold hover:bg-white/90 transition-colors"
          >
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5">
              <line x1="7" y1="1" x2="7" y2="13" />
              <line x1="1" y1="7" x2="13" y2="7" />
            </svg>
            Add source
          </button>
        </div>
      </div>

      {!sources.length ? (
        <section className="glass-panel mt-10 max-w-xl rounded-ml-lg p-6" aria-labelledby="live-empty-title">
          <h2 id="live-empty-title" className="type-title-sm text-white">No live source connected</h2>
          <p className="mt-2 text-sm leading-6 text-moonlit-text-secondary">
            Add an M3U playlist, Xtream Codes login, or XMLTV EPG feed to get started.
          </p>
          <button onClick={handleAddSource} className="mt-5 inline-flex min-h-11 items-center rounded-ml-ctl bg-white px-5 text-sm font-semibold text-black">
            Add IPTV source
          </button>
        </section>
      ) : (
        <>
          <div className="flex items-center gap-2 mb-6 flex-wrap">
            {sources.map(source => (
              <div key={source.id} className="flex items-center">
                <button
                  onClick={() => setSelectedSourceId(source.id)}
                  className={`px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
                    source.id === selectedSourceId
                      ? 'bg-white text-black'
                      : 'bg-white/10 text-white/60 hover:bg-white/20 hover:text-white'
                  }`}
                >
                  {source.name}
                </button>
                <div className="flex ml-1">
                  <button
                    onClick={() => handleEditSource(source)}
                    className="flex h-6 w-6 items-center justify-center rounded text-white/30 hover:bg-white/10 hover:text-white"
                    aria-label={`Edit ${source.name}`}
                  >
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.2">
                      <path d="M8 1l3 3-8 8H0v-3l8-8z" />
                    </svg>
                  </button>
                  <button
                    onClick={() => handleRemoveSource(source.id)}
                    className="flex h-6 w-6 items-center justify-center rounded text-white/30 hover:bg-red-500/20 hover:text-red-400"
                    aria-label={`Remove ${source.name}`}
                  >
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.2">
                      <line x1="2" y1="2" x2="10" y2="10" />
                      <line x1="10" y1="2" x2="2" y2="10" />
                    </svg>
                  </button>
                </div>
              </div>
            ))}
            {snap?.refreshing.size ? (
              <span className="text-xs text-white/30 ml-2">
                Refreshing...
                <span className="inline-block w-3 h-3 ml-1 rounded-full border border-white/20 border-t-white animate-spin-arc" />
              </span>
            ) : isRefreshing ? null : (
              <button
                onClick={handleRefresh}
                disabled={!selectedSource}
                className="flex items-center gap-1 px-2 py-1 rounded text-xs text-white/40 hover:text-white disabled:opacity-30 transition-colors"
              >
                <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.2">
                  <path d="M1 2v4h4M11 10V6H7" />
                  <path d="M1.5 6A5 5 0 0110.5 6M10.5 6a5 5 0 01-9 0" />
                </svg>
                Refresh
              </button>
            )}
          </div>

          {snap?.errorMessage && (
            <div className="mb-4 px-4 py-3 rounded-ml-sm bg-red-500/10 border border-red-500/20 text-sm text-red-300">
              {snap.errorMessage}
            </div>
          )}

          {!selectedSource || !playlist ? (
            <div className="glass-panel rounded-ml-lg p-6 text-center">
              <p className="text-moonlit-text-secondary text-sm">Select a source or add a new one to see channels.</p>
            </div>
          ) : !playlist.channels.length ? (
            <div className="glass-panel rounded-ml-lg p-10 text-center">
              {isRefreshing ? (
                <div className="flex flex-col items-center gap-3">
                  <div className="w-8 h-8 rounded-full border-2 border-white/20 border-t-white animate-spin-arc" />
                  <p className="text-moonlit-text-secondary text-sm">Loading channels...</p>
                </div>
              ) : (
                <>
                  <p className="text-moonlit-text-secondary text-sm">No channels found for this source.</p>
                  <button
                    onClick={handleRefresh}
                    className="mt-3 text-sm text-white/70 hover:text-white underline"
                  >
                    Try refreshing
                  </button>
                </>
              )}
            </div>
          ) : (
            <>
              <div className="mb-6">
                <input
                  type="search"
                  placeholder="Search channels..."
                  value={searchQuery}
                  onChange={e => setSearchQuery(e.target.value)}
                  aria-label="Search channels"
                  className="w-full max-w-md px-4 py-2.5 bg-[#2a2a2a] rounded text-sm text-white placeholder-white/25 border border-white/10 focus:outline-none focus:ring-1 focus:ring-white/30"
                />
              </div>

              {groupedChannels.length === 0 && searchQuery ? (
                <div className="glass-panel rounded-ml-lg p-6 text-center">
                  <p className="text-moonlit-text-secondary text-sm">No channels matching &quot;{searchQuery}&quot;</p>
                </div>
              ) : (
                groupedChannels.map(group => (
                  <section key={group.group} className="mb-8" aria-labelledby={`group-${group.group}`}>
                    {group.group !== PLAYLIST_UNGROUPED && (
                      <h2 id={`group-${group.group}`} className="text-xs font-bold text-white/30 uppercase tracking-wider mb-3 px-1">
                        {group.group}
                      </h2>
                    )}
                    <div className="flex flex-wrap gap-3">
                      {group.channels.map(channel => (
                        <ChannelTile
                          key={channel.id}
                          channel={channel}
                          nowNext={toNowNext(channel)}
                          onClick={handlePlayChannel}
                        />
                      ))}
                    </div>
                  </section>
                ))
              )}
            </>
          )}
        </>
      )}

      {showForm && (
        <IPTVSourceForm
          source={editingSource}
          onSave={handleSaveSource}
          onClose={() => { setShowForm(false); setEditingSource(undefined); }}
        />
      )}

      {showGuide && playlist && (
        <EPGGuide
          channels={playlist.channels}
          programsByChannel={programsByChannel}
          onPlayChannel={handlePlayChannel}
          onPlayCatchup={handlePlayCatchup}
          onClose={() => setShowGuide(false)}
        />
      )}
    </div>
  );
}
